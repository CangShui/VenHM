param([Parameter(Mandatory=$true)][string]$CliPath,[string]$Device='<device-id>')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'logs\transfer-device'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$script:seq=0;$trace="transfer-device-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
function InvokeCli([string[]]$Arguments){
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [CLI请求] $($Arguments-join' ')"
  $r=& node $CliPath @Arguments 2>(Join-Path $out 'stderr.log')
  if($LASTEXITCODE-ne0){throw 'CLI failed'}
  return $r
}
function Snapshot{
  $script:seq++
  $j=(InvokeCli @('ui','layout','--device',$Device,'--format','json'))-join"`n"
  $j|Set-Content -Encoding utf8 (Join-Path $out "$($script:seq).json")
  return ($j|ConvertFrom-Json)
}
function Flatten($n){$n;foreach($c in $n.children){Flatten $c}}
function Nodes($t){foreach($n in $t){Flatten $n}}
function ClickText($text){
  $t=Snapshot;$matches=@(Nodes $t|Where-Object {$_.text-eq$text-and$_.clickable})
  if($matches.Count-ne1){throw "Expected one clickable target: $text"}
  $b=$matches[0].bounds
  if($b[1]-lt0-or$b[3]-gt2832){throw 'Offscreen click refused'}
  InvokeCli @('ui','click',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device)|Out-Null
}
function Expect($pattern){
  for($i=0;$i-lt4;$i++){
    $t=Snapshot
    if(@(Nodes $t|Where-Object {$_.text-match$pattern}).Count){return $t}
    if(@(Nodes $t|Where-Object {$_.text-match'FAIL|错误|异常|失败'}).Count){throw 'Diagnostic failure shown; inspect saved layout'}
    if(@(Nodes $t|Where-Object text -eq '离线可用性验收').Count){
      InvokeCli @('ui','swipe','1200','2400','1200','900','--device',$Device)|Out-Null
    }
  }
  throw "Missing $pattern"
}
try{
  ClickText '历史'
  $t=Snapshot;$before=@(Nodes $t|Where-Object {$_.text-match'^共 \d+ 条'})[0].text
  $before|Set-Content -Encoding utf8 (Join-Path $out 'history-baseline.txt')
  ClickText '离线验收'
  ClickText '运行离线下载回归'
  Expect '^PASS · 本地2章×3页已解码下载'|Out-Null
  InvokeCli @('ui','swipe','1200','800','1200','2450','--device',$Device)|Out-Null
  ClickText '运行离线同步回归'
  Expect '^PASS · 同步白名单导出、真实RDB重复合并去重'|Out-Null
  InvokeCli @('ui','swipe','1200','800','1200','2450','--device',$Device)|Out-Null
  ClickText '‹ 返回'
  $t=Expect '^阅读历史$'
  if(-not(@(Nodes $t|Where-Object text -eq $before).Count)){throw 'History baseline changed; no attempt to alter user history'}
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [响应返回] PASS real local download/SQL sync diagnostics; baseline unchanged $before; no upload performed"
  'PASS transfer device download/sync diagnostics; no real server acceptance'
}catch{
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [异常] $($_.Exception.Message); stopped"
  throw
}
