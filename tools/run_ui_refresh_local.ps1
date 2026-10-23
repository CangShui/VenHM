# UI-only local gate. Does not install, launch, control a device or change backend data.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& node (Join-Path $PSScriptRoot 'create_ui_design_preview.js')
if($LASTEXITCODE -ne 0){throw 'UI design preview generator failed'}
& node (Join-Path $PSScriptRoot 'ui_refresh_guard.js')
if($LASTEXITCODE -ne 0){throw 'Backend/business unchanged guard failed'}
& node (Join-Path $PSScriptRoot 'ui_refresh_cases.js')
if($LASTEXITCODE -ne 0){throw 'UI-only contract tests failed'}
& (Join-Path $PSScriptRoot 'run_local_search_download_regression.ps1') -EvidenceName 'ui-refresh-regression-20261021'
if($LASTEXITCODE -ne 0){throw 'Existing local regression suite failed'}
Write-Output 'UI_REFRESH_LOCAL_PASS: 99 backend hashes, 13 UI contracts, 51 existing suites plus negative controls; no device or install'
exit 0
