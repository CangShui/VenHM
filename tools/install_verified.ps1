# Non-destructive HDC overwrite only. HDC can report exit0 for a disconnected
# device: require its explicit success text as well as process status.
param(
  [string]$HapPath='entry/build/default/outputs/default/entry-default-signed.hap',
  [string]$Device='<device-id>',
  [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$EvidenceName='verified-overwrite',
  [switch]$CheckEvidenceOnly
)
$ErrorActionPreference='Stop'
function Test-OverwriteEvidence([int]$ExitCode,[string]$Stdout,[string]$Stderr) {
  $text=$Stdout+"`n"+$Stderr
  return ($ExitCode-eq0 -and $text-match'(?i)install bundle successfully' -and
    $text-notmatch'(?i)\[Fail\]|Device not found|not connected|connect-key|install failed|error:')
}
if($CheckEvidenceOnly){
  $cases=@(
    @{Exit=0;Out='[Info] install bundle successfully.';Err='';Want=$true},
    @{Exit=0;Out='[Fail][E001005] Device not found or connected';Err='';Want=$false},
    @{Exit=0;Out='';Err='';Want=$false},
    @{Exit=1;Out='install bundle successfully';Err='';Want=$false},
    @{Exit=0;Out='install bundle successfully';Err='[Fail] install failed';Want=$false}
  )
  foreach($case in $cases){if((Test-OverwriteEvidence $case.Exit $case.Out $case.Err)-ne$case.Want){throw 'HDC evidence contract failed'}}
  Write-Output 'PASS5 HDC overwrite evidence contracts; no device action performed';exit 0
}
$root=Split-Path -Parent $PSScriptRoot
$hap=(Resolve-Path -LiteralPath (Join-Path $root $HapPath)).Path
if([IO.Path]::GetExtension($hap)-ne'.hap'){throw 'Only an existing HAP can be installed'}
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$out=Join-Path $root "logs\$EvidenceName.log";$err=Join-Path $root "logs\$EvidenceName-stderr.log"
$process=Start-Process -FilePath $hdc -ArgumentList @('-t',$Device,'install','-r',('"'+$hap+'"')) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
$stdout=Get-Content -LiteralPath $out -Raw -ErrorAction Stop
$stderr=Get-Content -LiteralPath $err -Raw -ErrorAction Stop
if(!(Test-OverwriteEvidence $process.ExitCode $stdout $stderr)){throw "Overwrite not verified (exit=$($process.ExitCode)); inspect $out. No uninstall/data clear/launch fallback."}
Write-Output 'VERIFIED_OVERWRITE_PASS; no application launch, uninstall or data clear'
# Unset $LASTEXITCODE is $null, and `$null -ne 0` is true in PowerShell; set an
# explicit success code so callers cannot misread a verified install as failure.
exit 0
