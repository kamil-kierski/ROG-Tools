<#  ROG Ally Sleep Doctor 1.1  –  no fancy chars  #>

if (-not ([Security.Principal.WindowsPrincipal]
          [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
          [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-ExecutionPolicy Bypass -Scope Process -Force

function C([string]$t,[string]$c){Write-Host $t -ForegroundColor $c}

function GetModern { $k=Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Power -Name PlatformAoAcOverride -EA SilentlyContinue; if(!$k){$true}else{($k.PlatformAoAcOverride -ne 0)} }
function GetHibernate { (powercfg /a | Select-String Hibernate) -like '*available*' }
function GetWake { powercfg -devicequery wake_armed }
function GetLastWake { try{(powercfg /lastwake)-join' '}catch{'N/A'} }

function ShowStatus {
    $ms=GetModern; $hb=GetHibernate; $wk=GetWake; $lw=GetLastWake
    C "`n=== STATUS ===" Cyan
    C ("Modern Standby: "+($ms?'ON':'OFF')) ($ms?'Red':'Green')
    C ("Hibernate     : "+($hb?'ON':'OFF'))  ($hb?'Green':'Red')
    C ("Wake devices  : $($wk.Count)") ($wk.Count?'Yellow':'Green')
    C ("Last wake     : $lw") Gray
    C "===============`n" Cyan
}

function DisableModern { Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Power PlatformAoAcOverride 0 -Type DWord -Force; C 'Modern Standby OFF. Reboot later.' Green }
function EnableHibernate { powercfg /hibernate on | out-null; C 'Hibernate ON.' Green }
function SetPowerBtn { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT; C 'Power button -> hibernate.' Green }
function DisableWakeInteractive {
 $d=GetWake; if(!$d){C 'no wake devices' Green;return}
 $i=1;$map=@{};foreach($v in $d){C "[$i] $v" Yellow;$map[$i]=$v;$i++}
 $c=Read-Host 'Pick number or * for all'; if($c -eq '*'){foreach($v in $d){powercfg -devicedisablewake "$v"};C 'all disabled' Green}
 elseif([int]::TryParse($c,[ref]$n) -and $map[$n]){powercfg -devicedisablewake "$($map[$n])";C 'disabled.' Green}
}

$menu=@(
 'Show status',
 'Disable Modern Standby',
 'Enable Hibernate',
 'Set Power button → Hibernate',
 'Disable wake devices',
 'EXIT'
)
$idx=0
while($true){
 Clear-Host; ShowStatus
 C "Use UP/DOWN and Enter`n" DarkGray
 for($j=0;$j -lt $menu.Count;$j++){
   if($j -eq $idx){Write-Host "> $($menu[$j])" -BackgroundColor Yellow -ForegroundColor Black}
   else{Write-Host "  $($menu[$j])"}
 }
 $k=[console]::ReadKey($true)
 switch($k.Key){
   'UpArrow' {$idx=[Math]::Max(0,$idx-1)}
   'DownArrow'{$idx=[Math]::Min($menu.Count-1,$idx+1)}
   'Enter' {
      switch($idx){
        0{ShowStatus;Pause}
        1{DisableModern;Pause}
        2{EnableHibernate;Pause}
        3{SetPowerBtn;Pause}
        4{DisableWakeInteractive;Pause}
        5{break}
      }
   }
 }
}
