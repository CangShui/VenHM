# Local-only gate for icon geometry and classic reader chrome. No device commands.
$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'reader_immersive_scope.js')
if($LASTEXITCODE -ne 0){throw 'Protected reader/backend scope changed'}
& (Join-Path $PSScriptRoot 'run_local_search_download_regression.ps1') -EvidenceName 'reader-immersive-regression-20261021'
if($LASTEXITCODE -ne 0){throw 'Local icon/reader/window or existing regression failed'}
Write-Output 'READER_IMMERSIVE_LOCAL_PASS: 54 suites including icon16/reader25/window18 and existing business regressions; no device/install'
exit 0
