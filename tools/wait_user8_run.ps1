param([string]$RunId='1792033074497',[string]$Device='<device-id>',[int]$Minutes=15)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$out=Join-Path $root 'logs\user8-device-matrix'
$dir='/data/app/el2/100/base/com.venerahm.reader/haps/entry/files/logs'
$file="deep-$RunId.jsonl";$local=Join-Path $out $file
$deadline=(Get-Date).AddMinutes($Minutes)
while((Get-Date)-lt$deadline){
  & $hdc -t $Device file recv "$dir/$file" $local 2>$null | Out-Null
  if(Test-Path $local){
    $text=[IO.File]::ReadAllText($local,[Text.Encoding]::UTF8)
    if($text-match '"stage":"END"'){Write-Output "MATRIX_END $file";break}
    $n=([regex]::Matches($text,'"stage"')).Count
    Write-Output "RUNNING $file stages=$n"
  } else { Write-Output 'WAITING_FOR_FILE' }
  Start-Sleep -Seconds 20
}
$text=[IO.File]::ReadAllText($local,[Text.Encoding]::UTF8)
if($text-notmatch '"stage":"END"'){throw "matrix did not reach END within $Minutes minutes"}
Write-Output 'MATRIX_COMPLETE'
