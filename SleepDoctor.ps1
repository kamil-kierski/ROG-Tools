<#  ROG Ally Sleep Doctor  –  PS 5.1  no-flicker, ASCII  #>
function Color($t,$c){Write-Host $t -ForegroundColor $c}

# ------------ admin & bypass ------------
if (-not ( (New-Object Security.Principal.WindowsPrincipal `
            ([Security.Principal.WindowsIdentity]::GetCurrent())
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
{
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-ExecutionPolicy Bypass -Scope Process -Force

# ------------ helpers ------------
function ModernOn { $k=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
                   -Name PlatformAoAcOverride -EA 0; if(!$k){$true}else{($k.PlatformAoAcOverride -ne 0)} }
function HibOn    { (powercfg /a|Select-String 'Hibernate') -like '*available*' }
function WakeList { powercfg -devicequery wake_armed }
function LastWake { try{(powercfg /lastwake)-join' '}catch{'N/A'} }

function DisableModern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; Color 'Modern Standby disabled.' Green }
function EnableHib     { powercfg /hibernate on | Out-Null; Color 'Hibernate enabled.' Green }
function SetPowerBtn   { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3
                         powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3
                         powercfg -setactive SCHEME_CURRENT
                         Color 'Power button → Hibernate.' Green }
function DisableWakeInteractive{
  $d=WakeList; if(!$d){Color 'No wake devices.' Green; return}
  $i=1;$map=@{};foreach($dev in $d){Color ("["+($i)+"] "+$dev) Yellow;$map[$i]=$dev;$i++}
  $ch=Read-Host 'Select number or * for all'
  if($ch -eq '*'){foreach($dev in $d){powercfg -devicedisablewake "$dev"}; Color 'All disabled.' Green}
  elseif([int]::TryParse($ch,[ref]$n) -and $map[$n]){
        powercfg -devicedisablewake "$($map[$n])"; Color "$($map[$n]) disabled." Green }
}

# ------------ status header (static) ------------
Clear-Host
Color "====  CURRENT STATUS  ====" Cyan
$headerTop = [Console]::CursorTop   # remember where to rewrite status later
Color "" ""

# ------------ draw functions ------------
function Update-Status {
    $ms=ModernOn; $hib=HibOn; $w=WakeList; $lw=LastWake
    [Console]::SetCursorPosition(0, $headerTop)
    $blank = ' ' * 80
    # overwrite 4 lines
    foreach($i in 1..6){Write-Host $blank}
    [Console]::SetCursorPosition(0, $headerTop)
    Color ("Modern Standby: "+$(if($ms){'ENABLED '}else{'DISABLED'})) $(if($ms){'Red'}else{'Green'})
    Color ("Hibernate    : "+$(if($hib){'ENABLED '}else{'DISABLED'})) $(if($hib){'Green'}else{'Red'})
    Color ("Wake devices : $($w.Count)") $(if($w.Count){'Yellow'}else{'Green'})
    Color ("Last wake    : $lw") Gray
    Color "Recommendations:" Magenta
    if($ms){Color ' • Disable Modern Standby.' Yellow}
    if(-not $hib){Color ' • Enable Hibernate.' Yellow}
    if($w.Count){Color ' • Disable wake devices.' Yellow}
}

$menu = @(
 'Show status',
 'Disable Modern Standby',
 'Enable Hibernate',
 'Set PowerBtn→Hibernate',
 'Disable wake devices',
 'EXIT'
)

$menuTop = $headerTop + 8
$pos=0

function DrawMenu {
    for($i=0;$i -lt $menu.Count;$i++){
        [Console]::SetCursorPosition(0,$menuTop+$i)
        $line = if($i -eq $pos){"> "+$menu[$i]} else{"  "+$menu[$i]}
        $col  = if($i -eq $pos){ 'Black' } else { 'White' }
        $bg   = if($i -eq $pos){ 'Yellow'} else { 'Black' }
        Write-Host $line -ForegroundColor $col -BackgroundColor $bg
    }
    [Console]::SetCursorPosition(0,$menuTop+$menu.Count+1)
    Color "Use Up / Down arrows, Enter" DarkGray
}

Update-Status
DrawMenu

while($true){
    $key=[Console]::ReadKey($true).Key
    switch($key){
        'UpArrow'   { if($pos){$pos--; DrawMenu} }
        'DownArrow' { if($pos -lt $menu.Count-1){$pos++; DrawMenu} }
        'Enter' {
            switch($pos){
                0{ Update-Status }
                1{ DisableModern; Update-Status }
                2{ EnableHib;     Update-Status }
                3{ SetPowerBtn;   Update-Status }
                4{ DisableWakeInteractive; Update-Status }
                5{ break }
            }
            DrawMenu
        }
    }
}

Color "`nExiting..." Gray
