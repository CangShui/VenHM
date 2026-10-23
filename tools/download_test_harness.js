'use strict';
// Executes the production queue AND native coordinator against controlled SDK/filesystem fakes.
// No device, account, network, RDB or user filesystem is touched.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {stripTypeScriptTypes}=require('node:module');
const root=path.resolve(__dirname,'..');
const tick=()=>new Promise(r=>setImmediate(r));
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject};};
function downloads(audit=()=>{}) {
  const files=new Map(),dirs=new Set(['/app/files','/app/files/local_comics']),symlinks=new Set();
  const writes=[],calls=[],deleted=[],events=new Map(),service={starts:[],stops:[],agents:[],modeChecks:[],supported:true,failMode:null,failStart:null,failStop:null,startGate:null,agentGate:null,next:1,invalidId:false,liveNative:new Set()};
  const stat=p=>{if(!files.has(p)&&!dirs.has(p)&&!symlinks.has(p))throw Error('ENOENT '+p);return {size:files.get(p)?.byteLength||128,
    isFile:()=>files.has(p)&&!symlinks.has(p),isDirectory:()=>dirs.has(p)&&!symlinks.has(p),isSymbolicLink:()=>symlinks.has(p)};};
  const ctx=vm.createContext({ArrayBuffer,Uint8Array,Promise,
    AppContext:{filesDir:'/app/files',localComicDir:'/app/files/local_comics',bundleName:'fixture.bundle',context:{}},
    Log:{audit},
    fs:{OpenMode:{CREATE:1,READ_WRITE:2,TRUNC:4,READ_ONLY:8},accessSync:p=>files.has(p)||dirs.has(p)||symlinks.has(p),
      mkdirSync:p=>dirs.add(p),openSync:(p,mode)=>{if(mode&4)files.set(p,'');return {fd:p}},
      writeSync:(p,b)=>{files.set(p,b);writes.push(p);return typeof b==='string'?Buffer.byteLength(b):b.byteLength},closeSync:()=>{},
      renameSync:(a,b)=>{files.set(b,files.get(a));files.delete(a)},readTextSync:p=>{if(!files.has(p))throw Error('ENOENT '+p);return files.get(p)},
      unlinkSync:p=>{deleted.push(p);files.delete(p)},
      listFileSync:p=>[...new Set([...files.keys(),...dirs,...symlinks].filter(k=>k.startsWith(p+'/')&&!k.slice(p.length+1).includes('/')).map(k=>k.slice(p.length+1)))],
      rmdirSync:p=>{deleted.push(p);for(const k of files.keys())if(k.startsWith(p+'/'))files.delete(k);for(const k of dirs)if(k===p||k.startsWith(p+'/'))dirs.delete(k)},
      statSync:stat,lstatSync:stat,readSync:(p,b)=>{new Uint8Array(b).set(new Uint8Array(files.get(p)));return b.byteLength}},
    SourceManager:{find:k=>k==='fixture'?{loadComicInfo:async()=>({error:false,dataOrNull:{title:'Fixture',chapters:{length:2,ids:['a','b'],titles:['A','B']}}}),
      loadComicPages:async(id,ep)=>({error:false,dataOrNull:[`${ep}-1`,`${ep}-2`]})}:undefined},
    ImageRequests:{resolve:async(s,u)=>({url:u,headers:new Map(),unsupported:[],modifyImage:''})},
    ImagePipeline:{fetch:async(config,trace,shouldContinue)=>{const response=await ctx.HttpClient.getBytes(config.url);
      if(!shouldContinue())throw Error('IMAGE_REQUEST_CANCELLED');
      if(!response.ok)throw Error('image HTTP failed');return response.bytes}},
    ImageTransforms:{cancel:()=>{}},
    HttpClient:{getBytes:async u=>{calls.push(u);return {ok:true,status:200,bytes:new ArrayBuffer(128)}}},
    image:{createImageSource:()=>({getImageInfo:async()=>({size:{width:10,height:20},mimeType:'image/png'}),
      createPixelMap:async()=>({getImageInfo:async()=>({size:{width:10,height:20}}),release:async()=>{}}),release:async()=>{}})},
    wantAgent:{OperationType:{START_ABILITY:1},WantAgentFlags:{UPDATE_PRESENT_FLAG:1},getWantAgent:async info=>{service.agents.push(info);if(service.agentGate)await service.agentGate.promise;return {id:1}}},
    backgroundTaskManager:{BackgroundTaskMode:{MODE_DATA_TRANSFER:1},
      BackgroundTaskSubmode:{SUBMODE_NORMAL_NOTIFICATION:2,SUBMODE_LIVE_VIEW_NOTIFICATION:3},
      ContinuousTaskRequest:class{isModeSupported(){service.modeChecks.push(this);if(service.failMode)throw service.failMode;return service.supported}},
      on:(name,cb)=>events.set(name,cb),off:(name,cb)=>{if(events.get(name)===cb)events.delete(name)},
      startBackgroundRunning:async(context,request)=>{
        service.starts.push(request);
        // Published API21 mapping/implementation rejects empty or mismatched submodes.
        if(request.backgroundTaskModes.length!==1||request.backgroundTaskModes[0]!==1||
          request.backgroundTaskSubmodes.length!==1||request.backgroundTaskSubmodes[0]!==3)
          throw Object.assign(Error('Continuous task verification failed'),{code:9800005});
        if(service.startGate)await service.startGate.promise;if(service.failStart)throw service.failStart;
        const id=service.next++;if(service.invalidId)return {notificationId:8041};
        service.liveNative.add(id);return {continuousTaskId:id,notificationId:8041}},
      stopBackgroundRunning:async(context,id)=>{service.stops.push(id);if(service.failStop)throw service.failStop;
        if(id===undefined)service.liveNative.clear();else service.liveNative.delete(id)}}
  });
  const load=(p,name)=>{const text=fs.readFileSync(path.join(root,p),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
    vm.runInContext(stripTypeScriptTypes(text,{mode:'transform'})+`\nglobalThis.${name}=${name};`,ctx);};
  load('entry/src/main/ets/features/BackgroundDownloadCoordinator.ets','BackgroundDownloadCoordinator');
  load('entry/src/main/ets/features/DownloadQueue.ets','DownloadQueue');
  return {ctx,Queue:ctx.DownloadQueue,Coordinator:ctx.BackgroundDownloadCoordinator,files,dirs,symlinks,writes,calls,deleted,service,events};
}
module.exports={downloads,tick,deferred};
