# Windows PowerShell surfaces native compiler warnings as NativeCommandError.
# Preserve them in logs; native exit codes, not harmless stderr, determine failure.
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$zig=(Get-Content -LiteralPath (Join-Path $root 'logs\host-native-compiler-path.txt') -ErrorAction Stop).Trim()
if(!$zig -or !(Test-Path -LiteralPath $zig)){throw 'Verified portable host compiler missing'}
$out=Join-Path $root 'logs\isolated-native-host'
New-Item -ItemType Directory -Force $out|Out-Null
$cpp=Join-Path $root 'entry\src\main\cpp'
$q=Join-Path $cpp 'quickjs'
$objects=@()
foreach($name in @('dtoa.c','libregexp.c','libunicode.c','quickjs.c')){
  $object=Join-Path $out "$name.obj"
  & $zig cc -std=c11 -O1 -D_GNU_SOURCE -I $q -c (Join-Path $q $name) -o $object *> (Join-Path $out "$name.log")
  if($LASTEXITCODE-ne0){Get-Content (Join-Path $out "$name.log") -Tail 15;throw 'Isolated C compilation failed'}
  $objects+=$object
}
$sources=@((Join-Path $cpp 'js_engine.cpp'),(Join-Path $cpp 'isolated_engine.cpp'),(Join-Path $PSScriptRoot 'native_runtime_tests\isolated_cases.cpp'))
foreach($source in $sources){
  $name=[IO.Path]::GetFileName($source);$object=Join-Path $out "$name.obj"
  & $zig c++ -std=c++17 -O1 -I $cpp -I $q -c $source -o $object *> (Join-Path $out "$name.log")
  if($LASTEXITCODE-ne0){Get-Content (Join-Path $out "$name.log") -Tail 25;throw 'Isolated C++ compilation failed'}
  $objects+=$object
}
$exe=Join-Path $out 'isolated_cases.exe'
& $zig c++ @objects -o $exe *> (Join-Path $out 'link.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'link.log') -Tail 15;throw 'Isolated linking failed'}
& $exe (Join-Path $root 'entry\src\main\resources\rawfile\init.js') (Join-Path $root 'entry\src\main\resources\rawfile\html_engine.js') (Join-Path $out 'audit.log') *> (Join-Path $out 'result.log')
if($LASTEXITCODE-ne0){Get-Content (Join-Path $out 'audit.log') -Tail 20;Get-Content (Join-Path $out 'result.log');throw 'Production isolated engine tests failed'}
Get-Content (Join-Path $out 'result.log')
