'use strict';
// Controlled loopback server: synthetic PNG only, no accounts or user files.
const http=require('node:http'),zlib=require('node:zlib'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),log=path.join(root,'logs/image-http-fixture-server.log');
fs.mkdirSync(path.dirname(log),{recursive:true});
const trace='image-http-fixture';
const audit=(stage,message)=>fs.appendFileSync(log,`TraceID=${trace} [${stage}] ${message}\n`);
function crc32(data){let n=0xffffffff;for(const b of data){n^=b;for(let i=0;i<8;i++)n=(n>>>1)^((n&1)?0xedb88320:0)}return (n^0xffffffff)>>>0}
function chunk(type,data){const t=Buffer.from(type),body=Buffer.concat([t,data]),result=Buffer.alloc(data.length+12);
  result.writeUInt32BE(data.length);body.copy(result,4);result.writeUInt32BE(crc32(body),result.length-4);return result}
const header=Buffer.alloc(13);header.writeUInt32BE(2,0);header.writeUInt32BE(3,4);header[8]=8;header[9]=6;
const rows=[];for(let y=0;y<3;y++){rows.push(Buffer.from([0,10+y*10,30,99,255,11+y*10,40,99,255]))}
const png=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(Buffer.concat(rows))),chunk('IEND',Buffer.alloc(0))]);
const counts={};
const server=http.createServer(async(req,res)=>{
  const data=[];for await(const b of req)data.push(b);const body=Buffer.concat(data),route=new URL(req.url,'http://fixture.invalid').pathname;
  counts[route]=(counts[route]||0)+1;
  audit('请求到达',`方法=${req.method}；路由=${route}；正文长度=${body.length}；不记录原文/请求头`);
  if(route==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end('{"fixture":"venera-hm-image-v1"}');return}
  if(route==='/summary'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(counts));return}
  if(route.startsWith('/encoding/')){
    const codec=route.split('/')[2],plain=Buffer.from('{"message":"synthetic compressed response","ok":true}');
    const input=codec==='gzip'?zlib.gzipSync(plain):codec==='deflate'?zlib.deflateSync(plain):
      codec==='br'?zlib.brotliCompressSync(plain):null;
    if(!input){res.writeHead(400);res.end('unsupported fixture encoding');return}
    res.writeHead(200,{'Content-Type':'application/json;charset=utf-8','Content-Encoding':codec});
    res.end(input);audit('压缩响应返回',`编码=${codec}；原字节=${plain.length}；传输字节=${input.length}`);return
  }
  if(route.startsWith('/auth/')){
    const name=new URL(req.url,'http://fixture.invalid').searchParams.get('name')||'';
    if(!/^hm_auth_[0-9]+_[0-9]+$/.test(name)){res.writeHead(400);res.end('invalid synthetic fixture identity');return}
    if(route==='/auth/login'){
      const done='/auth/done?name='+name,endpoint='/auth/session?name='+name;
      const html='<!doctype html><meta charset="utf-8"><title>Synthetic auth login</title>'+
        '<h1>本机合成账号验收（不是实际网站登录）</h1><button id="continue">确认合成账号</button>'+
        '<script>document.getElementById("continue").onclick=async()=>{'+
        'const r=await fetch('+JSON.stringify(endpoint)+',{method:"POST",body:"synthetic"});'+
        'if(r.ok){localStorage.setItem("probeToken","synthetic-token");location.href='+JSON.stringify(done)+';}};</script>';
      res.writeHead(200,{'Content-Type':'text/html;charset=utf-8'});res.end(html);audit('合成网页返回','显示手动确认按钮，无真实账号字段');return
    }
    if(route==='/auth/session'&&req.method==='POST'&&body.toString()==='synthetic'){
      res.writeHead(200,{'Content-Type':'text/plain','Set-Cookie':name+'=synthetic; Path=/; HttpOnly; SameSite=Lax; Expires=Wed, 21 Oct 2035 07:28:00 GMT'});
      res.end('ok');audit('合成会话返回','仅随机fixture Cookie，含HttpOnly/SameSite/Expires');return
    }
    if(route==='/auth/done'){
      res.writeHead(200,{'Content-Type':'text/html;charset=utf-8'});res.end('<!doctype html><title>Synthetic auth done</title><h1>合成会话就绪</h1>');return
    }
    if(route==='/auth/verify'){
      const valid=(req.headers.cookie||'').split(/;\s*/).includes(name+'=synthetic');
      res.writeHead(valid?200:401,{'Content-Type':'text/plain'});res.end(valid?'verified':'not verified');
      audit('合成会话复核',`Cookie名字/值不落盘；已验证=${valid}`);return
    }
    res.writeHead(404);res.end('unknown synthetic auth endpoint');return
  }
  let valid=true,status=200,result=png;
  if(route==='/post')valid=req.method==='POST'&&body.toString()==='a=1'&&req.headers['content-type']==='application/x-www-form-urlencoded';
  else if(route==='/empty')valid=req.method==='POST'&&body.length===0;
  else if(route==='/binary')valid=req.method==='POST'&&body.equals(Buffer.from([1,2]));
  else if(route==='/encrypted')result=Buffer.concat([Buffer.from([99]),png]);
  else if(route==='/slow'){await new Promise(r=>setTimeout(r,20000))}
  else if(route==='/failure'||route==='/always-fail'){status=403;result=Buffer.from('synthetic denied')}
  else if(route!=='/image'){status=404;result=Buffer.from('fixture endpoint not found')}
  if(!valid){status=422;result=Buffer.from('fixture request mismatch')}
  res.writeHead(status,{'Content-Type':status===200?'image/png':'text/plain'});res.end(result);
  audit('响应返回',`路由=${route}；状态=${status}；合成字节=${result.length}；契约符合=${valid}`);
});
server.listen(29091,'127.0.0.1',()=>{audit('服务启动','仅监听127.0.0.1:29091；需设备HDC rport；不访问外网');console.log('Fixture listening on 127.0.0.1:29091')});
server.on('error',e=>{audit('异常',e.code||'server error');console.error(e.code);process.exitCode=1});
function stop(){audit('服务停止','结束本次隔离测试');server.close(()=>process.exit(0))}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
