param(
  [Parameter(Mandatory=$true)][string]$CliPath,
  [ValidateSet('edit','verify','cleanup')][string]$Stage='edit',
  [string]$Device='<device-id>'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'logs\source-settings-device'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$audit=Join-Path $out 'audit.log'
$trace="settings-device-$Stage-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
$script:sequence=0
function Audit($stage,$message) {
  Add-Content -Encoding utf8 $audit "$(Get-Date -Format o) TraceID=$trace [$stage] $message"
}
function InvokeDevEco([string[]]$Arguments) {
  Audit 'CLI请求' ($Arguments -join ' ')
  $result=& node $CliPath @Arguments 2> (Join-Path $out 'stderr.log')
  if($LASTEXITCODE-ne0){throw "CLI failed: $($Arguments -join ' ')"}
  Audit 'CLI响应' 'exit=0'
  return $result
}
function Snapshot {
  $script:sequence++
  $json=(InvokeDevEco @('ui','layout','--device',$Device,'--format','json'))-join "`n"
  $json | Set-Content -Encoding utf8 (Join-Path $out "$Stage-$($script:sequence).json")
  return ($json|ConvertFrom-Json)
}
function Flatten($n){$n;foreach($c in $n.children){Flatten $c}}
function Nodes($tree){foreach($n in $tree){Flatten $n}}
function Has($tree,$text){return [bool](@(Nodes $tree|Where-Object text -eq $text).Count)}
function ClickNode($node,$tree) {
  $b=$node.bounds;$max=$tree[0].bounds
  $x=[int](($b[0]+$b[2])/2);$y=[int](($b[1]+$b[3])/2)
  if($b[2]-le$b[0] -or $b[3]-le$b[1] -or $y-lt0 -or $y-ge$max[3] -or $x-lt0 -or $x-ge$max[2]){
    throw 'Refusing click on invisible/out-of-screen node'
  }
  InvokeDevEco @('ui','click',"$x","$y",'--device',$Device)|Out-Null
}
function ClickText($text) {
  $tree=Snapshot
  $matches=@(Nodes $tree|Where-Object text -eq $text)
  $clickable=@($matches|Where-Object clickable -eq $true)
  if($clickable.Count-eq1){ClickNode $clickable[0] $tree;return}
  if($matches.Count-ne1){throw "Expected unique text: $text"}
  ClickNode $matches[0] $tree
}
function Expect($pattern,[bool]$ScrollToFind=$false) {
  $tree=Snapshot
  if($ScrollToFind -and -not(@(Nodes $tree|Where-Object { $_.text-match$pattern }).Count)){
    if(-not(Has $tree '离线可用性验收')){throw 'Refusing to scroll unknown page'}
    InvokeDevEco @('ui','swipe','1200','2400','1200','900','--device',$Device)|Out-Null
    $tree=Snapshot
  }
  for($retry=0;$retry-lt2 -and -not(@(Nodes $tree|Where-Object { $_.text-match$pattern }).Count);$retry++){
    Start-Sleep -Milliseconds 200
    $tree=Snapshot
  }
  if(-not(@(Nodes $tree|Where-Object { $_.text-match$pattern }).Count)){throw "Expected: $pattern"}
  Audit '断言通过' $pattern
  return $tree
}
function OpenFixture {
  $tree=Snapshot
  if(Has $tree 'Venera HM'){
    ClickText '历史'
    $tree=Snapshot
  }
  if(Has $tree '阅读历史'){
    if($Stage-eq'edit'){
      $baseline=@(Nodes $tree|Where-Object {$_.text-match'^共 \d+ 条'})
      if($baseline.Count-ne1){throw 'Cannot capture history baseline'}
      $baseline[0].text|Set-Content -Encoding utf8 (Join-Path $out 'history-baseline.txt')
      Audit '数据基线' $baseline[0].text
    }
    ClickText '离线验收'
    $tree=Snapshot
  }
  if(Has $tree '离线可用性验收'){
    if($Stage-eq'cleanup'){return}
    ClickText '打开离线源设置样本'
  }
  Expect '^离线源设置样本 · 源设置$' | Out-Null
}
function VerifyToggleChecked {
  # devecocli's JSON projection omits "checked", even in full mode.
  # Read the raw HDC/uitest attributes instead of treating missing as false.
  $hdc=Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
  $file=Join-Path $out 'verify-raw-toggle.json'
  Audit '原始UI读取' '通过HDC读取Toggle.checked；CLI投影不包含此属性'
  & $hdc -t $Device shell 'uitest dumpLayout -p /data/local/tmp/hm-setting-toggle.json' | Out-Null
  if($LASTEXITCODE-ne0){throw 'Raw layout dump failed'}
  & $hdc -t $Device file recv /data/local/tmp/hm-setting-toggle.json $file | Out-Null
  if($LASTEXITCODE-ne0){throw 'Raw layout transfer failed'}
  $raw=Get-Content $file -Raw|ConvertFrom-Json
  function Attributes($n){$n.attributes;foreach($c in $n.children){Attributes $c}}
  $toggle=@(Attributes $raw|Where-Object type -eq 'Toggle')
  if($toggle.Count-ne1-or$toggle[0].checked-ne'true'){throw 'Boolean mode lost across process restart'}
  Audit '断言通过' '原始UI Toggle.checked=true'
}
try{
  Audit '请求到达' "阶段=$Stage；仅修改带标记的离线样本；不登录、不联网、不修改实际源"
  OpenFixture
  if($Stage-eq'edit'){
    ClickText '保存'
    Expect '必须输入42'|Out-Null
    $tree=Snapshot
    $inputs=@(Nodes $tree|Where-Object type -eq 'TextInput')
    if($inputs.Count-ne1){throw 'Expected one isolated input'}
    $b=$inputs[0].bounds
    InvokeDevEco @('ui','text','42',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device)|Out-Null
    ClickText '保存'
    $tree=Expect '^数值零$'
    $input=@(Nodes $tree|Where-Object type -eq 'TextInput')
    if($input[0].text-ne'42'){throw 'Input not saved as 42'}
    $select=@(Nodes $tree|Where-Object type -eq 'Select')
    if($select.Count-ne1){throw 'Expected one select'}
    ClickNode $select[0] $tree
    Expect '^动态一$'|Out-Null
    ClickText '动态一'
    $tree=Snapshot
    $toggle=@(Nodes $tree|Where-Object type -eq 'Toggle')
    if($toggle.Count-ne1){throw 'Expected one toggle'}
    ClickNode $toggle[0] $tree
    Expect '^当前值：1$'|Out-Null
    $tree=Snapshot
    $select=@(Nodes $tree|Where-Object type -eq 'Select')
    ClickNode $select[0] $tree
    $tree=Expect '^动态二$'
    if(Has $tree '动态一'){throw 'Old dynamic option remained after toggle'}
    ClickText '布尔false'
    Expect '^布尔false$'|Out-Null
    ClickText '执行无副作用回调'
    Expect '^回调计数：1$'|Out-Null
    Audit '响应返回' 'PASS edit: async validator/receiver, primitive false, dynamic options, stale selection, callback getter refresh'
    'PASS source settings device edit'
  }elseif($Stage-eq'verify'){
    $tree=Expect '^布尔false$'
    $input=@(Nodes $tree|Where-Object type -eq 'TextInput')
    if($input.Count-ne1-or$input[0].text-ne'42'){throw 'Input lost across process restart'}
    VerifyToggleChecked
    Expect '^回调计数：1$'|Out-Null
    Audit '响应返回' 'PASS verify: input42, mode true, typed choice false, callback_count=1 persisted across process restart'
    'PASS source settings device cold persistence'
  }else{
    $tree=Snapshot
    if(Has $tree '离线源设置样本 · 源设置'){ClickText '‹ 返回'}
    Expect '^离线可用性验收$'|Out-Null
    ClickText '清理离线源设置样本'
    Expect '^PASS · 已清理离线源设置样本；未修改真实源$' $true|Out-Null
    InvokeDevEco @('ui','swipe','1200','800','1200','2450','--device',$Device)|Out-Null
    ClickText '‹ 返回'
    $tree=Expect '^阅读历史$'
    $baseline=(Get-Content (Join-Path $out 'history-baseline.txt') -Raw).Trim()
    if(-not(Has $tree $baseline)){throw 'History count changed from baseline; no restoration attempted'}
    Audit '响应返回' "PASS cleanup: fixture SQL rows removed/flag cleared; history baseline unchanged: $baseline"
    'PASS source settings device fixture cleanup'
  }
}catch{
  Audit '异常' "$($_.Exception.Message)；已停止，不盲点、不删除真实数据"
  throw
}
