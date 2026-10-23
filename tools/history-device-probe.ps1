param([ValidateSet('snapshot','click','swipe','shot')][string]$Action='snapshot', [string]$Text='', [int]$X1=0,[int]$Y1=0,[int]$X2=0,[int]$Y2=0,[string]$Name='current')
$ErrorActionPreference='Stop'
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$out=Join-Path $PSScriptRoot '..\dist\history-usability'
New-Item -ItemType Directory -Path $out -Force | Out-Null
function InvokeHdc([string[]]$Arguments) {
  $output = & $hdc @Arguments
  if ($LASTEXITCODE -ne 0 -or ($output -match '\[Fail\]|error:|Error Code:')) {
    throw "hdc failed: $Arguments; $output"
  }
  $output
}
function ReadLayout {
  InvokeHdc @('shell','uitest dumpLayout -p /data/local/tmp/venera_history_probe.json') | Out-Null
  $local=Join-Path $out "$Name.json"
  InvokeHdc @('file','recv','/data/local/tmp/venera_history_probe.json',$local) | Out-Null
  $tree=Get-Content $local -Raw -Encoding UTF8 | ConvertFrom-Json
  $nodes=[System.Collections.Generic.List[object]]::new()
  function Visit($node) {
    if($node.attributes) { $nodes.Add($node.attributes) }
    foreach($child in $node.children) { Visit $child }
  }
  Visit $tree
  return $nodes
}
if($Action -eq 'shot') {
  InvokeHdc @('shell','snapshot_display -f /data/local/tmp/venera_history_probe.jpeg') | Out-Null
  InvokeHdc @('file','recv','/data/local/tmp/venera_history_probe.jpeg',(Join-Path $out "$Name.jpeg"))
  exit 0
}
if($Action -eq 'swipe') {
  InvokeHdc @('shell',"uitest uiInput swipe $X1 $Y1 $X2 $Y2 500") | Out-Null
}
if($Action -eq 'click') {
  $nodes=ReadLayout
  $matches=@($nodes | Where-Object { $_.text -eq $Text })
  if($matches.Count -eq 0) { throw "No current node with exact text '$Text'; refusing blind click" }
  $node=$matches[0]
  if($node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid bounds' }
  $x=[int](([int]$Matches[1]+[int]$Matches[3])/2)
  $y=[int](([int]$Matches[2]+[int]$Matches[4])/2)
  InvokeHdc @('shell',"uitest uiInput click $x $y") | Out-Null
}
$nodes=ReadLayout
$nodes | Where-Object { $_.text -or $_.type -eq 'Toggle' } | ForEach-Object {
  '{0} | {1} | checked={2}' -f $_.text,$_.bounds,$_.checked
}
