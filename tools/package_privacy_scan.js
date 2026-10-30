'use strict';
// Binary-safe privacy scan for a built package or any directory tree.
// Reads every file as raw bytes (Latin-1 view) so native libraries and archives
// are checked too, not just text files. Exit code 1 on any finding.
const fs=require('node:fs'),path=require('node:path');

const PATTERNS=[
  {name:'local user name',re:/Administrator|C:[\\/]Users[\\/]/i},
  {name:'absolute windows path in source strings',re:/[A-Za-z]:\\Users\\[^\0]{0,40}/},
  {name:'github token',re:/github_pat_[A-Za-z0-9_]{20,}/},
  {name:'generic api token',re:/(ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}/},
  {name:'signing material path',re:/\.ohos[\\/]config/},
  {name:'private key block',re:/-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----/},
  {name:'basic-auth url',re:/[a-z][a-z0-9+.-]*:\/\/[^\/\s:@]+:[^\/\s@]+@/i},
  {name:'private network address',re:/\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b/},
  {name:'device serial',re:/\b4ZB0[0-9A-Z]{10,}\b/},
  {name:'git remote with credentials',re:/https:\/\/[^\/\s]+@github\.com/}
];
const ALLOW=[/fixture\.invalid/,/127\.0\.0\.1/,/example\.com/i];

function scanFile(file,findings){
  const bytes=fs.readFileSync(file);
  const text=bytes.toString('latin1');
  const lines=text.split('\n');
  for(const p of PATTERNS){
    if(!p.re.test(text))continue;
    for(let i=0;i<lines.length;i++){
      const line=lines[i];
      if(!p.re.test(line))continue;
      if(ALLOW.some(a=>a.test(line)))continue;
      const trimmed=line.replace(/[\x00-\x1f]/g,' ').trim().slice(0,160);
      findings.push({file,line:i+1,rule:p.name,text:trimmed});
      break; // one finding per rule per file is enough to fail
    }
  }
}

function walk(target,findings){
  const st=fs.statSync(target);
  if(st.isDirectory()){
    for(const name of fs.readdirSync(target))walk(path.join(target,name),findings);
  }else if(st.isFile()){
    scanFile(target,findings);
  }
}

const target=process.argv[2];
if(!target||!fs.existsSync(target)){
  console.error('usage: node tools/package_privacy_scan.js <file-or-directory>');
  process.exit(2);
}
const findings=[];
walk(target,findings);
if(findings.length===0){
  console.log('PACKAGE_PRIVACY_SCAN_PASS: no user paths, credentials, signing material, tokens or device ids');
  process.exit(0);
}
console.log(`PACKAGE_PRIVACY_SCAN_FAIL findings=${findings.length}`);
for(const f of findings){
  console.log(`  ${path.basename(f.file)}:${f.line} [${f.rule}] ${f.text}`);
}
process.exit(1);
