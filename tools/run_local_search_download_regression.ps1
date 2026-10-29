param([int]$CaseTimeoutSeconds=30,[string]$EvidenceName='local-search-download-20261017')
# Local-only: this script has NO hdc/aa/install/UI automation or real-site steps.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($EvidenceName -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Invalid evidence name'}
$out=Join-Path (Join-Path $root 'logs') $EvidenceName
New-Item -ItemType Directory -Force $out | Out-Null
$node=(Get-Command node -ErrorAction Stop).Source
$python=(Get-Command python -ErrorAction Stop).Source
$cases=@('rpc_trace_cases.js','content_decoding_cases.js','auth_log_cases.js','account_page_cases.js','browser_cookie_cases.js','cookie_schema_cases.js','image_component_lifecycle_cases.js','page_lifecycle_cases.js','http_adapter_cases.js','chapter_navigation_cases.js','image_pipeline_cases.js','image_transform_cases.js','image_cache_cases.js','download_sync_cases.js','background_download_cases.js','deep_matrix_cases.js','source_account_cases.js','reader_controls_cases.js','source_settings_cases.js','history_reader_cases.js','search_session_cases.js','html_lifecycle_cases.js','ui_bridge_cases.js','html_engine_cases.js','isolated_arkts_cases.js','worker_napi_contract_cases.js','reader_settings_cases.js','reader_image_layout_cases.js','reader_spread_cases.js','reader_performance_cases.js','category_tag_cases.js','source_contract_ui_cases.js','reader_tap_policy_cases.js','public_template_probe_cases.js','startup_source_optin_cases.js','source_acceptance_category_napi_cases.js','ykmh_category_attribution_cases.js','ranking_cases.js','ranking_napi_cases.js','search_filters_cases.js','search_filters_napi_cases.js','details_cases.js','details_napi_cases.js','collections_cases.js','collections_napi_cases.js','ui_contract_cases.js','download_progress_cases.js','cache_store_cases.js','cache_settings_cases.js','details_cache_cases.js','ui_icon_size_cases.js','reader_window_chrome_cases.js','reader_immersive_cases.js','fix4_cases.js','device_layout_cases.js','source_report_cases.py')
$results=@()
foreach($case in $cases){
  $file=Join-Path $PSScriptRoot $case
  if(!(Test-Path -LiteralPath $file)){throw "Required local suite missing: $case"}
  $exe=if($case.EndsWith('.py')){$python}else{$node}
  $stdout=Join-Path $out "$case.stdout.log";$stderr=Join-Path $out "$case.stderr.log"
  $p=Start-Process -FilePath $exe -ArgumentList @(('"'+$file+'"')) -WorkingDirectory $root -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $handle=$p.Handle
  $timedout=!$p.WaitForExit($CaseTimeoutSeconds*1000)
  if($timedout){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
  $p.Refresh()
  $text=Get-Content -LiteralPath $stdout -Raw -Encoding UTF8
  $marker=$text-match'(?im)^(?:PASS\s+\d+\b|ALL PASS\s*$|\d+ passed, 0 failed\b)'
  if($case-eq'background_download_cases.js'){$marker=$text-match'PASS 27 production background/queue race safety cases'}
  if($case-eq'search_filters_cases.js'){$marker=$text-match'PASS 25 production search filters/defaults/shared-source/inline-aggregate contracts'}
  # Match only failure records, not passing case names such as "... failure
  # cleanup ..." or "0 failed" in a successful performance summary.
  if($text-match'(?im)^\s*(?:FAIL\b|WATCHDOG\b|SEARCH_FILTERS_INCOMPLETE\b|missing final\b)'){$marker=$false}
  $passed=(!$timedout -and $p.ExitCode-eq0 -and $marker)
  $results+=@{suite=$case;pass=$passed;exit=$p.ExitCode;timedout=$timedout;required_marker=$marker}
  if($passed){Write-Output "PASS $case"}else{Write-Output "FAIL $case (exit=$($p.ExitCode),timeout=$timedout,marker=$marker)"}
}
$results|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 (Join-Path $out 'summary.json')
$failed=@($results|Where-Object{!$_.pass})
if($failed.Count-gt0){throw "Local regression failed: $($failed.suite -join ', ')"}
# Negative controls: prove the harnesses can actually fail.
foreach($neg in @('local_watchdog_cases.js','ui_contract_negative.js')){
  & $node (Join-Path $PSScriptRoot $neg) 2>&1 | Out-File -Encoding UTF8 -Append (Join-Path $out "$neg.stdout.log")
  if($LASTEXITCODE -ne 0){throw "Negative control failed: $neg"}
  Write-Output "PASS negative-control $neg"
}
Write-Output "LOCAL_SEARCH_DOWNLOAD_PASS suites=$($results.Count); local/host fixtures only; no device or install"
exit 0
