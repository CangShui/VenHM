'use strict';
// Offline design-review documents only. Binds loopback, has no app APIs,
// no proxy/network access, and cannot serve repository files outside the folder.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const folder=path.resolve(__dirname,'../logs/ui-refresh-20261021');
const port=58371;
http.createServer((req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1:'+port);
 if(url.pathname==='/health'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({kind:'VENERA_DESIGN_PREVIEW_ONLY',notArkUI:true}));return}
 const file=url.pathname==='/'?'design-preview.html':url.pathname.slice(1);
 if(!/^(?:design-preview\.html|design-inputs\.json)$/.test(file)){res.writeHead(404);res.end();return}
 const target=path.join(folder,file);
 if(!fs.existsSync(target)){res.writeHead(404);res.end('Preview not generated');return}
 res.writeHead(200,{'Content-Type':file.endsWith('.html')?'text/html; charset=utf-8':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});fs.createReadStream(target).pipe(res);
}).listen(port,'127.0.0.1',()=>console.log('UI_DESIGN_PREVIEW_ONLY http://127.0.0.1:'+port+' (not ArkUI runtime; no phone/network/backends)'));
