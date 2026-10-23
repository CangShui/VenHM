# Actual production Node NAPI addon, independent of ArkTS mocks. Host evidence
# ONLY: not phone NAPI, ArkTS finalizer timing, ImageKit or SDK transport proof.
param([int]$TimeoutSeconds=40)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'logs\napi-host'
$node=(Get-Command node -ErrorAction Stop).Source
if(!(Test-Path (Join-Path $out 'venerajs.node'))){throw 'Production host addon not built'}
$script=Join-Path $PSScriptRoot 'napi_host_cases.js'
$p=Start-Process -FilePath $node -ArgumentList @('--expose-gc',('"'+$script+'"')) -WorkingDirectory $root -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $out 'integration.log') -RedirectStandardError (Join-Path $out 'integration-stderr.log')
# Materialize the handle before exit; Windows PowerShell can otherwise lose
# ExitCode on a Start-Process object after a fast asynchronous child finishes.
$processHandle=$p.Handle
if(!$p.WaitForExit($TimeoutSeconds*1000)){
  # Kill only the test process launched above, never any SDK/HDC/app process.
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  throw 'Actual host NAPI test timed out; inspect logs, not a passing teardown'
}
$p.Refresh()
if($p.ExitCode-ne0){throw "Actual host NAPI integration exit=$($p.ExitCode); inspect integration logs"}
if(!(Select-String -LiteralPath (Join-Path $out 'integration.log') -SimpleMatch 'NAPI_HOST_PASS cases=' -Quiet)){throw 'Host test exit0 without completed PASS marker'}
Get-Content (Join-Path $out 'integration.log')
# Native synchronous loops require an EXTERNAL watchdog; Node timers cannot stop
# QuickJS while NAPI has not returned. Each deadline case also has its own 15s
# child-process watchdog, and this outer process has a separate absolute bound.
$deadlineScript=Join-Path $PSScriptRoot 'main_runtime_deadline_cases.js'
$d=Start-Process -FilePath $node -ArgumentList @('--expose-gc',('"'+$deadlineScript+'"')) -WorkingDirectory $root -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $out 'main-deadline.log') -RedirectStandardError (Join-Path $out 'main-deadline-stderr.log')
$deadlineHandle=$d.Handle
if(!$d.WaitForExit(180000)){
  Stop-Process -Id $d.Id -Force -ErrorAction SilentlyContinue
  throw 'Main-runtime deadline suite exceeded its external watchdog'
}
$d.Refresh()
if($d.ExitCode-ne0){throw "Main-runtime deadline suite exit=$($d.ExitCode); inspect main-deadline logs"}
if(!(Select-String -LiteralPath (Join-Path $out 'main-deadline.log') -SimpleMatch 'MAIN_RUNTIME_DEADLINE_PASS cases=' -Quiet)){throw 'Main-runtime suite exit0 without PASS marker'}
Get-Content (Join-Path $out 'main-deadline.log')
