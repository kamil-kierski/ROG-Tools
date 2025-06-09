<#  ROG Ally Sleep Doctor  –  PS 5.1 SAFE
    • Główne menu strzałki + A/Enter
    • Sekcja Wake-devices: strzałki + A/Enter, Disable = X
    • Debug-log wyświetla ostatnie 5 wpisów
    • Brak pełnego Clear-Host: nadpisywanie kursor-pos, zero migania
#>

### --- Elevate & EP bypass ---
if (-not ([Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-ExecutionPolicy Bypass -Scope Process -Force

### ----- helpers -----
function C($t,$col){
    try{ Write-Host $t -ForegroundColor ([ConsoleColor]$col) -NoNewline }
    catch{ Write-Host $t -NoNewline }
}

function NewLine { [Console]::WriteLine() }

function ModernOn { $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name PlatformAoAcOverride -EA 0; if(!$k){$true}else{($k.PlatformAoAcOverride -ne 0)} }
function HibOn    { (powercfg /a | Select-String 'Hibernate') -like '*available*' }
function WakeList { powercfg -devicequery wake_armed }
function LastWake { try { (powercfg /lastwake) -join ' ' } catch { 'N/A' } }

$global:LOG = @()
function Log($msg){
    $global:LOG += ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg)
    if($LOG.Count -gt 5){ $global:LOG = $LOG[-5..-1] }
}

### ----- fix actions -----
function DisableModern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; Log 'Modern Standby disabled'; }
function EnableHib     { powercfg /hibernate on | Out-Null; Log 'Hibernate enabled'; }
function SetPowerBtn   { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT; Log 'Power-button → Hibernate'; }
function ToggleWakeDevice([string]$d){
    if((powercfg -devicequery wake_armed) -contains $d){
        powercfg -devicedisablewake "$d"; Log "Disabled wake: $d"
    } else {
        powercfg -deviceenablewake  "$d"; Log "Enabled wake : $d"
    }
}

### ----- drawing helpers (minimal flicker) -----
$H = [Console]::WindowHeight
$W = [Console]::WindowWidth
function ClearZone([int]$yStart,[int]$yEnd){
    for($y=$yStart;$y -le $yEnd;$y++){
        [Console]::SetCursorPosition(0,$y)
        Write-Host (" " * ($W-1))
    }
}

function DrawStatus{
    [Console]::SetCursorPosition(0,0)
    ClearZone 0 9
    $ms = ModernOn; $hib = HibOn; $w = WakeList; $lw = LastWake
    C "====  CURRENT STATUS  ====" Cyan; NewLine
    C "Modern Standby: "; C $(if($ms){'ENABLED'}else{'DISABLED'}) $(if($ms){'Red'}else{'Green'}); NewLine
    C "Hibernate      : "; C $(if($hib){'ENABLED'}else{'DISABLED'}) $(if($hib){'Green'}else{'Red'}); NewLine
    C "Wake devices   : $($w.Count)" $(if($w.Count){'Yellow'}else{'Green'}); NewLine
    C "Last wake      : $lw" Gray; NewLine

    C "Recommendations:" Magenta; NewLine
    if($ms){  C " • Disable Modern Standby." Yellow; NewLine }
    if(-not $hib){ C " • Enable Hibernate." Yellow; NewLine }
    if($w.Count){  C " • Disable wake devices." Yellow; NewLine }
}

function DrawMenu([int]$sel){
    [Console]::SetCursorPosition(0,10)
    ClearZone 10 16
    $menu = @(
      'Show status',
      'Disable Modern Standby',
      'Enable Hibernate',
      'Set Power-button → Hibernate',
      'Manage wake devices',
      'EXIT'
    )
    C "Use ↑ ↓   A/Enter = run   B/Back = main menu" DarkGray; NewLine
    for($i=0;$i -lt $menu.Count;$i++){
        if($i -eq $sel){
            Write-Host ("> $($menu[$i])".PadRight($W-1)) -ForegroundColor Black -BackgroundColor Yellow
        } else {
            Write-Host ("  $($menu[$i])".PadRight($W-1))
        }
    }
}

function DrawLog{
    $start = $H-7
    ClearZone $start ($H-2)
    [Console]::SetCursorPosition(0,$start)
    C "Debug log (last 5):" DarkGray; NewLine
    foreach($l in $LOG){ Write-Host $l }
}

### ----- wake-device manager (arrow list) -----
function WakeMenu{
    $list = WakeList
    if(!$list){ Log 'No wake devices'; return }
    $idx = 0
    while($true){
        [Console]::SetCursorPosition(0,10)
        ClearZone 10 16
        C "Wake devices – A=toggle  B=back" DarkGray; NewLine
        for($i=0;$i -lt $list.Count;$i++){
            $flag = (WakeList) -contains $list[$i] ? '[ON] ' : '[OFF]'
            if($i -eq $idx){
                Write-Host ("> $flag$list[$i]".PadRight($W-1)) -ForegroundColor Black -BackgroundColor Yellow
            }else{
                Write-Host ("  $flag$list[$i]".PadRight($W-1))
            }
        }
        $k = [Console]::ReadKey($true).Key
        switch($k){
            'UpArrow'   { if($idx){$idx--} }
            'DownArrow' { if($idx -lt $list.Count-1){$idx++} }
            'Enter'     { ToggleWakeDevice $list[$idx] }
            'Escape'    { return }
            'B','Backspace' { return }
        }
        DrawLog
    }
}

### ----- main loop -----
$sel=0
while($true){
    DrawStatus; DrawMenu $sel; DrawLog
    $k = [Console]::ReadKey($true).Key
    switch($k){
        'UpArrow'   { if($sel){$sel--} }
        'DownArrow' { if($sel -lt 5){$sel++} }
        'Enter' {
            switch($sel){
                0 { Log 'Status refreshed' }
                1 { DisableModern }
                2 { EnableHib }
                3 { SetPowerBtn }
                4 { WakeMenu }
                5 { break }
            }
        }
    }
}
ClearZone 0 ($H-1)
C "Done." Green; NewLine
