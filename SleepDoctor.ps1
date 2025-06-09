<#  ROG Ally Sleep Doctor  –  v1.0
    • Live status (Modern Standby / Hibernate / wake devices / last wake)
    • Arrow-key menu  (↑ ↓ Enter)
    • Fixes:  ▸Disable Modern Standby ▸Enable Hibernate
              ▸Set Power-button → Hibernate ▸Disable wake devices
    • Auto-elevate when called via “iwr | iex”
#>

#region Helpers
function Color($txt,$c){Write-Host $txt -ForegroundColor $c}
function Is-Admin {
    (New-Object Security.Principal.WindowsPrincipal `
      ([Security.Principal.WindowsIdentity]::GetCurrent()) `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Ensure-Admin {
    if(-not (Is-Admin)) {
        Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-Admin
Set-ExecutionPolicy Bypass -Scope Process -Force
#endregion

#region Status getters
function Modern-On { $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
                           -Name PlatformAoAcOverride -EA SilentlyContinue
                    if(!$k){return $true}; return ($k.PlatformAoAcOverride -ne 0) }
function Hib-On    { (powercfg /a | Select-String 'Hibernate') -like '*available*' }
function Wake-List { powercfg -devicequery wake_armed }
function LastWake  { try{(powercfg /lastwake) -join ' '}catch{'N/A'} }
#endregion

#region Fix actions
function Disable-Modern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
                           PlatformAoAcOverride 0 -Type DWord -Force
                           Color 'Modern Standby disabled  (S3 sleep enabled).' Green }
function Enable-Hib     { powercfg /hibernate on | Out-Null; Color 'Hibernate enabled.' Green }
function Set-PowerBtn   { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3
                          powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3
                          powercfg -setactive SCHEME_CURRENT
                          Color 'Power button now triggers Hibernate.' Green }
function Disable-WakeInt{
    $d=Wake-List; if(!$d){Color 'No wake devices.' Green; return}
    $i=1; $map=@{}; foreach($dev in $d){Color "[$i] $dev" Yellow; $map[$i]=$dev; $i++}
    $ch=Read-Host 'Select number or * for all'; if($ch -eq '*'){
        foreach($dev in $d){powercfg -devicedisablewake "$dev"}; Color 'All wake devices disabled.' Green
    } elseif([int]::TryParse($ch,[ref]$n) -and $map[$n]) {
        powercfg -devicedisablewake "$($map[$n])"; Color "$($map[$n]) disabled." Green
    }
}
#endregion

function Show-Status {
    $ms=Modern-On; $hib=Hib-On; $w=Wake-List; $lw=LastWake
    Color "`n====  CURRENT STATUS  ====" Cyan
    Color ("Modern Standby: "+($ms?'ENABLED':'DISABLED')) ($ms?'Red':'Green')
    Color ("Hibernate    : "+($hib?'ENABLED':'DISABLED')) ($hib?'Green':'Red')
    Color ("Wake devices : $($w.Count)") ($w.Count?'Yellow':'Green')
    Color ("Last wake    : $lw") Gray
    Color "`nRecommendations:" Magenta
    if($ms){Color ' • Disable Modern Standby (will enable S3).' Yellow}
    if(-not $hib){Color ' • Enable Hibernate.' Yellow}
    if($w.Count){Color ' • Disable wake devices.' Yellow}
    Color '============================' Cyan
}

function Draw-Menu([int]$sel){
    Clear-Host; Show-Status
    Color "`nUse ↑ ↓ arrows  |  Enter = run`n" DarkGray
    $menu = @(
      'Show status',
      'Disable Modern Standby',
      'Enable Hibernate',
      'Set Power-button → Hibernate',
      'Disable wake devices',
      'EXIT'
    )
    for($i=0;$i -lt $menu.Count;$i++){
        if($i -eq $sel){
            Write-Host "> $($menu[$i])" -ForegroundColor Black -BackgroundColor Yellow
        }else{
            Write-Host "  $($menu[$i])"
        }
    }
}

# main loop
$idx=0
while($true){
    Draw-Menu $idx
    switch((Read-Key).Key){
        'UpArrow'   { if($idx) { $idx-- } }
        'DownArrow' { if($idx -lt 5) { $idx++ } }
        'Enter' {
            switch($idx){
              0 { Show-Status; Pause }
              1 { Disable-Modern; Pause }
              2 { Enable-Hib;     Pause }
              3 { Set-PowerBtn;   Pause }
              4 { Disable-WakeInt;Pause }
              5 { break }
            }
        }
    }
}
