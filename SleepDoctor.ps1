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
function DisableModern { Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' PlatformAoAcOverride 0 -Type DWord -Force; Log 'Modern Standby disabled'; return $true }
function EnableHib     { try { powercfg /hibernate on | Out-Null; Log 'Hibernate enabled'; return $true } catch { Log "ERROR: $($_.Exception.Message)"; return $false } }
function SetPowerBtn   { try { powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 3; powercfg -setactive SCHEME_CURRENT | Out-Null; Log 'Power-button -> Hibernate'; return $true } catch { Log "ERROR: $($_.Exception.Message)"; return $false } }
function Toggle-WakeDevice([string]$dev, [bool]$isArmed){
    $action = if($isArmed){"disable"}else{"enable"}
    try {
        powercfg -device${action}wake "$dev" | Out-Null
        Log "Device wake ${action}d: $dev"
    } catch {
        Log "ERROR: $($_.Exception.Message)"
    }
}

### ----- New Simplified UI Engine -----
$global:Status = @{}
function Update-Status{
    $global:Status.ModernOn = ModernOn
    $global:Status.HibOn = HibOn
    $global:Status.WakeList = WakeList
    $global:Status.LastWake = LastWake
    Log "Status updated"
}

function Draw-Screen([int]$sel, [string[]]$menu){
    Clear-Host
    $H = [Console]::WindowHeight
    $W = [Console]::WindowWidth

    # --- STATUS ---
    C "====  CURRENT STATUS  ====" Cyan; NewLine
    C "Modern Standby: "; C $(if($global:Status.ModernOn){'ENABLED'}else{'DISABLED'}) $(if($global:Status.ModernOn){'Red'}else{'Green'}); NewLine
    C "Hibernate      : "; C $(if($global:Status.HibOn){'ENABLED'}else{'DISABLED'}) $(if($global:Status.HibOn){'Green'}else{'Red'}); NewLine
    C "Wake devices   : $($global:Status.WakeList.Count)" $(if($global:Status.WakeList.Count){'Yellow'}else{'Green'}); NewLine
    C "Last wake      : $($global:Status.LastWake)" Gray; NewLine
    NewLine
    C "Recommendations:" Magenta; NewLine
    if($global:Status.ModernOn){ C " • Disable Modern Standby." Yellow; NewLine }
    if(-not $global:Status.HibOn){ C " • Enable Hibernate." Yellow; NewLine }
    if($global:Status.WakeList.Count){  C " • Disable wake devices." Yellow; NewLine }
    NewLine

    # --- MENU ---
    C "Use ↑↓, A/Enter=select, B/Esc=back/exit" DarkGray; NewLine
    for($i=0;$i -lt $menu.Count;$i++){
        if($i -eq $sel){ Write-Host ("> $($menu[$i])".PadRight($W-1)) -ForegroundColor Black -BackgroundColor Yellow }
        else { Write-Host ("  $($menu[$i])".PadRight($W-1)) }
    }
    
    # --- LOG ---
    $logStartY = if($H - 8 -lt 20){20}else{$H - 8}
    [Console]::SetCursorPosition(0, $logStartY)
    C "====  DEBUG LOG  ====" DarkGray; NewLine
    foreach($l in $global:LOG){ Write-Host $l }
}

function Manage-WakeDevices{
    $allDevices = powercfg -devicequery wake_programmable
    if(-not $allDevices){ Log 'No wake-programmable devices.'; return }
    
    $idx = 0
    while($true){
        Clear-Host
        C "==== MANAGE WAKE DEVICES ====" Cyan; NewLine
        C "Use ↑↓, A/Enter=toggle, B/Esc=back" DarkGray; NewLine
        $armedDevices = WakeList
        for($i=0; $i -lt $allDevices.Count; $i++){
            $isArmed = $armedDevices -contains $allDevices[$i]
            $flag = if($isArmed){'[ON] '}else{'[OFF]'}
            $line = "  $flag$($allDevices[$i])"
            if($i -eq $idx){ Write-Host (">" + $line.SubString(1)) -ForegroundColor Black -BackgroundColor Yellow }
            else { Write-Host $line }
        }

        $k = [Console]::ReadKey($true).Key
        switch($k){
            'UpArrow'   { if($idx -gt 0){$idx--} }
            'DownArrow' { if($idx -lt ($allDevices.Count - 1)){$idx++} }
            'A'; 'Enter' { 
                Toggle-WakeDevice -dev $allDevices[$idx] -isArmed ($armedDevices -contains $allDevices[$idx])
            }
            'B'; 'Backspace'; 'Escape' { return }
        }
    }
}

### ----- MAIN LOOP -----
$sel=0
$menu = @(
  'Refresh Status',
  'Disable Modern Standby',
  'Enable Hibernate',
  'Set Power-button -> Hibernate',
  'Manage wake devices',
  'EXIT'
)

Update-Status
while($true){
    Draw-Screen $sel $menu
    $k = [Console]::ReadKey($true).Key

    switch($k){
        'UpArrow'   { if($sel -gt 0){ $sel-- } }
        'DownArrow' { if($sel -lt ($menu.Count-1)){ $sel++ } }
        'A'; 'Enter' {
            $refresh = $false
            switch($sel){
                0 { $refresh = $true }
                1 { if(DisableModern){ $refresh = $true } }
                2 { if(EnableHib){ $refresh = $true } }
                3 { if(SetPowerBtn){ $refresh = $true } }
                4 { Manage-WakeDevices; $refresh = $true }
                5 { break }
            }
            if($sel -eq 5){ break }
            if($refresh){ Update-Status }
        }
        'B'; 'Backspace'; 'Escape' { break }
    }
}

Clear-Host
C "Done." Green; NewLine

