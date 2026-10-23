# Venera HM - 端到端自动化测试脚本
#
# 用途：把"改代码 -> 编译 -> 签名 -> 安装 -> 启动 -> 读界面 -> 读日志 -> 截图"
# 全部自动化，无需人工在手机上操作。
#
# 前置条件（一次性）：
#   DevEco Studio -> File -> Project Structure -> Signing Configs
#   -> 勾选 Automatically generate signature -> 登录华为账号 -> Apply
#   之后 build-profile.json5 会写入 signingConfigs，product 里需要引用
#   "signingConfig": "default"（本仓库已配置）。
#
# 用法：
#   pwsh -File tools/e2e.ps1 -Action build
#   pwsh -File tools/e2e.ps1 -Action run          # build + install + launch
#   pwsh -File tools/e2e.ps1 -Action ui           # 导出界面文字
#   pwsh -File tools/e2e.ps1 -Action logs         # 导出本应用日志
#   pwsh -File tools/e2e.ps1 -Action shot         # 截图到 dist/
#   pwsh -File tools/e2e.ps1 -Action tap -X 100 -Y 200

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('build', 'run', 'ui', 'logs', 'shot', 'tap', 'swipe', 'key')]
  [string]$Action,
  [int]$X = 0,
  [int]$Y = 0,
  [int]$X2 = 0,
  [int]$Y2 = 0,
  [string]$Key = 'Back'
)

$ErrorActionPreference = 'Stop'
$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
$Root = Split-Path -Parent $PSScriptRoot
$Hdc = "$DevEco\sdk\default\openharmony\toolchains\hdc.exe"
$Bundle = 'com.venerahm.reader'
$Ability = 'EntryAbility'
$Tag = 'VeneraHM'

$env:JAVA_HOME = "$DevEco\jbr"
$env:DEVECO_SDK_HOME = "$DevEco\sdk"
$env:PATH = "$DevEco\tools\hvigor\bin;$DevEco\tools\ohpm\bin;$DevEco\tools\node;$DevEco\jbr\bin;$env:PATH"

function Invoke-Build {
  Push-Location $Root
  try {
    & "$DevEco\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap 2>&1 |
      Out-File -Encoding utf8 "$env:TEMP\venera_build.log"
    $ok = Select-String -Path "$env:TEMP\venera_build.log" -Pattern 'BUILD SUCCESSFUL' -Quiet
    if (-not $ok) {
      Select-String -Path "$env:TEMP\venera_build.log" -Pattern 'Error Message' -Context 0, 1 |
        ForEach-Object { $_.Line.Trim(); $_.Context.PostContext | ForEach-Object { "   $($_.Trim())" } } |
        Select-Object -First 20
      throw 'build failed'
    }
    Write-Output 'BUILD SUCCESSFUL'
  } finally {
    Pop-Location
  }
}

function Get-SignedHap {
  $path = "$Root\entry\build\default\outputs\default\entry-default-signed.hap"
  if (-not (Test-Path $path)) { throw "signed hap not found: $path" }
  return $path
}

function Install-And-Launch {
  $hap = Get-SignedHap
  & $Hdc install -r $hap 2>&1 | Select-Object -First 3
  & $Hdc shell "aa start -b $Bundle -a $Ability" 2>&1 | Select-Object -First 2
  Start-Sleep -Seconds 6
}

function Get-UiText {
  & $Hdc shell "uitest dumpLayout -p /data/local/tmp/layout.json" 2>&1 | Out-Null
  & $Hdc file recv /data/local/tmp/layout.json "$env:TEMP\venera_layout.json" 2>&1 | Out-Null
  $json = Get-Content "$env:TEMP\venera_layout.json" -Raw -Encoding utf8
  $texts = [regex]::Matches($json, '"text"\s*:\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Where-Object { $_.Trim().Length -gt 0 } |
    Select-Object -Unique
  return ($texts -join ' | ')
}

function Get-AppLogs {
  & $Hdc shell "hilog -x" 2>&1 |
    Select-String -CaseSensitive -Pattern $Tag |
    Select-Object -Last 60 |
    ForEach-Object { $_.Line.Trim() }
}

switch ($Action) {
  'build' { Invoke-Build }
  'run' { Invoke-Build; Install-And-Launch; Get-UiText }
  'ui' { Get-UiText }
  'logs' { Get-AppLogs }
  'shot' {
    New-Item -ItemType Directory -Force -Path "$Root\dist" | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    & $Hdc shell "snapshot_display -f /data/local/tmp/shot.jpeg" 2>&1 | Out-Null
    & $Hdc file recv /data/local/tmp/shot.jpeg "$Root\dist\shot_$stamp.jpeg" 2>&1 | Select-Object -First 1
    Write-Output "$Root\dist\shot_$stamp.jpeg"
  }
  'tap' { & $Hdc shell "uitest uiInput click $X $Y" 2>&1 | Select-Object -First 2 }
  'swipe' { & $Hdc shell "uitest uiInput swipe $X $Y $X2 $Y2" 2>&1 | Select-Object -First 2 }
  'key' { & $Hdc shell "uitest uiInput keyEvent $Key" 2>&1 | Select-Object -First 2 }
}
