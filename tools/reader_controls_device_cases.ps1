param([Parameter(Mandatory=$true)][string]$CliPath,[string]$Device='<device-id>',[string]$ResumeFixtureId='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'logs\reader-controls-device'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$script:seq=0;$trace="reader-device-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
function InvokeDevEco([string[]]$Arguments){
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [CLI请求] $($Arguments-join' ')"
  $r=& node $CliPath @Arguments 2>(Join-Path $out 'stderr.log')
  if($LASTEXITCODE-ne0){throw 'CLI failed; stop rather than blind click'}
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
function ContainsText($n,$text){if($n.text-eq$text){return $true};foreach($c in $n.children){if(ContainsText $c $text){return $true}};return $false}
function ClickText($text){
  $t=Snapshot;$matches=@(Nodes $t|Where-Object {$_.text-eq$text-and$_.clickable})
  if($matches.Count-eq0){$matches=@(Nodes $t|Where-Object {$_.type-eq'Button'-and$_.clickable-and(ContainsText $_ $text)})}
  if($matches.Count-ne1){throw "Expected unique clickable $text"}
  $b=$matches[0].bounds
  if($b[1]-lt0-or$b[3]-gt2832){throw "Offscreen target refused: $text"}
  InvokeDevEco @('ui','click',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device)|Out-Null
}
function ClickScrollable($text){
  for($i=0;$i-lt4;$i++){
    $t=Snapshot;$n=@(Nodes $t|Where-Object {$_.text-eq$text-and$_.clickable})
    if($n.Count-eq1-and$n[0].bounds[1]-ge0-and$n[0].bounds[3]-le2832){ClickText $text;return}
    InvokeDevEco @('ui','swipe','1200','2400','1200','1000','--device',$Device)|Out-Null
  }
  throw "Missing/offscreen target: $text"
}
function Counter{
  $t=Snapshot;$n=@(Nodes $t|Where-Object {$_.text-match'^[123] / 3$'})
  if($n.Count-ne1){throw 'Missing unique three-page fixture counter'}
  return $n[0].text
}
function ImageBounds{
  $hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
  & $hdc -t $Device shell 'uitest dumpLayout -p /data/local/tmp/venera-reader-controls.json'|Out-Null
  if($LASTEXITCODE-ne0){throw 'Raw image layout failed'}
  $temporary=Join-Path $out 'raw-image.tmp.json'
  & $hdc -t $Device file recv /data/local/tmp/venera-reader-controls.json $temporary|Out-Null
  if($LASTEXITCODE-ne0){throw 'Raw image layout transfer failed'}
  $raw=Get-Content $temporary -Raw|ConvertFrom-Json
  Remove-Item -LiteralPath $temporary
  function Attributes($n){$n.attributes;foreach($c in $n.children){Attributes $c}}
  $candidates=@()
  foreach($n in (Attributes $raw)){
    if($n.type-eq'Image'-and$n.visible-eq'true'-and$n.bounds-match'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'){
      $b=@([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],[int]$Matches[4])
      if($b[3]-$b[1]-gt500-and$b[2]-$b[0]-gt400-and$b[3]-gt450-and$b[1]-lt2400){$candidates+=,@($b)}
    }
  }
  if($candidates.Count-ne1){throw 'Expected one visible large app image in raw tree; no notification nodes kept'}
  $candidates[0]|ConvertTo-Json|Set-Content -Encoding utf8 (Join-Path $out "image-bounds-$($script:seq).json")
  return ,$candidates[0]
}
try{
  # Start from the history page, not an arbitrary app or screen.
  $t=Snapshot
  if($ResumeFixtureId.length-gt0){
    if($ResumeFixtureId-notmatch'^HM_OFFLINE_READER_[0-9]+_[0-9]+$'-or
      -not(@(Nodes $t|Where-Object text -eq $ResumeFixtureId).Count)){throw 'Resume fixture identity not observed; refused'}
    $before=Get-Content (Join-Path $out 'history-baseline.txt')
    Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [恢复自有验收] observed $ResumeFixtureId, preserving reader mode"
  }else{
    if(-not(@(Nodes $t|Where-Object text -eq '阅读历史').Count)){throw 'Start this test on 阅读历史'}
    $before=@(Nodes $t|Where-Object {$_.text-match'^共 \d+ 条'})[0].text
    $before|Set-Content -Encoding utf8 (Join-Path $out 'history-baseline.txt')
    ClickText '离线验收'
    $ready=$false
    for($i=0;$i-lt4;$i++){
      $t=Snapshot
      if(@(Nodes $t|Where-Object text -eq '尚无样本阅读进度').Count){$ready=$true;break}
      if(@(Nodes $t|Where-Object {$_.text-match'ID=.+时长'}).Count){
        throw 'Existing fixture has reading progress; refuse to alter it or remove it'
      }
    }
    if(-not$ready){throw 'Fixture state is not initialized; refuse to guess ownership'}
    ClickScrollable '继续阅读本地样本'
  }
  $original=Counter
  if($original-ne'1 / 3'){throw 'Fresh fixture did not begin at page 1'}
  # Keep the original reader mode; no preference is rewritten by this probe.
  ClickText '页›'
  if((Counter)-ne'2 / 3'){throw 'Next-page button did not advance canonical position'}
  ClickText '‹页'
  if((Counter)-ne'1 / 3'){throw 'Previous-page button did not restore first page'}
  $b=ImageBounds;$y=[int]((([Math]::Max(450,$b[1]))+([Math]::Min(2400,$b[3])))/2)
  $x=[int](($b[0]+$b[2])/2)
  InvokeDevEco @('ui','doubleclick',"$x","$y",'--device',$Device)|Out-Null
  InvokeDevEco @('ui','screenshot','--device',$Device,'--path',(Join-Path $out 'zoomed.png'))|Out-Null
  # Re-observe after zoom before selecting a target.
  $b=ImageBounds;$y=[int]((([Math]::Max(450,$b[1]))+([Math]::Min(2400,$b[3])))/2);$x=[int](($b[0]+$b[2])/2)
  InvokeDevEco @('ui','doubleclick',"$x","$y",'--device',$Device)|Out-Null
  ClickText '亮度'
  $t=Snapshot
  if(-not(@(Nodes $t|Where-Object text -eq '35%').Count)){throw 'Window brightness control did not reach 35%'}
  ClickText '自动'
  Start-Sleep -Seconds 9
  if((Counter)-eq'1 / 3'){throw 'Automatic reader did not advance'}
  ClickText '暂停'
  $paused=Counter
  Start-Sleep -Seconds 10
  if((Counter)-ne$paused){throw 'Page changed after user pause'}
  ClickText '‹ 返回'
  ClickScrollable '刷新进度'
  ClickScrollable '清理本页生成的样本'
  ClickText '清理样本'
  InvokeDevEco @('ui','swipe','1200','800','1200','2450','--device',$Device)|Out-Null
  InvokeDevEco @('ui','swipe','1200','800','1200','2450','--device',$Device)|Out-Null
  ClickText '‹ 返回'
  $t=Snapshot
  if(-not(@(Nodes $t|Where-Object text -eq $before).Count)){throw 'History baseline changed; never reset user records to compensate'}
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [响应返回] PASS page buttons/auto pause/brightness UI; doubletap images captured, native scale/restore logs still need independent verification; history unchanged $before"
  'PASS reader controls device UI; verify scale/brightness/keep-screen restore in app audit separately; no pinch claim'
}catch{
  Add-Content -Encoding utf8 (Join-Path $out 'audit.log') "TraceID=$trace [异常] $($_.Exception.Message); stop without clearing data/preferences"
  throw
}
