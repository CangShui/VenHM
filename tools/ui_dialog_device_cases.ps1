param(
  [Parameter(Mandatory=$true)][string]$CliPath,
  [string]$Device='<device-id>',
  [string]$EvidenceName='ui-dialog-device'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root "logs\$EvidenceName"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$trace="ui-device-$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
$audit=Join-Path $out 'audit.log'
$script:step=0
function Audit($stage,$message) {
  Add-Content -Encoding utf8 $audit "$(Get-Date -Format o) TraceID=$trace [$stage] $message"
}
function InvokeDevEco([string[]]$Arguments) {
  Audit 'CLI请求' ($Arguments -join ' ')
  $result=& node $CliPath @Arguments 2> (Join-Path $out 'cli-stderr.log')
  if($LASTEXITCODE -ne 0) {
    Audit 'CLI异常' "exit=$LASTEXITCODE；停止，不盲点"
    throw "CLI failed: $($Arguments -join ' ')"
  }
  Audit 'CLI响应' 'exit=0'
  return $result
}
function Snapshot {
  $script:step++
  $json=(InvokeDevEco @('ui','layout','--device',$Device,'--format','json')) -join "`n"
  $json | Set-Content -Encoding utf8 (Join-Path $out "$($script:step)-layout.json")
  return ($json | ConvertFrom-Json)
}
function Flatten($node) {
  $node
  foreach($child in $node.children) { Flatten $child }
}
function Nodes($tree) {
  foreach($node in $tree) { Flatten $node }
}
function DialogNodes($tree) {
  $dialogs=@(Nodes $tree | Where-Object type -eq 'Dialog')
  if($dialogs.Count -ne 1) {
    Audit '前置拒绝' "期望1个活动对话框，实际$($dialogs.Count)；不点击"
    throw 'Expected one active dialog'
  }
  return @(Flatten $dialogs[0])
}
function ClickText($text,[bool]$InDialog=$true) {
  $tree=Snapshot
  $nodes=if($InDialog) { DialogNodes $tree } else { Nodes $tree }
  $matches=@($nodes | Where-Object { $_.text -eq $text -and $_.clickable })
  if($matches.Count -ne 1) {
    Audit '前置拒绝' "目标文字=$text，唯一可点击节点数=$($matches.Count)；不点击"
    throw "Expected unique clickable text: $text"
  }
  $b=$matches[0].bounds
  $x=[int](($b[0]+$b[2])/2); $y=[int](($b[1]+$b[3])/2)
  InvokeDevEco @('ui','click',"$x","$y",'--device',$Device) | Out-Null
}
function ExpectText($text) {
  $nodes=DialogNodes (Snapshot)
  if(-not ($nodes | Where-Object text -eq $text)) {
    Audit '断言失败' "对话框缺少预期文字=$text"
    throw "Missing text: $text"
  }
  Audit '断言通过' "对话框文字=$text"
}
try {
  Audit '请求到达' '仅操作应用的无副作用UI自检，不登录源、不联网、不生成漫画、不删除数据；入口应为历史页或离线验收页'
  $tree=Snapshot
  if(Nodes $tree|Where-Object text -eq 'Venera HM'){
    ClickText '历史' $false
    $tree=Snapshot
  }
  if(Nodes $tree | Where-Object text -eq '离线验收') {
    ClickText '离线验收' $false
  }
  ClickText '运行 UI 对话框自检（需手动操作）' $false
  ExpectText 'UI 自检：请输入 42'
  ClickText '确定'
  ExpectText '必须输入 42'
  $inputs=@(DialogNodes (Snapshot) | Where-Object type -eq 'TextInput')
  if($inputs.Count -ne 1) { throw 'Expected one input field' }
  $b=$inputs[0].bounds
  $x=[int](($b[0]+$b[2])/2); $y=[int](($b[1]+$b[3])/2)
  InvokeDevEco @('ui','text','42',"$x","$y",'--device',$Device) | Out-Null
  ClickText '确定'
  ExpectText 'UI 自检：请选择一项'
  $nodes=@(DialogNodes (Snapshot))
  $selected=@($nodes | Where-Object text -eq '●')
  if($selected.Count -ne 1) { throw 'Initial selection is not unique' }
  $at=[Array]::IndexOf($nodes,$selected[0])
  if($nodes[$at+1].text -ne '乙') { throw 'Initial index 1 did not select 乙' }
  # The label itself is not clickable; its parent Row owns the handler.
  $options=@($nodes | Where-Object text -eq '丙')
  if($options.Count -ne 1) { throw 'Expected one 丙 option' }
  $b=$options[0].bounds
  InvokeDevEco @('ui','click',"$([int](($b[0]+$b[2])/2))","$([int](($b[1]+$b[3])/2))",'--device',$Device) | Out-Null
  ExpectText 'UI 自检：确认对话框'
  ClickText '确定'
  ExpectText 'UI 自检：加载框已关闭'
  ClickText '确定'
  ExpectText 'UI 自检：请取消输入'
  ClickText '取消'
  ExpectText 'UI 自检：请取消选择'
  if(DialogNodes (Snapshot) | Where-Object text -eq '●') { throw 'Out-of-range initial index was not discarded' }
  ClickText '取消'
  ExpectText '加载中…'
  ClickText '取消'
  ExpectText 'UI 自检：取消回调完成'
  ClickText '确定'
  $tree=Snapshot
  if(Nodes $tree | Where-Object type -eq 'Dialog') { throw 'Residual dialog after completion' }
  $result=@(Nodes $tree | Where-Object { $_.text -like 'UI 自检结果：PASS*' })
  if($result.Count-eq0-and (Nodes $tree|Where-Object text -eq '离线可用性验收')){
    InvokeDevEco @('ui','swipe','1200','2400','1200','900','--device',$Device)|Out-Null
    $tree=Snapshot
    $result=@(Nodes $tree | Where-Object { $_.text -like 'UI 自检结果：PASS*' })
  }
  if($result.Count -ne 1) { throw 'Missing PASS result; inspect saved layouts' }
  if($result[0].text -notmatch 'input=42.*select=2.*dialog=1.*cancelInput=null.*cancelSelect=null.*onCancel=1') {
    throw 'Unexpected script results'
  }
  if($result[0].text -notmatch 'auditFile=true') {
    throw 'App did not confirm the audit TraceID was read back from disk'
  }
  Audit '响应返回' $result[0].text
  Write-Output $result[0].text
  Write-Output "Evidence: $out"
} catch {
  Audit '异常' "$($_.Exception.Message)；已停止，不尝试盲点或清数据"
  throw
}
