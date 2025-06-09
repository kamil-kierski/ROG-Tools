<#  ROG Ally Sleep Doctor  –  PS 5.1 SAFE
    • Main menu: Arrow keys + A/Enter to select
    • Wake-devices section: Arrow keys + A/Enter to toggle, B/Backspace to go back
    • Debug-log shows the last 5 entries
    • No full Clear-Host: uses cursor positioning to prevent flickering
#>

### --- Elevate & EP bypass ---
if (-not ([Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $script_url = 'https://raw.githubusercontent.com/kamil-kierski/ROG-Tools/master/SleepDoctor.ps1'
    $command = "Set-ExecutionPolicy -Scope Process Bypass -Force; iwr -UseBasicParsing {0} | iex" -f $script_url
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -Command `"$command`""
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
function HibOn    { (Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -EA 0) -eq 1 }
function WakeList { powercfg -devicequery wake_armed }
function LastWake { try { (powercfg /lastwake) -join ' ' } catch { 'N/A' } }

$global:LOG = @()
function Log($msg){
    $global:LOG += ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg)
    if($LOG.Count -gt 5){ $global:LOG = $LOG[-5..-1] }
}

function Invoke-PoshCommand {
    param($command)
    $output = & $command 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errmsg = ($output | Out-String).Trim()
        Log "ERROR: $errmsg"
        return $false
    }
    return $true
}

### ----- fix actions -----
function DisableModern { if(Invoke-PoshCommand {powercfg -change -standby-timeout-ac 0; powercfg -change -standby-timeout-dc 0}) { Log 'Modern Standby disabled (timeouts set to 0)'; Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; Log 'Modern Standby disabled (registry)' } }
function EnableHib     { if(Invoke-PoshCommand {powercfg /hibernate on}) { Log 'Hibernate enabled' } }
function SetPowerBtn   { if(Invoke-PoshCommand {powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT}) { Log 'Power-button -> Hibernate' } }

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

function DrawMenu([int]$sel, [string[]]$menu){
    $menuTop = 10
    $menuBottom = $menuTop + $menu.Count
    [Console]::SetCursorPosition(0, $menuTop)
    ClearZone $menuTop $menuBottom
    [Console]::SetCursorPosition(0, $menuTop)

    C "Use ↑↓, A/Enter=select, B/Esc=back/exit" DarkGray; NewLine
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
    $list = powercfg -devicequery wake_programmable
    if(-not $list){ Log 'No wake-programmable devices.'; return }
    $idx = 0
    # Reserve space for menu (from row 10) and log (last 7 rows)
    $maxItems = $H - 10 - 7 - 2 # screen_height - menu_top - log_lines - buffer
    if ($maxItems -lt 1) { $maxItems = 1 }

    while($true){
        $armedList = powercfg -devicequery wake_armed
        [Console]::SetCursorPosition(0,10)
        ClearZone 10 ($H-8)

        [Console]::SetCursorPosition(0,10)
        C "Wake devices - A/Enter=toggle, B/Esc=back" DarkGray; NewLine

        $displayList = $list
        if ($list.Count -gt $maxItems) {
            $displayList = $list[0..($maxItems-1)]
        }

        for($i=0; $i -lt $displayList.Count; $i++){
            $isArmed = $armedList -contains $displayList[$i]
            $flag = if($isArmed){'[ON] '}else{'[OFF]'}
            
            if($i -eq $idx){
                Write-Host ("> $flag$($displayList[$i])".PadRight($W-1)) -ForegroundColor Black -BackgroundColor Yellow
            }else{
                Write-Host ("  $flag$($displayList[$i])".PadRight($W-1))
            }
        }
        if ($list.Count -gt $maxItems) {
            C '...list truncated (screen too small)' DarkGray
        }

        $maxIdx = $displayList.Count - 1
        
        $k = [Console]::ReadKey($true).Key
        $actionTaken = $false
        if($k -eq 'UpArrow'){ if($idx -gt 0){$idx--} }
        elseif($k -eq 'DownArrow'){ if($idx -lt $maxIdx){$idx++} }
        elseif($k -eq 'A' -or $k -eq 'Enter'){
            $dev = $displayList[$idx]
            if($armedList -contains $dev){
                if(Invoke-PoshCommand {powercfg -devicedisablewake "$dev"}){ Log "Disabled wake: $dev" }
            } else {
                if(Invoke-PoshCommand {powercfg -deviceenablewake "$dev"}){ Log "Enabled wake : $dev" }
            }
            $actionTaken = $true
        }
        elseif($k -eq 'B' -or $k -eq 'Backspace' -or $k -eq 'Escape'){
            return
        }
        
        if($actionTaken){
            $armedList = powercfg -devicequery wake_armed
        }
        DrawLog
    }
}

### ----- main loop -----
$sel=0
$menu = @(
  'Show status',
  'Disable Modern Standby',
  'Enable Hibernate',
  'Set Power-button -> Hibernate',
  'Manage wake devices',
  'EXIT'
)
$needsRedraw = $true
while($true){
    if($needsRedraw){
        DrawStatus; DrawMenu $sel $menu; DrawLog
        $needsRedraw = $false
    }

    $k = [Console]::ReadKey($true).Key
    $oldSel = $sel

    if($k -eq 'UpArrow'){ if($sel -gt 0){$sel--} }
    elseif($k -eq 'DownArrow'){ if($sel -lt ($menu.Count-1)){$sel++} }
    elseif($k -eq 'A' -or $k -eq 'Enter'){
        $actionTaken = $false
        switch($sel){
            0 { Log 'Status refreshed'; $actionTaken = $true }
            1 { if(DisableModern){ $actionTaken = $true } }
            2 { if(EnableHib){ $actionTaken = $true } }
            3 { if(SetPowerBtn){ $actionTaken = $true } }
            4 { WakeMenu; $actionTaken = $true } # WakeMenu is blocking, so redraw after
            5 { break }
        }
        if($sel -eq 5){ break }
        if($actionTaken){ $needsRedraw = $true }
    }
    elseif($k -eq 'B' -or $k -eq 'Backspace' -or $k -eq 'Escape'){
        break
    }

    if($oldSel -ne $sel){
        DrawMenu $sel $menu
    }
}
ClearZone 0 ($H-1)
C "Done." Green; NewLine

