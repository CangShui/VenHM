# Pre-push/pre-commit secret scan for the public repository.
# Fails when credentials, signing material, basic-auth URLs or hardware IDs are
# found in the files that would be published. Test fixtures that intentionally
# use synthetic values are allowlisted by exact file+marker, never by pattern.
param(
  [switch]$Staged,
  [string[]]$Paths
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot

# Only known text types are scanned; binary caches can contain arbitrary bytes
# and are never published (see .gitignore).
$textExtensions = @('.md','.ps1','.js','.mjs','.cjs','.ts','.ets','.tsx','.jsx','.json','.json5',
  '.yaml','.yml','.txt','.c','.h','.cpp','.hpp','.cc','.cmake','.gitignore','.xml','.svg','.html','.css','.py','.sh','.bat','.tmpl')

function Get-TargetFiles {
  if($Paths -and $Paths.Count -gt 0){
    return $Paths | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) } |
      ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) }
  }
  if($Staged){
    $names = & git -C $root diff --cached --name-only --diff-filter=ACMR
    if($LASTEXITCODE -ne 0){ throw 'git diff --cached failed' }
    return $names | Where-Object { $_ } | ForEach-Object {
      $full = Join-Path $root $_
      if(Test-Path -LiteralPath $full){ Get-Item -LiteralPath $full }
    }
  }
  return Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\(\.git|\.hvigor|\.idea|\.cxx|\.preview|node_modules|oh_modules|build|logs|dist)\\' -and
    ($textExtensions -contains $_.Extension -or $_.Name -in @('.gitignore','CMakeLists.txt')) -and
    $_.Name -notin @('secret_scan.ps1') -and
    $_.Extension -notin @('.p12','.cer','.p7b')
  }
}

# Files where a synthetic credential-looking value is the point of the test.
$fixtureAllow = @{
  'tools/account_page_cases.js' = @('synthetic')
  'tools/browser_cookie_cases.js' = @('synthetic','user:pass@fixture.invalid')
  'tools/source_account_cases.js' = @('fixture-session')
  'tools/details_cases.js' = @('user:pass@host','token=secret')
  'tools/download_sync_cases.js' = @('u:p@server')
}

$rules = @(
  @{ Name='github_token'; Regex='github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}' },
  @{ Name='cloud_key'; Regex='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' },
  @{ Name='signing_secret'; Regex='(?i)(storePassword|keyPassword|keyAlias)\s*[:=]\s*["'']' },
  @{ Name='absolute_user_path'; Regex="[A-Za-z]:\\\\?Users\\\\?(?!<user>)[^\\\s']+" },
  @{ Name='basic_auth_url'; Regex='[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]+@' },
  @{ Name='hardware_id'; Regex='\b4ZB\d{13,}\b' },
  @{ Name='real_secret_assignment'; Regex='(?i)(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]\s*["''](?!synthetic|fixture|test|example|changeme)[^"'']{8,}["'']' }
)

$findings=@()
foreach($file in Get-TargetFiles){
  if($file.PSIsContainer){ continue }
  $rel = $file.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
  $allow = $fixtureAllow[$rel]
  $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
  if($null -eq $lines){ continue }
  for($i=0; $i -lt $lines.Count; $i++){
    $line = $lines[$i]
    if([string]::IsNullOrWhiteSpace($line)){ continue }
    foreach($rule in $rules){
      if($line -match $rule.Regex){
        $skip=$false
        if($allow){ foreach($marker in $allow){ if($line.Contains($marker)){ $skip=$true } } }
        if($skip){ continue }
        $findings += [pscustomobject]@{ Rule=$rule.Name; File=$rel; Line=$i+1; Text=$line.Trim() }
      }
    }
  }
}

if($findings.Count -gt 0){
  Write-Output "SECRET_SCAN_FAIL findings=$($findings.Count)"
  $findings | Select-Object -First 40 Rule,File,Line,Text | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Output
  exit 1
}
Write-Output 'SECRET_SCAN_PASS: no credentials, signing material, basic-auth URLs, absolute user paths or hardware IDs'
exit 0
