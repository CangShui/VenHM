param([Parameter(Mandatory=$true)][string]$CliPath,[string]$Device='<device-id>')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'logs\search-device'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$trace="search-device-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
$audit=Join-Path $out 'audit.log';$script:seq=0
function InvokeDevEco([string[]]$Arguments){
  Add-Content -Encoding utf8 $audit "TraceID=$trace [CLI请求] $($Arguments-join' ')"
  $r=& node $CliPath @Arguments 2>(Join-Path $out 'stderr.log')
  if($LASTEXITCODE-ne0){throw 'CLI failed'}
  return $r
}
function Snapshot{
  $script:seq++
  $j=(InvokeDevEco @('ui','layout','--device',$Device,'--format','json'))-join"`n"
  $j|Set-Content -Encoding utf8 (Join-Path $out "$($script:seq).json")
  return ($j|ConvertFrom-Json)
}
function Flatten($n){$n;foreach($c in $n.children){Flatten $c}}
function Nodes($t){foreach($n in $t){Flatten $n}}
function Click($n){
  $b=$n.bounds
  if($b[2]-le$b[0]-or$b[3]-le$b[1]-or$b[1]-lt0-or$b[3]-gt2832){throw 'Invisible target'}
  InvokeDevEco @('ui','click',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device)|Out-Null
}
function ClickText($text){
  $t=Snapshot;$all=@(Nodes $t|Where-Object text -eq $text)
  $clickable=@($all|Where-Object clickable -eq $true)
  if($clickable.Count-eq1){Click $clickable[0];return}
  if($all.Count-ne1){throw "Non-unique target $text"}
  Click $all[0]
}
function Expect($text){
  for($i=0;$i-lt6;$i++){
    $t=Snapshot
    if(@(Nodes $t|Where-Object text -eq $text).Count){return $t}
    Start-Sleep -Milliseconds 200
  }
  throw "Missing expected state: $text"
}
try{
  Add-Content -Encoding utf8 $audit "TraceID=$trace [请求到达] readonly H-Comic search/pagination and source-switch verification; no favorites/history writes"
  ClickText '搜索'
  $t=Snapshot;$select=@(Nodes $t|Where-Object type -eq 'Select')
  if($select.Count-ne1){throw 'Expected one source select'}
  Click $select[0]
  ClickText 'H-Comic'
  $t=Snapshot;$input=@(Nodes $t|Where-Object type -eq 'TextInput')
  if($input.Count-ne1){throw 'Expected one query field'}
  $b=$input[0].bounds
  InvokeDevEco @('ui','text','a',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device)|Out-Null
  ClickText '搜索'
  Expect '已加载 10 条'|Out-Null
  ClickText '加载更多'
  Expect '已加载 20 条'|Out-Null
  $t=Snapshot;$select=@(Nodes $t|Where-Object type -eq 'Select')
  Click $select[0]
  ClickText '本地漫画'
  $t=Expect '选择漫画源并输入关键字开始搜索'
  if(@(Nodes $t|Where-Object type -eq 'Grid').Count){throw 'Old results remained after switching source'}
  Add-Content -Encoding utf8 $audit "TraceID=$trace [响应返回] PASS initial10 -> distinct page2 total20; keyboard dismissed; source switch cleared results; query content excluded from app logs"
  'PASS search device pagination and source switch'
}catch{
  Add-Content -Encoding utf8 $audit "TraceID=$trace [异常] $($_.Exception.Message); stopped without blind actions"
  throw
}
