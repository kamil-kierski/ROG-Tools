<#  ROG Ally Sleep Doctor – PS 5.1, arrow-menu  #>

# --- auto-elevate & EP bypass
if (-not ([Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
  exit
}
Set-ExecutionPolicy Bypass -Scope Process -Force

# --- safe color
function C([string]$t,[string]$col){try{Write-Host $t -ForegroundColor ([ConsoleColor]$col)}catch{Write-Host $t}}

# --- helpers
function ModernOn { $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name PlatformAoAcOverride -EA 0; if(!$k){$true}else{($k.PlatformAoAcOverride -ne 0)} }
function HibOn    { (powercfg /a | Select-String 'Hibernate') -like '*available*' }
function WakeList { powercfg -devicequery wake_armed }
function LastWake { try{(powercfg /lastwake)-join' '}catch{'N/A'} }

# --- fixes
function DisableModern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; C 'Modern Standby disabled (S3 enabled).' Green }
function EnableHib     { powercfg /hibernate on | Out-Null; C 'Hibernate enabled.' Green }
function SetPowerBtn   { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT; C 'Power-button → Hibernate.' Green }
function DisableWakeInt{
  $d=WakeList; if(!$d){C 'No wake devices.' Green; return}
  $i=1;$map=@{}; foreach($dev in $d){C "[$i] $dev" Yellow; $map[$i]=$dev; $i++}
  $sel=Read-Host 'Select number or * for all'; if($sel -eq '*'){
      foreach($dev in $d){powercfg -devicedisablewake "$dev"}; C 'All wake devices disabled.' Green
  } elseif($map[$sel]){ powercfg -devicedisablewake "$($map[$sel])"; C "$($map[$sel]) disabled." Green }
}

# --- status
function Status{
  $ms=ModernOn; $hib=HibOn; $w=WakeList; $lw=LastWake
  C "`n====  CURRENT STATUS  ====" Cyan
  C ("Modern Standby: "+$(if($ms){'ENABLED'}else{'DISABLED'})) $(if($ms){'Red'}else{'Green'})
  C ("Hibernate      : "+$(if($hib){'ENABLED'}else{'DISABLED'})) $(if($hib){'Green'}else{'Red'})
  C ("Wake devices   : $($w.Count)") $(if($w.Count){'Yellow'}else{'Green'})
  C ("Last wake      : $lw") Gray
  C "`nRecommendations:" Magenta
  if($ms){C ' • Disable Modern Standby.' Yellow}
  if(-not $hib){C ' • Enable Hibernate.' Yellow}
  if($w.Count){C ' • Disable wake devices.' Yellow}
  C '==============================' Cyan
}

# --- arrow-menu
$menu = @(
  'Show status',
  'Disable Modern Standby',
  'Enable Hibernate',
  'Set Power-button → Hibernate',
  'Disable wake devices',
  'EXIT'
)
$pos=0
function Draw{
  Clear-Host; Status
  C "`nUse ↑ ↓  |  A/Enter to confirm`n" DarkGray
  for($j=0;$j -lt $menu.Count;$j++){
    if($j -eq $pos){
      Write-Host "> $($menu[$j])" -ForegroundColor Black -BackgroundColor Yellow
    }else{
      Write-Host "  $($menu[$j])"
    }
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
        0{ Status; Pause }
        1{ DisableModern; Pause }
        2{ EnableHib;     Pause }
        3{ SetPowerBtn;   Pause }
        4{ DisableWakeInt;Pause }
        5{ break }
      }
    }
  }
}
