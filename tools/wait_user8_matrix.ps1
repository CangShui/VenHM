param([string]$Device='<device-id>',[int]$Minutes=15)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$out=Join-Path $root 'logs\user8-device-matrix'
New-Item -ItemType Directory -Force $out|Out-Null
$dir='/data/app/el2/100/base/com.venerahm.reader/haps/entry/files/logs'
function RemoteList(){ (& $hdc -t $Device shell ls $dir 2>&1) -join "`n" }
function DeepMax([string]$text){
  $nums=@([regex]::Matches($text,'deep-(\d+)\.jsonl')|ForEach-Object{[int64]$_.Groups[1].Value})
  if($nums.Count-eq0){return [int64]0}
  return ($nums|Measure-Object -Maximum).Maximum
}
$before=DeepMax (RemoteList)
Write-Output "BEFORE_MAX=$before"
$deadline=(Get-Date).AddMinutes($Minutes)
$target=$null
while((Get-Date)-lt$deadline){
  Start-Sleep -Seconds 20
  $now=RemoteList
  $nowMax=DeepMax $now
  if($nowMax -gt $before){
    $target="deep-$nowMax.jsonl"
    $local=Join-Path $out $target
    & $hdc -t $Device file recv "$dir/$target" $local 2>$null | Out-Null
    if(Test-Path $local){
      $text=[IO.File]::ReadAllText($local,[Text.Encoding]::UTF8)
      if($text-match '"stage":"END"'){Write-Output "MATRIX_END file=$target";break}
      Write-Output "RUNNING $target"
    }
  } else { Write-Output 'WAITING_FOR_NEW_RUN' }
}
if($target-eq$null){throw 'no new matrix file appeared within the deadline'}
Write-Output "MATRIX_FILE=$target"
