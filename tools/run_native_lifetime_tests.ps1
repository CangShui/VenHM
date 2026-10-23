# Execute the production ownership helper in actual QuickJS, no NAPI mocks.
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$zig=(Get-Content -LiteralPath (Join-Path $root 'logs\host-native-compiler-path.txt') -ErrorAction Stop).Trim()
if(!$zig -or !(Test-Path -LiteralPath $zig)){throw 'Verified host compiler missing'}
$out=Join-Path $root 'logs\native-lifetime-host'
New-Item -ItemType Directory -Force $out -ErrorAction Stop|Out-Null
$cpp=Join-Path $root 'entry\src\main\cpp'; $q=Join-Path $cpp 'quickjs'; $objects=@()
foreach($name in @('dtoa.c','libregexp.c','libunicode.c','quickjs.c')){
  $object=Join-Path $out "$name.obj"
  & $zig cc -std=c11 -O1 -D_GNU_SOURCE -I $q -c (Join-Path $q $name) -o $object 2>&1 | Out-File -Encoding UTF8 (Join-Path $out "$name.log")
  if($LASTEXITCODE-ne0){throw "Lifetime C compilation failed: $name"}; $objects+=$object
}
foreach($source in @((Join-Path $cpp 'js_engine.cpp'),(Join-Path $PSScriptRoot 'native_runtime_tests\lifetime_cases.cpp'))){
  $name=[IO.Path]::GetFileName($source);$object=Join-Path $out "$name.obj"
  & $zig c++ -std=c++17 -O1 -I $cpp -I $q -c $source -o $object 2>&1 | Out-File -Encoding UTF8 (Join-Path $out "$name.log")
  if($LASTEXITCODE-ne0){throw "Lifetime C++ compilation failed: $name"}; $objects+=$object
}
$exe=Join-Path $out 'lifetime_cases.exe'
& $zig c++ @objects -o $exe 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'link.log')
if($LASTEXITCODE-ne0){throw 'Lifetime linking failed'}
& $exe (Join-Path $out 'audit.log') 2>&1 | Out-File -Encoding UTF8 (Join-Path $out 'result.log')
if($LASTEXITCODE-ne0){throw 'Production lifetime tests failed'}
Get-Content (Join-Path $out 'result.log')
