<# ROG Ally Sleep Doctor – PS 5.1 safe #>
function Color([string]$t,[string]$c){Write-Host $t -ForegroundColor $c}
function IsAdmin {
    (New-Object Security.Principal.WindowsPrincipal(
      [Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if(-not (IsAdmin)){
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-ExecutionPolicy Bypass -Scope Process -Force

function ModernOn { $k=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name PlatformAoAcOverride -EA 0; if(!$k){$true}else{($k.PlatformAoAcOverride -ne 0)} }
function HibOn    { (powercfg /a|Select-String 'Hibernate') -like '*available*' }
function WakeList { powercfg -devicequery wake_armed }
function LastWake { try{(powercfg /lastwake)-join' '}catch{'N/A'} }

function Status {
    $ms=ModernOn; $hib=HibOn; $w=WakeList; $lw=LastWake
    Color "`n==== CURRENT STATUS ====" Cyan
    Color ("Modern Standby: "+$(if($ms){'ENABLED'}else{'DISABLED'})) $(if($ms){'Red'}else{'Green'})
    Color ("Hibernate    : "+$(if($hib){'ENABLED'}else{'DISABLED'})) $(if($hib){'Green'}else{'Red'})
    Color ("Wake devices : $($w.Count)") $(if($w.Count){'Yellow'}else{'Green'})
    Color ("Last wake    : $lw") Gray
    Color "`nRecommendations:" Magenta
    if($ms){Color ' • Disable Modern Standby.' Yellow}
    if(-not $hib){Color ' • Enable Hibernate.' Yellow}
    if($w.Count){Color ' • Disable wake devices.' Yellow}
    Color '==========================' Cyan
}

function DisableModern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; Color 'Modern Standby disabled.' Green }
function EnableHib     { powercfg /hibernate on|Out-Null; Color 'Hibernate enabled.' Green }
function SetPowerBtn   { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT; Color 'Power button → Hibernate.' Green }

function DisableWakeInteractive{
    $d=WakeList; if(!$d){Color 'No wake devices.' Green; return}
    $i=1;$map=@{};foreach($dev in $d){Color "[$i] $dev" Yellow;$map[$i]=$dev;$i++}
    $ch=Read-Host 'Select number or * for all'
    if($ch -eq '*'){foreach($dev in $d){powercfg -devicedisablewake "$dev"}; Color 'All disabled.' Green}
    elseif([int]::TryParse($ch,[ref]$n) -and $map[$n]){powercfg -devicedisablewake "$($map[$n])"; Color "$($map[$n]) disabled." Green}
}

# menu loop
$menu = @('Show status','Disable Modern Standby','Enable Hibernate','Set PowerBtn→Hibernate','Disable wake devices','EXIT')
$pos  = 0
function Draw{
  Clear-Host; Status
  Color "`nUse ↑ ↓ arrows, Enter`n" DarkGray
  for($j=0;$j -lt $menu.Count;$j++){
    if($j -eq $pos){Write-Host "> $($menu[$j])" -ForegroundColor Black -BackgroundColor Yellow}
    else{Write-Host "  $($menu[$j])"}
  }
}
while($true){
  Draw
  $key = [Console]::ReadKey($true).Key
  switch($key){
    'UpArrow'   { if($pos){$pos--} }
    'DownArrow' { if($pos -lt $menu.Count-1){$pos++} }
    'Enter' {
        switch($pos){
          0{Status;Pause}
          1{DisableModern;Pause}
          2{EnableHib;Pause}
          3{SetPowerBtn;Pause}
          4{DisableWakeInteractive;Pause}
          5{break}
        }
    }
  }
}
