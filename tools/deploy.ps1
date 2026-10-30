# Build (optional) and install VenHM to the connected HarmonyOS device.
#
# Examples
#   .\tools\deploy.ps1                      # build + install current source
#   .\tools\deploy.ps1 -SkipBuild           # install the last built package
#   .\tools\deploy.ps1 -WaitSeconds 120     # wait for the phone first
#   .\tools\deploy.ps1 -Launch              # start the app after installing
#   .\tools\deploy.ps1 -HapPath dist\some-signed.hap
#
# Never uninstalls, never clears app data, and never launches the app unless
# -Launch is given explicitly.
param(
  [string]$HapPath = 'entry/build/default/outputs/default/entry-default-signed.hap',
  [string]$Device = '',
  [switch]$SkipBuild,
  [int]$WaitSeconds = 0,
  [switch]$Launch,
  [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$EvidenceName = 'deploy'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
# hvigor resolves hvigor/hvigor-config.json5 from the CURRENT directory. Double
# clicking deploy.cmd starts in tools\, so always build from the project root.
Set-Location -LiteralPath $root
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$buildLog = Join-Path $logDir ($EvidenceName + '-build-' + $stamp + '.log')
$installLog = Join-Path $logDir ($EvidenceName + '-install-' + $stamp + '.log')
$installErr = Join-Path $logDir ($EvidenceName + '-install-' + $stamp + '-stderr.log')

function Fail([string]$message) {
  Write-Host ('FAIL: ' + $message) -ForegroundColor Red
  exit 1
}

# ---------------------------------------------------------------- environment
$deveco = $env:DEVECO_HOME
if ([string]::IsNullOrWhiteSpace($deveco)) { $deveco = 'C:\Program Files\Huawei\DevEco Studio' }
if (!(Test-Path -LiteralPath $deveco)) { Fail ('DevEco Studio not found at ' + $deveco + ' (set DEVECO_HOME)') }
$hvigor = Join-Path $deveco 'tools\hvigor\bin\hvigorw.bat'
$hdc = Join-Path $deveco 'sdk\default\openharmony\toolchains\hdc.exe'
if (!(Test-Path -LiteralPath $hdc)) { Fail ('hdc not found at ' + $hdc) }

# ---------------------------------------------------------------- build
if (!$SkipBuild) {
  if (!(Test-Path -LiteralPath $hvigor)) { Fail ('hvigorw not found at ' + $hvigor) }
  if (!(Test-Path -LiteralPath (Join-Path $root 'hvigor\hvigor-config.json5'))) {
    Fail ('hvigor-config.json5 missing under ' + $root + '; run the script from this project')
  }
  $env:JAVA_HOME = Join-Path $deveco 'jbr'
  $env:DEVECO_SDK_HOME = Join-Path $deveco 'sdk'
  $env:PATH = (Join-Path $deveco 'tools\node') + ';' + (Join-Path $deveco 'tools\ohpm\bin') + ';' +
    (Join-Path $deveco 'tools\hvigor\bin') + ';' + (Join-Path $deveco 'jbr\bin') + ';' + $env:PATH
  Write-Host ('Building in ' + (Get-Location).Path + ' ...') -ForegroundColor Cyan
  $global:LASTEXITCODE = 0
  # hvigor writes ArkTS warnings to stderr; keep them as output instead of
  # letting Stop mode abort the deploy on a harmless warning line.
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon 2>&1 |
    Out-File -Encoding UTF8 $buildLog
  $buildExit = $LASTEXITCODE
  $ErrorActionPreference = $previousPreference
  if ($buildExit -ne 0) {
    # Surface the compiler's own first errors instead of only a log path.
    $errorLines = @()
    if (Test-Path -LiteralPath $buildLog) {
      $errorLines = Get-Content -LiteralPath $buildLog -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'ERROR|error:|Error Message' } | Select-Object -First 6
    }
    Write-Host '--- build errors ---' -ForegroundColor Yellow
    if ($errorLines.Count -gt 0) { $errorLines | ForEach-Object { Write-Host ('  ' + $_.ToString().Trim()) } }
    else {
      Write-Host '  (no ERROR line matched; last 15 log lines)' -ForegroundColor Yellow
      Get-Content -LiteralPath $buildLog -ErrorAction SilentlyContinue | Select-Object -Last 15 |
        ForEach-Object { Write-Host ('  ' + $_.ToString().TrimEnd()) }
    }
    Fail ('build failed (exit=' + $buildExit + '), full log: ' + $buildLog)
  }
  Write-Host ('Build OK (' + $buildLog + ')') -ForegroundColor Green
  $signedCandidate = Join-Path $root 'entry\build\default\outputs\default\entry-default-signed.hap'
  if (!(Test-Path -LiteralPath $signedCandidate)) {
    $unsigned = Join-Path $root 'entry\build\default\outputs\default\entry-default-unsigned.hap'
    if (Test-Path -LiteralPath $unsigned) {
      Fail ('build produced an UNSIGNED package only. Configure signing in DevEco ' +
        '(File > Project Structure > Signing Configs) or restore your local signing config, then retry.')
    }
    Fail 'build finished but the signed HAP is missing; inspect the build log'
  }
} else {
  Write-Host 'Skipping build (-SkipBuild)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- package
$hapFull = Join-Path $root $HapPath
if (!(Test-Path -LiteralPath $hapFull)) {
  Fail ('package not found: ' + $hapFull + ' - run without -SkipBuild to build it first')
}
if ([IO.Path]::GetExtension($hapFull) -ne '.hap') { Fail 'only a .hap package can be installed' }
$hapItem = Get-Item -LiteralPath $hapFull
$srcDirs = @((Join-Path $root 'entry\src'), (Join-Path $root 'AppScope'))
$newer = Get-ChildItem -Recurse -File $srcDirs -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -gt $hapItem.LastWriteTime } | Select-Object -First 1
if ($newer -and !$SkipBuild) { Fail 'package is older than the source; rerun without -SkipBuild' }
if ($newer) { Write-Host 'WARNING: package is older than the source tree.' -ForegroundColor Yellow }
$sha = (Get-FileHash -LiteralPath $hapFull -Algorithm SHA256).Hash
Write-Host ('Package: ' + $hapItem.Name + '  ' + $hapItem.Length + ' bytes')
Write-Host ('SHA-256: ' + $sha)

# ---------------------------------------------------------------- device
function Get-Targets {
  $raw = (& $hdc list targets 2>&1) | Out-String
  $found = @()
  foreach ($line in ($raw -split "`n")) {
    $t = $line.Trim()
    if ($t.Length -lt 6) { continue }
    $isId = $true
    foreach ($ch in $t.ToCharArray()) {
      if (!([char]::IsLetterOrDigit($ch))) { $isId = $false; break }
    }
    if ($isId) { $found += $t }
  }
  return $found
}

if ([string]::IsNullOrWhiteSpace($Device)) {
  $deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
  while ($true) {
    $targets = @(Get-Targets)
    if ($targets.Count -gt 0) { $Device = $targets[0]; break }
    if ((Get-Date) -ge $deadline) {
      Fail 'no device found. Connect the phone, enable USB debugging, then retry with -WaitSeconds 120'
    }
    Write-Host 'Waiting for a device ...' -ForegroundColor DarkYellow
    Start-Sleep -Seconds 3
  }
} else {
  if (@(Get-Targets) -notcontains $Device) {
    if ($WaitSeconds -gt 0) {
      $deadline = (Get-Date).AddSeconds($WaitSeconds)
      while ((Get-Date) -lt $deadline) {
        if (@(Get-Targets) -contains $Device) { break }
        Write-Host ('Waiting for device ' + $Device + ' ...') -ForegroundColor DarkYellow
        Start-Sleep -Seconds 3
      }
    }
    if (@(Get-Targets) -notcontains $Device) { Fail ('device ' + $Device + ' is not connected') }
  }
}
Write-Host ('Device: ' + $Device) -ForegroundColor Green

# ---------------------------------------------------------------- install
Write-Host 'Installing (overwrite, data preserved) ...' -ForegroundColor Cyan
$arguments = @('-t', $Device, 'install', '-r', ('"' + $hapFull + '"'))
$process = Start-Process -FilePath $hdc -ArgumentList $arguments -NoNewWindow -Wait -PassThru `
  -RedirectStandardOutput $installLog -RedirectStandardError $installErr
$stdout = Get-Content -LiteralPath $installLog -Raw -ErrorAction SilentlyContinue
$stderr = Get-Content -LiteralPath $installErr -Raw -ErrorAction SilentlyContinue
$text = '' + $stdout + "`n" + $stderr
$verified = ($process.ExitCode -eq 0) -and ($text -match '(?i)install bundle successfully') -and
  ($text -notmatch '(?i)\[Fail\]|Device not found|not connected|connect-key|install failed')
if (!$verified) { Fail ('install not verified (exit=' + $process.ExitCode + '); see ' + $installLog) }
Write-Host 'Install verified: install bundle successfully' -ForegroundColor Green

# ---------------------------------------------------------------- optional launch
if ($Launch) {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $hdc -t $Device shell aa start -a EntryAbility -b com.venerahm.reader | Out-Null
  $ErrorActionPreference = $previousPreference
  Write-Host 'Launch requested (-Launch).' -ForegroundColor Green
} else {
  Write-Host 'App not started (pass -Launch to start it).' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'DONE - data preserved, no uninstall, no data clear.' -ForegroundColor Green
Write-Host ('install log: ' + $installLog)
exit 0
