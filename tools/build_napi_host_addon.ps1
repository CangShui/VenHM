# Build EXACT production runtime/NAPI translation units against standard Node
# NAPI on Windows. Real host threads, callbacks, GC and cleanup, NOT OHOS proof.
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$zig=(Get-Content -LiteralPath (Join-Path $root 'logs\host-native-compiler-path.txt') -ErrorAction Stop).Trim()
$nodeDeps=(Get-Content -LiteralPath (Join-Path $root 'logs\node-napi-host-path.txt') -ErrorAction Stop).Trim()
if(!(Test-Path $zig) -or !(Test-Path (Join-Path $nodeDeps 'node.lib'))){throw 'Verified host NAPI build dependencies missing'}
$out=Join-Path $root 'logs\napi-host'; New-Item -ItemType Directory -Force $out -ErrorAction Stop|Out-Null
$cpp=Join-Path $root 'entry\src\main\cpp';$q=Join-Path $cpp 'quickjs';$zlib=Join-Path $root 'logs\host-zlib-v1.3.1'
$brotli=Join-Path $cpp 'brotli\c';$headers=Join-Path $nodeDeps 'node-v24.14.1\include\node'
$shim=Join-Path $PSScriptRoot 'napi_host_tests\include';$objects=@();$index=0
$sources=@('dtoa.c','libregexp.c','libunicode.c','quickjs.c'|ForEach-Object {Join-Path $q $_})
$sources+=@(Get-ChildItem -LiteralPath $zlib -Filter '*.c' -ErrorAction Stop|ForEach-Object {$_.FullName})
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $brotli 'common') -Filter '*.c' -ErrorAction Stop|ForEach-Object {$_.FullName})
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $brotli 'dec') -Filter '*.c' -ErrorAction Stop|ForEach-Object {$_.FullName})
foreach($source in $sources){
  $index++;$object=Join-Path $out "native$index.obj"
  & $zig cc -std=c11 -O1 -D_GNU_SOURCE -DZ_SOLO -DBROTLI_BUILD_PORTABLE -I $q -I $zlib -I "$brotli\include" -c $source -o $object 2>&1|Out-File -Encoding UTF8 (Join-Path $out "native$index.log")
  if($LASTEXITCODE-ne0){throw "Host NAPI native compilation failed: $source"};$objects+=$object
}
foreach($name in @('js_engine.cpp','isolated_engine.cpp','worker_napi.cpp','napi_init.cpp')){
  $object=Join-Path $out "$name.obj"
  & $zig c++ -std=c++17 -O1 -DNAPI_VERSION=8 -I $shim -I $headers -I $cpp -I $q -I $zlib -I "$brotli\include" -c (Join-Path $cpp $name) -o $object 2>&1|Out-File -Encoding UTF8 (Join-Path $out "$name.log")
  if($LASTEXITCODE-ne0){throw "Production host NAPI C++ compilation failed: $name"};$objects+=$object
}
$addon=Join-Path $out 'venerajs.node'
& $zig c++ -shared @objects (Join-Path $nodeDeps 'node.lib') -o $addon 2>&1|Out-File -Encoding UTF8 (Join-Path $out 'link.log')
if($LASTEXITCODE-ne0){throw 'Production host NAPI linking failed'}
& $zig c++ -shared -std=c++17 -O1 -DNAPI_VERSION=8 -I $headers (Join-Path $PSScriptRoot 'napi_host_tests\foreign_external.cpp') (Join-Path $nodeDeps 'node.lib') -o (Join-Path $out 'foreign_external.node') 2>&1|Out-File -Encoding UTF8 (Join-Path $out 'foreign.log')
if($LASTEXITCODE-ne0){throw 'Foreign external test addon linking failed'}
Get-FileHash $addon -Algorithm SHA256 | Format-List|Out-File -Encoding UTF8 (Join-Path $out 'addon-sha256.txt')
Write-Output 'PRODUCTION_NAPI_HOST_ADDON_BUILD_PASS'
