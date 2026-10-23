param([string]$Device='<device-id>')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cli=Join-Path $env:TEMP 'venera-devecocli-1.3.5\node_modules\@deveco\deveco-cli\cli.js'
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$out=Join-Path $root 'logs\user8-device-matrix'
New-Item -ItemType Directory -Force $out|Out-Null
$script:step=0
# The device may have drifted to another app; re-foreground only Venera HM.
& $hdc -t $Device shell aa start -b com.venerahm.reader -a EntryAbility 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'foreground.log')
if($LASTEXITCODE-ne0){throw 'cannot foreground Venera HM'}
Start-Sleep -Seconds 6
function Snapshot([string]$tag){
  $script:step++
  $file=Join-Path $out "$($script:step)-$tag.json"
  $p=Start-Process -FilePath 'C:\Program Files\nodejs\node.exe' -ArgumentList @(('"'+$cli+'"'),'ui','layout','--device',$Device,'--format','json') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $file -RedirectStandardError (Join-Path $out "$($script:step)-$tag.err")
  if($p.ExitCode-ne0){throw "layout failed: $tag"}
  return [IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
}
function FindNode([string]$json,[string]$text){
  $pattern='"text"\s*:\s*"'+[regex]::Escape($text)+'"'
  $m=[regex]::Match($json,$pattern)
  if(!$m.Success){return $null}
  # Layout order is type, text, bounds: the target's own bounds FOLLOW its text,
  # so search forward; searching backward returns the parent container instead.
  $tail=$json.Substring($m.Index+$m.Length)
  $bounds=[regex]::Match($tail,'"bounds"\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\]')
  if(!$bounds.Success){return $null}
  $b=$bounds.Groups
  return @{x=[int](([int]$b[1].Value+[int]$b[3].Value)/2);y=[int](([int]$b[2].Value+[int]$b[4].Value)/2)}
}
function ClickText([string]$text){
  $json=Snapshot "find-$text"
  $node=FindNode $json $text
  if($node-eq$null){throw "target not found: $text"}
  $p=Start-Process -FilePath 'C:\Program Files\nodejs\node.exe' -ArgumentList @(('"'+$cli+'"'),'ui','click',"$($node.x)","$($node.y)",'--device',$Device) -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $out "click-$text.log") -RedirectStandardError (Join-Path $out "click-$text.err")
  if($p.ExitCode-ne0){throw "click failed: $text"}
  Start-Sleep -Milliseconds 900
}
ClickText '历史'
ClickText '离线验收'
ClickText '运行深度源矩阵（联网，只读）'
Start-Sleep -Seconds 3
$json=Snapshot 'matrix-start'
if($json-notmatch '停止深度矩阵'){throw 'matrix did not start (no stop button)'}
Write-Output 'MATRIX_STARTED'
# The matrix runs one source at a time with real network; wait for the END marker.
for($i=0;$i-lt80;$i++){
  Start-Sleep -Seconds 15
  & $hdc -t $Device file recv /data/app/el2/100/base/com.venerahm.reader/haps/entry/files/logs/app-dev-2026-10-14.log (Join-Path $out 'app-dev.log') 2>$null | Out-Null
  $log=[IO.File]::ReadAllText((Join-Path $out 'app-dev.log'),[Text.Encoding]::UTF8)
  if($log-match 'matrix \| END'){Write-Output "MATRIX_FINISHED after $($i+1) polls";break}
  $status=Snapshot "poll-$i"
  if($status-match '矩阵执行完成'){Write-Output "MATRIX_FINISHED ui after $($i+1) polls";break}
}
$json=Snapshot 'matrix-end'
$rows=@([regex]::Matches($json,'"text"\s*:\s*"([^"]*L0=[^"]*)"')|ForEach-Object{$_.Groups[1].Value})
$rows|Set-Content -Encoding UTF8 (Join-Path $out 'ui-rows.txt')
Write-Output "UI_ROWS=$($rows.Count)"
