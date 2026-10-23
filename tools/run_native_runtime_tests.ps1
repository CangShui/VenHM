param([string]$Device='<device-id>')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$native='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$cmake=Join-Path $native 'build-tools\cmake\bin\cmake.exe'
$ninja=Join-Path $native 'build-tools\cmake\bin\ninja.exe'
$hdc='C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$build=Join-Path $root 'logs\native-runtime-build'
New-Item -ItemType Directory -Force $build|Out-Null
$trace='native-runtime-driver'
Add-Content -Encoding utf8 (Join-Path $root 'logs\native-runtime-driver.log') "TraceID=$trace [请求到达] crosscompile production engine; CLI binary test, no UI/unlock/app data"
& $cmake -S (Join-Path $PSScriptRoot 'native_runtime_tests') -B $build -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_TOOLCHAIN_FILE=$native\build\cmake\ohos.toolchain.cmake" -DOHOS_ARCH=arm64-v8a -DOHOS_PLATFORM_LEVEL=21 -DOHOS_STL=c++_static -DCMAKE_BUILD_TYPE=Release *> (Join-Path $build 'configure.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $build 'configure.log') -Tail 30;throw 'Native configuration failed'}
& $cmake --build $build *> (Join-Path $build 'build.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $build 'build.log') -Tail 35;throw 'Native build failed'}
$name='venera-runtime-probe-'+[DateTimeOffset]::Now.ToUnixTimeMilliseconds()
$remote="/data/local/tmp/$name"
& $hdc -t $Device file send (Join-Path $build 'venera_native_runtime_tests') $remote|Out-Null
if($LASTEXITCODE-ne0){throw 'Test binary transfer failed'}
try{
  & $hdc -t $Device shell "chmod 700 $remote && $remote $remote.log" *> (Join-Path $root 'logs\native-runtime-device-result.log')
  if((Get-Content (Join-Path $root 'logs\native-runtime-device-result.log') -Raw)-match'Permission denied'){
    Add-Content -Encoding utf8 (Join-Path $root 'logs\native-runtime-driver.log') "TraceID=$trace [平台拒绝] device denies independent executable; no policy/root/unlock workaround attempted"
    throw 'Device execution denied by platform; use host native tests and app startup probe'
  }
  & $hdc -t $Device file recv "$remote.log" (Join-Path $root 'logs\native-runtime-device-audit.log')|Out-Null
  if($LASTEXITCODE-ne0-or!(Test-Path (Join-Path $root 'logs\native-runtime-device-audit.log'))){throw 'Native device test log missing'}
  $log=Get-Content (Join-Path $root 'logs\native-runtime-device-audit.log') -Raw
  if($log-notmatch'NATIVE_TRACE_PASS assertions=\d+'-or$log-match'\[FAIL\]'){throw 'Native tests did not prove PASS'}
  Add-Content -Encoding utf8 (Join-Path $root 'logs\native-runtime-driver.log') "TraceID=$trace [响应返回] PASS native engine test; not ArkTS/NAPI/app/real login acceptance"
  Get-Content (Join-Path $root 'logs\native-runtime-device-result.log')
}finally{
  # Literal generated /data/local/tmp names; no recursive operation or app data access.
  & $hdc -t $Device shell "rm $remote $remote.log"|Out-Null
}
