#include <chrono>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
#include <thread>
#include <future>
#include "isolated_engine.h"
#include "trace_context.h"
#include "worker_rpc_validation.h"
static FILE* log_file;
static int count = 0;
static void Check(bool yes, const char* label) {
  std::fprintf(log_file,"TraceID=isolated-native-tests [%s] %s\n",yes?"PASS":"FAIL",label);std::fflush(log_file);
  if (!yes) std::exit(2);count++;
}
static std::string Read(const std::string& path) {
  std::ifstream in(path,std::ios::binary);return {std::istreambuf_iterator<char>(in),{}};
}
static venera::IsolatedControl Control(int milliseconds=3000) {
  venera::IsolatedControl value;
  value.trace="isolated-native-tests";value.deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(milliseconds);
  return value;
}
static venera::PixelSurface Input() {
  venera::PixelSurface pixels;pixels.width=3;pixels.height=5;pixels.rgba.resize(60);
  for(size_t y=0;y<5;y++)for(size_t x=0;x<3;x++){
    size_t i=(y*3+x)*4;pixels.rgba[i]=11+y*11;pixels.rgba[i+1]=x*30;pixels.rgba[i+2]=99;pixels.rgba[i+3]=255;
  }return pixels;
}
int main(int argc,char**argv){
  if(argc!=4)return 3;
  log_file=std::fopen(argv[3],"w");if(!log_file)return 4;
  const std::string init=Read(argv[1]),html=Read(argv[2]);
  std::fprintf(log_file,"TraceID=isolated-native-tests [请求到达] Production worker core + unmodified init.js; no app/user data\n");
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;Check(engine.Init(init,"",&error),"isolated image init");
    venera::IsolatedResult result;
    Check(engine.Modify("let modifyImage=image=>{globalThis.privateMarker=99;let out=Image.empty(image.width,image.height);"
      "out.fillImageRangeAt(0,0,image,0,2,image.width,3);out.fillImageRangeAt(0,3,image,0,0,image.width,2);return out;}",
      Input(),false,&result),"JM-style block reorder succeeds");
    const int rows[]={33,44,55,11,22};
    bool pixels=true;
    for(size_t y=0;y<5;y++)for(size_t x=0;x<3;x++){
      size_t i=(y*3+x)*4;pixels&=result.pixels.rgba[i]==rows[y]&&result.pixels.rgba[i+1]==x*30&&result.pixels.rgba[i+2]==99&&result.pixels.rgba[i+3]==255;
    }Check(pixels,"RGBA oracle/remainder exactly matches");
  }
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;Check(engine.Init(init,"",&error),"fresh independent image engine");
    venera::IsolatedResult result;
    Check(engine.Modify("let modifyImage=i=>{if(typeof privateMarker!=='undefined')throw Error('global leaked');return i.copyRange(0,0,3,5).copyAndRotate90();}",
      Input(),false,&result),"globals do not leak and crop+rotate succeeds");
    Check(result.pixels.width==5&&result.pixels.height==3,"rotated dimensions correct");
    bool correct=true;
    for(size_t y=0;y<3;y++)for(size_t x=0;x<5;x++)correct&=result.pixels.rgba[(y*5+x)*4]==11+(4-x)*11;
    Check(correct,"clockwise rotation pixels exact");
  }
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;engine.Init(init,"",&error);venera::IsolatedResult result;
    auto input=Input();for(size_t i=0;i<input.rgba.size();i+=4){input.rgba[i]=32;input.rgba[i+1]=16;input.rgba[i+2]=8;input.rgba[i+3]=128;}
    Check(engine.Modify("let modifyImage=i=>i;",std::move(input),true,&result),"premultiplied conversion worker path");
    Check(result.pixels.rgba[0]==64&&result.pixels.rgba[1]==32&&result.pixels.rgba[2]==16&&result.pixels.rgba[3]==128,"straight alpha channels correct");
  }
  for(const char* script:{"let modifyImage=i=>i.copyRange(3,0,1,1);","let modifyImage=i=>Image.empty(2147483648,2147483648);",
      "let modifyImage=i=>null;","let modifyImage=i=>Promise.resolve(i);"}){
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;engine.Init(init,"",&error);venera::IsolatedResult result;
    Check(!engine.Modify(script,Input(),false,&result),"invalid/bounds/overflow/async image result rejected");
  }
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;Check(engine.Init(init,"",&error),"timeout engine successfully initialized");venera::IsolatedResult result;
    control.deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(50);
    auto before=std::chrono::steady_clock::now();
    Check(!engine.Modify("let modifyImage=i=>{while(true){}return i;};",Input(),false,&result),"infinite image script interrupted");
    Check(std::chrono::steady_clock::now()-before<std::chrono::seconds(2),"timeout actually bounds CPU");
  }
  {
    auto control=Control();control.cancelled.store(true);
    venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;Check(!engine.Init(init,"",&error),"cancelled task cannot execute bootstrap");
  }
  // Compute foundation: original positional args and independent structured types,
  // no claim that the production full RPC/persistent-event-loop API is complete.
  {
    venera::QuickJsRuntime source;
    JSValue args;std::string error;
    source.EvaluateRaw("[new Uint8Array([9,1,2,8]).subarray(1,3),new Map([['x',40]])]","<args>",&args,&error);
    std::vector<uint8_t> blob;Check(venera::IsolatedEngine::Serialize(source.context(),args,&blob,&error),"structured compute args serialized");
    JS_FreeValue(source.context(),args);
    auto control=Control();venera::IsolatedEngine worker(&control,64*1024*1024,0);
    Check(worker.Init(init,html,&error),"compute init + original HTML engine");
    venera::IsolatedResult result;
    Check(worker.Compute("(bytes,map)=>[bytes[0]+bytes[1]+map.get('x'),typeof ComicSource,APP.version]",blob,&result),"compute positional structured arguments");
    JSValue decoded=JS_ReadObject(source.context(),result.serialized.data(),result.serialized.size(),JS_READ_OBJ_REFERENCE);
    Check(source.JsonStringify(decoded)=="[43,\"function\",\"1.17.0\"]","compute result roundtrip real engine");
    JS_FreeValue(source.context(),decoded);
    venera::IsolatedResult failed;
    Check(!worker.Compute("42",blob,&failed),"compute nonfunction rejected");
  }
  Check(venera::IsolatedImagePixelBudget(60)==32*1024*1024,"small image has bounded 32MiB floor, not unconditional 128MiB output reserve");
  Check(venera::IsolatedImagePixelBudget(10*1024*1024)==40*1024*1024,"image working budget scales with four input surfaces");
  Check(venera::IsolatedImagePixelBudget(80*1024*1024)==128*1024*1024,"large image working budget never exceeds128MiB");
  Check(venera::IsolatedImagePixelBudget(128*1024*1024+1)==0,"oversized pixel input has no admission budget");
  Check(4*(60+venera::IsolatedImagePixelBudget(60)+1024)<384*1024*1024,"four small-image result reservations fit production transport budget");
  // Exercise the exact production RPC tree guard independently of NAPI.
  {
    venera::QuickJsRuntime runtime; std::string error;
    struct TreeCase { const char* code; bool allowed; const char* label; };
    for(const TreeCase test:{
      TreeCase{"({method:'http',headers:{a:'b'},data:new Uint8Array([1,2])})",true,"ordinary worker RPC byte/tree allowed"},
      TreeCase{"(()=>{const x={};x.self=x;return x})()",false,"worker RPC cycle rejected before UI conversion"},
      TreeCase{"({fn:()=>1})",false,"worker RPC remote callback explicitly rejected"},
      TreeCase{"({get value(){throw Error('getter must not run')}})",false,"worker RPC accessor rejected without invocation"},
      TreeCase{"new Proxy({}, {})",false,"worker RPC proxy rejected"},
      TreeCase{"new Map([['x',1]])",false,"worker RPC exotics not flattened silently"},
      TreeCase{"new Array(1000000)",false,"worker RPC sparse length bounded"},
      TreeCase{"(()=>{let x={};for(let i=0;i<70;i++)x={next:x};return x})()",false,"worker RPC depth bounded"},
      TreeCase{"Array.from({length:65537},()=>1)",false,"worker RPC node count bounded"},
      TreeCase{"new ArrayBuffer(64*1024*1024+1)",false,"worker RPC binary byte cap bounded"},
      TreeCase{"(()=>{const x={n:1};return [x,x]})()",true,"worker RPC acyclic shared subtree allowed"}
    }){
      JSValue value;
      Check(runtime.EvaluateRaw(test.code,"<rpc-tree>",&value,&error),"RPC guard input executes in actual QuickJS");
      Check(venera::CheckWorkerRpcTree(runtime.context(),value)==test.allowed,test.label);
      JS_FreeValue(runtime.context(),value);
    }
  }
  // These tests invoke the production C++ engine, not a JavaScript model.
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,100);
    std::string error;Check(engine.Init(init,"",&error),"small pixel-budget bootstrap");
    venera::IsolatedResult result;
    Check(!engine.Modify("let modifyImage=i=>i.copyAndRotate90();",Input(),false,&result),"aggregate input+new surface pixel budget enforced");
    Check(result.pixels.rgba.empty(),"pixel failure never returns partial/unscrambled output");
  }
  {
    auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,128*1024*1024);
    std::string error;engine.Init(init,"",&error);venera::IsolatedResult result;
    Check(!engine.Modify("let modifyImage=i=>{for(let n=0;n<20000;n++){try{i.width;}catch(e){}}return i;}",Input(),false,&result),"bridge call budget enforced even when caught by script");
    bool clean=true;for(auto& line:result.audit)clean &= line.find("20000")==std::string::npos;
    Check(clean,"worker audit excludes source code");
  }
  {
    venera::QuickJsRuntime source;JSValue args;std::string error;
    source.EvaluateRaw("[]","<empty-args>",&args,&error);std::vector<uint8_t> blob;
    venera::IsolatedEngine::Serialize(source.context(),args,&blob,&error);JS_FreeValue(source.context(),args);
    for(const char* code:{"async()=>{await Promise.resolve();return 42;}","()=>{const o={};o.self=o;return [o,o,new Set([1,2]),new Date(0),123n];}"}){
      auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,0);
      Check(engine.Init(init,html,&error),"async/structured engine bootstrap");venera::IsolatedResult result;
      Check(engine.Compute(code,blob,&result),"async/cyclic structured compute result accepted");
      JSValue decoded=JS_ReadObject(source.context(),result.serialized.data(),result.serialized.size(),JS_READ_OBJ_REFERENCE);
      Check(!JS_IsException(decoded),"structured result read by caller");
      if(JS_IsArray(decoded)){
        JSValue first=JS_GetPropertyUint32(source.context(),decoded,0),second=JS_GetPropertyUint32(source.context(),decoded,1);
        JSValue self=JS_GetPropertyStr(source.context(),first,"self");
        Check(JS_VALUE_GET_PTR(first)==JS_VALUE_GET_PTR(second)&&JS_VALUE_GET_PTR(first)==JS_VALUE_GET_PTR(self),"shared and cyclic object identity preserved");
        JS_FreeValue(source.context(),first);JS_FreeValue(source.context(),second);JS_FreeValue(source.context(),self);
      }else{int32_t n=0;JS_ToInt32(source.context(),&n,decoded);Check(n==42,"await compute value exact");}
      JS_FreeValue(source.context(),decoded);
    }
    for(const char* code:{"()=>()=>1","()=>Promise.reject(Error('synthetic private error'))","()=>new Promise(()=>{})","()=>{throw Error('synthetic private error')}"}){
      auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,0);engine.Init(init,"",&error);
      venera::IsolatedResult result;Check(!engine.Compute(code,blob,&result),"function/pending/rejected/thrown compute result rejected");
      bool clean=true;for(auto& line:result.audit)clean &= line.find("synthetic private error")==std::string::npos;
      Check(clean,"audit never contains exception original text");
    }
    for(const char* code:{"()=>{while(true){}}","()=>{const f=()=>Promise.resolve().then(f);f();return 1;}"}){
      auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,0);engine.Init(init,"",&error);
      control.deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(50);
      venera::IsolatedResult result;auto before=std::chrono::steady_clock::now();
      Check(!engine.Compute(code,blob,&result),"CPU loop and self-requeuing microtask timeout rejected");
      Check(std::chrono::steady_clock::now()-before<std::chrono::seconds(2),"JS and job-loop deadline bounded");
    }
    {
      auto control=Control();venera::IsolatedEngine engine(&control,2*1024*1024,0);
      Check(engine.Init(init,"",&error),"small JS-heap bootstrap succeeds");venera::IsolatedResult result;
      Check(!engine.Compute("()=>new Uint8Array(8*1024*1024)",blob,&result),"QuickJS heap allocation limit enforced");
    }
    {
      auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,0);engine.Init(init,"",&error);
      std::thread cancel([&control]{std::this_thread::sleep_for(std::chrono::milliseconds(40));control.cancelled.store(true);});
      venera::IsolatedResult result;bool ok=engine.Compute("()=>{while(true){}}",blob,&result);cancel.join();
      Check(!ok&&control.cancelled.load(),"atomic cancellation interrupts already-running CPU job");
    }
    {
      auto control=Control();std::string observed;
      venera::IsolatedEngine engine(&control,64*1024*1024,0,[&observed](JSContext*ctx,JSValueConst){
        observed=venera::TraceOf(ctx);return JS_NewSettledPromise(ctx,false,JS_NewInt32(ctx,42));});
      engine.Init(init,"",&error);venera::IsolatedResult result;
      Check(engine.Compute("async()=>await sendMessage({method:'delay',time:1})",blob,&result),"real engine await host RPC result");
      Check(observed==control.trace,"host RPC retains request trace");
    }
    std::vector<std::future<bool>> jobs;
    for(int id=0;id<4;id++)jobs.push_back(std::async(std::launch::async,[&,id]{
      auto control=Control();control.trace="parallel-"+std::to_string(id);
      venera::IsolatedEngine engine(&control,64*1024*1024,0);std::string local;
      if(!engine.Init(init,"",&local))return false;venera::IsolatedResult result;
      return engine.Compute("()=>{globalThis.workerMarker=1;return 42;}",blob,&result);
    }));
    bool all=true;for(auto& job:jobs)all &= job.get();Check(all,"four independent native engines compute concurrently");
    {
      auto control=Control();venera::IsolatedEngine engine(&control,64*1024*1024,0);engine.Init(init,"",&error);
      venera::IsolatedResult result;Check(engine.Compute("()=>typeof workerMarker",blob,&result),"fresh job does not inherit another job globals");
      JSValue decoded=JS_ReadObject(source.context(),result.serialized.data(),result.serialized.size(),JS_READ_OBJ_REFERENCE);
      Check(source.JsonStringify(decoded)=="\"undefined\"","job-global isolation exact");JS_FreeValue(source.context(),decoded);
    }
  }
  std::fprintf(log_file,"TraceID=isolated-native-tests [响应返回] ISOLATED_NATIVE_PASS assertions=%d\n",count);
  std::fclose(log_file);std::printf("ISOLATED_NATIVE_PASS assertions=%d\n",count);return 0;
}
