param()
# Native stderr warnings are diagnostic; explicit compiler/test exit codes decide failures.
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$zig=(Get-Content -LiteralPath (Join-Path $root 'logs\host-native-compiler-path.txt')).Trim()
if(!(Test-Path -LiteralPath $zig)){throw 'Verified portable host compiler missing'}
$out=Join-Path $root 'logs\native-runtime-host'
New-Item -ItemType Directory -Force $out|Out-Null
$q=Join-Path $root 'entry\src\main\cpp\quickjs'
$cpp=Join-Path $root 'entry\src\main\cpp'
$objects=@()
foreach($source in @('dtoa.c','libregexp.c','libunicode.c','quickjs.c')){
  $obj=Join-Path $out "$source.obj"
  & $zig cc -std=c11 -O1 -D_GNU_SOURCE -I $q -c (Join-Path $q $source) -o $obj *> (Join-Path $out "$source.log")
  if($LASTEXITCODE-ne0){Get-Content (Join-Path $out "$source.log") -Tail 20;throw "Native host compile failed: $source"}
  $objects+=$obj
}
foreach($source in @((Join-Path $cpp 'js_engine.cpp'),(Join-Path $PSScriptRoot 'native_runtime_tests\trace_cases.cpp'))){
  $obj=Join-Path $out "$([IO.Path]::GetFileName($source)).obj"
  & $zig c++ -std=c++17 -O1 -I $q -I $cpp -c $source -o $obj *> (Join-Path $out "$([IO.Path]::GetFileName($source)).log")
  if($LASTEXITCODE-ne0){Get-Content (Join-Path $out "$([IO.Path]::GetFileName($source)).log") -Tail 20;throw 'Native host C++ compile failed'}
  $objects+=$obj
}
$exe=Join-Path $out 'trace_cases.exe'
& $zig c++ -O1 @objects -o $exe *> (Join-Path $out 'link.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'link.log') -Tail 20;throw 'Host linking failed'}
& $exe (Join-Path $out 'audit.log') *> (Join-Path $out 'result.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'audit.log') -Tail 20;throw 'Production native trace test failed'}
Get-Content (Join-Path $out 'result.log')
