# Native stderr warnings are diagnostic; explicit compiler/test exit codes decide failures.
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$zig=(Get-Content -LiteralPath (Join-Path $root 'logs\host-native-compiler-path.txt') -ErrorAction Stop).Trim()
if(!$zig -or !(Test-Path -LiteralPath $zig)){throw 'Verified portable host compiler missing'}
$out=Join-Path $root 'logs\native-http-codecs'
New-Item -ItemType Directory -Force $out|Out-Null
$cpp=Join-Path $root 'entry\src\main\cpp'
$zlib=Join-Path $root 'logs\host-zlib-v1.3.1'
$brotli=Join-Path $cpp 'brotli\c'
& node (Join-Path $PSScriptRoot 'generate_http_codec_vectors.js')
if($LASTEXITCODE-ne0){throw 'Codec vector generation failed'}
$objects=@()
$sources=@(Get-ChildItem -LiteralPath $zlib -Filter '*.c'|ForEach-Object {$_.FullName})
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $brotli 'common') -Filter '*.c'|ForEach-Object {$_.FullName})
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $brotli 'dec') -Filter '*.c'|ForEach-Object {$_.FullName})
$index=0
foreach($source in $sources){
  $index++;$object=Join-Path $out "part$index.obj"
  & $zig cc -O1 -DZ_SOLO -DBROTLI_BUILD_PORTABLE -I $zlib -I "$brotli\include" -c $source -o $object *> (Join-Path $out "part$index.log")
  if($LASTEXITCODE-ne0){Get-Content (Join-Path $out "part$index.log") -Tail 18;throw "Native codec compile failed $source"}
  $objects+=$object
}
$exe=Join-Path $out 'http_codec_cases.exe'
& $zig c++ -std=c++17 -O1 -I $cpp -I $zlib -I "$brotli\include" (Join-Path $PSScriptRoot 'native_runtime_tests\http_codec_cases.cpp') @objects -o $exe *> (Join-Path $out 'link.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'link.log') -Tail 20;throw 'Native codec host linking failed'}
& $exe (Join-Path $root 'logs\http-codec-vectors') (Join-Path $out 'audit.log') *> (Join-Path $out 'result.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'audit.log');throw 'Production native codec tests failed'}
Get-Content (Join-Path $out 'result.log')
