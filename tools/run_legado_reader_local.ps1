# Reference-based reader interaction: local tests only; no device or installation.
$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'legado_reader_scope_cases.js')
if($LASTEXITCODE -ne 0){throw 'Reader data/source scope guard failed'}
& (Join-Path $PSScriptRoot 'run_local_search_download_regression.ps1') -EvidenceName 'legado-reader-regression-20261023'
if($LASTEXITCODE -ne 0){throw 'Nine-zone reader/legacy regression failed'}
Write-Output 'LEGADO_READER_LOCAL_PASS: 54 complete suites plus negative controls; original style/data pipelines retained; no device action'
exit 0
