<#
    ROG Ally Sleep Doctor - Enhanced Version (PowerShell 3.0+ Compatible)
    Manages power settings, hibernation, and wake devices for optimal sleep performance
    
    Controls:
    • Arrow Keys: Navigate menu
    • Enter/Space: Select option
    • Escape/Q: Exit
    • R: Refresh status
#>

# Ensure we're running as administrator
if (-not ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        $scriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
        $MyInvocation.MyCommand.ScriptContents | Out-File -FilePath $scriptPath -Encoding UTF8
    }
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Global variables
$Global:ActivityLog = New-Object System.Collections.Generic.Queue[string]
$Global:MaxLogEntries = 10
$Global:LastRefresh = Get-Date

# Color scheme
$Colors = @{
    Header     = 'Cyan'
    Success    = 'Green'
    Warning    = 'Yellow'
    Error      = 'Red'
    Info       = 'White'
    Muted      = 'DarkGray'
    Highlight  = 'Magenta'
    Selected   = @{ Foreground = 'Black'; Background = 'Yellow' }
}

# Console utilities
function Write-ColorText {
    param(
        [string]$Text,
        [string]$Color = 'White',
        [switch]$NoNewline
    )
    
    try {
        if ($NoNewline) {
            Write-Host $Text -ForegroundColor $Color -NoNewline
        } else {
            Write-Host $Text -ForegroundColor $Color
        }
    } catch {
        if ($NoNewline) {
            Write-Host $Text -NoNewline
        } else {
            Write-Host $Text
        }
    }
}

function Add-ActivityLog {
    param([string]$Message)
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    $Global:ActivityLog.Enqueue($logEntry)
    
    while ($Global:ActivityLog.Count -gt $Global:MaxLogEntries) {
        [void]$Global:ActivityLog.Dequeue()
    }
}

function Clear-ConsoleArea {
    param(
        [int]$StartLine,
        [int]$EndLine
    )
    
    $width = [Console]::WindowWidth
    for ($line = $StartLine; $line -le $EndLine; $line++) {
        [Console]::SetCursorPosition(0, $line)
        Write-Host (" " * ($width - 1)) -NoNewline
    }
}

# System status functions
function Get-ModernStandbyStatus {
    try {
        $regValue = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'PlatformAoAcOverride' -ErrorAction SilentlyContinue
        if (-not $regValue) {
            return $true  # Modern Standby enabled by default
        }
        return $regValue.PlatformAoAcOverride -ne 0
    } catch {
        return $false
    }
}

function Get-HibernationStatus {
    try {
        $hibernateEnabled = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction SilentlyContinue
        if ($hibernateEnabled -and $hibernateEnabled.HibernateEnabled) {
            return $hibernateEnabled.HibernateEnabled -eq 1
        }
        return $false
    } catch {
        return $false
    }
}

function Get-WakeDevices {
    try {
        $devices = powercfg -devicequery wake_armed 2>$null
        if ($devices) {
            return @($devices | Where-Object { $_ -and $_.Trim() })
        }
        return @()
    } catch {
        return @()
    }
}

function Get-WakeProgrammableDevices {
    try {
        $devices = powercfg -devicequery wake_programmable 2>$null
        if ($devices) {
            return @($devices | Where-Object { $_ -and $_.Trim() })
        }
        return @()
    } catch {
        return @()
    }
}

function Get-LastWakeSource {
    try {
        $wakeInfo = powercfg /lastwake 2>$null
        if ($wakeInfo) {
            return ($wakeInfo -join ' ').Trim()
        }
        return "Unknown"
    } catch {
        return "Unable to determine"
    }
}

function Get-PowerButtonAction {
    try {
        $queryResult = powercfg -q SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 2>$null
        if (-not $queryResult) {
            return @{ AC = "Unknown"; DC = "Unknown" }
        }
        
        $acAction = ""
        $dcAction = ""
        
        foreach ($line in $queryResult) {
            if ($line -match "Current AC Power Setting Index:\s*(.+)") {
                $acAction = $matches[1].Trim()
            }
            if ($line -match "Current DC Power Setting Index:\s*(.+)") {
                $dcAction = $matches[1].Trim()
            }
        }
        
        $actionMap = @{
            '0x00000000' = 'Do Nothing'
            '0x00000001' = 'Sleep'
            '0x00000002' = 'Hibernate'
            '0x00000003' = 'Shut Down'
        }
        
        $acActionText = if ($actionMap.ContainsKey($acAction)) { $actionMap[$acAction] } else { "Unknown ($acAction)" }
        $dcActionText = if ($actionMap.ContainsKey($dcAction)) { $actionMap[$dcAction] } else { "Unknown ($dcAction)" }
        
        return @{
            AC = $acActionText
            DC = $dcActionText
        }
    } catch {
        return @{ AC = "Unknown"; DC = "Unknown" }
    }
}

# System modification functions
function Disable-ModernStandby {
    try {
        # Set standby timeouts to 0
        $result1 = powercfg -change -standby-timeout-ac 0 2>$null
        $result2 = powercfg -change -standby-timeout-dc 0 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Add-ActivityLog "Modern Standby timeouts disabled"
            
            # Set registry value
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'PlatformAoAcOverride' -Value 0 -Type DWord -Force
            Add-ActivityLog "Modern Standby registry setting updated"
            return $true
        } else {
            Add-ActivityLog "Failed to disable Modern Standby timeouts"
            return $false
        }
    } catch {
        Add-ActivityLog "Error disabling Modern Standby: $($_.Exception.Message)"
        return $false
    }
}

function Enable-Hibernation {
    try {
        $result = powercfg /hibernate on 2>$null
        if ($LASTEXITCODE -eq 0) {
            Add-ActivityLog "Hibernation enabled successfully"
            return $true
        } else {
            Add-ActivityLog "Failed to enable hibernation"
            return $false
        }
    } catch {
        Add-ActivityLog "Error enabling hibernation: $($_.Exception.Message)"
        return $false
    }
}

function Set-PowerButtonToHibernate {
    try {
        # Set power button action to hibernate (value 2) for both AC and DC
        $result1 = powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 2 2>$null
        $result2 = powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS POWERBUTTONACTION 2 2>$null
        $result3 = powercfg -setactive SCHEME_CURRENT 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Add-ActivityLog "Power button configured for hibernation"
            return $true
        } else {
            Add-ActivityLog "Failed to configure power button"
            return $false
        }
    } catch {
        Add-ActivityLog "Error configuring power button: $($_.Exception.Message)"
        return $false
    }
}

# Display functions
function Show-Header {
    [Console]::SetCursorPosition(0, 0)
    Clear-ConsoleArea 0 2
    [Console]::SetCursorPosition(0, 0)
    
    Write-ColorText "================================================================================" $Colors.Header
    Write-ColorText "                          ROG Ally Sleep Doctor                              " $Colors.Header
    Write-ColorText "================================================================================" $Colors.Header
}

function Show-SystemStatus {
    [Console]::SetCursorPosition(0, 4)
    Clear-ConsoleArea 4 15
    [Console]::SetCursorPosition(0, 4)
    
    Write-ColorText "CURRENT SYSTEM STATUS" $Colors.Header
    Write-ColorText "--------------------------------------------------------------------------------" $Colors.Muted
    
    # Get current status
    $modernStandby = Get-ModernStandbyStatus
    $hibernation = Get-HibernationStatus
    $wakeDevices = Get-WakeDevices
    $lastWake = Get-LastWakeSource
    $powerButton = Get-PowerButtonAction
    
    # Modern Standby Status
    Write-ColorText "Modern Standby    : " $Colors.Info -NoNewline
    if ($modernStandby) {
        Write-ColorText "ENABLED " $Colors.Error -NoNewline
        Write-ColorText "(WARNING: May cause battery drain)" $Colors.Warning
    } else {
        Write-ColorText "DISABLED " $Colors.Success -NoNewline
        Write-ColorText "(OK: Recommended)" $Colors.Success
    }
    
    # Hibernation Status
    Write-ColorText "Hibernation       : " $Colors.Info -NoNewline
    if ($hibernation) {
        Write-ColorText "ENABLED " $Colors.Success -NoNewline
        Write-ColorText "(OK: Good for battery life)" $Colors.Success
    } else {
        Write-ColorText "DISABLED " $Colors.Error -NoNewline
        Write-ColorText "(WARNING: Enable for better battery)" $Colors.Warning
    }
    
    # Wake Devices
    Write-ColorText "Wake Devices      : " $Colors.Info -NoNewline
    if ($wakeDevices.Count -gt 0) {
        Write-ColorText "$($wakeDevices.Count) active " $Colors.Warning -NoNewline
        Write-ColorText "(WARNING: May cause unwanted wake-ups)" $Colors.Warning
    } else {
        Write-ColorText "None active " $Colors.Success -NoNewline
        Write-ColorText "(OK: Prevents unwanted wake-ups)" $Colors.Success
    }
    
    # Power Button Action
    Write-ColorText "Power Button (AC) : " $Colors.Info -NoNewline
    if ($powerButton.AC -eq "Hibernate") {
        Write-ColorText $powerButton.AC $Colors.Success
    } else {
        Write-ColorText $powerButton.AC $Colors.Warning
    }
    Write-ColorText "Power Button (DC) : " $Colors.Info -NoNewline
    if ($powerButton.DC -eq "Hibernate") {
        Write-ColorText $powerButton.DC $Colors.Success
    } else {
        Write-ColorText $powerButton.DC $Colors.Warning
    }
    
    # Last Wake Source
    Write-ColorText "Last Wake Source  : " $Colors.Info -NoNewline
    Write-ColorText $lastWake $Colors.Muted
    
    # Overall Health Score
    $score = 0
    if (-not $modernStandby) { $score += 25 }
    if ($hibernation) { $score += 25 }
    if ($wakeDevices.Count -eq 0) { $score += 25 }
    if ($powerButton.AC -eq "Hibernate" -and $powerButton.DC -eq "Hibernate") { $score += 25 }
    
    Write-ColorText ""
    Write-ColorText "Sleep Health Score: " $Colors.Info -NoNewline
    if ($score -ge 75) {
        $scoreColor = $Colors.Success
        $healthText = "Excellent"
    } elseif ($score -ge 50) {
        $scoreColor = $Colors.Warning
        $healthText = "Good"
    } elseif ($score -ge 25) {
        $scoreColor = $Colors.Warning
        $healthText = "Needs Improvement"
    } else {
        $scoreColor = $Colors.Error
        $healthText = "Poor"
    }
    
    Write-ColorText "$score/100 " $scoreColor -NoNewline
    Write-ColorText "($healthText)" $scoreColor
    
    $Global:LastRefresh = Get-Date
}

function Show-Menu {
    param(
        [string[]]$MenuItems,
        [int]$SelectedIndex
    )
    
    [Console]::SetCursorPosition(0, 17)
    Clear-ConsoleArea 17 25
    [Console]::SetCursorPosition(0, 17)
    
    Write-ColorText "AVAILABLE ACTIONS" $Colors.Header
    Write-ColorText "--------------------------------------------------------------------------------" $Colors.Muted
    
    for ($i = 0; $i -lt $MenuItems.Count; $i++) {
        if ($i -eq $SelectedIndex) {
            Write-Host ("  > " + $MenuItems[$i]).PadRight([Console]::WindowWidth - 1) -ForegroundColor $Colors.Selected.Foreground -BackgroundColor $Colors.Selected.Background
        } else {
            Write-ColorText "    $($MenuItems[$i])" $Colors.Info
        }
    }
    
    Write-ColorText ""
    Write-ColorText "Controls: Up/Down Navigate • Enter/Space Select • R Refresh • Q/Esc Exit" $Colors.Muted
}

function Show-ActivityLog {
    $logStartLine = [Console]::WindowHeight - 8
    [Console]::SetCursorPosition(0, $logStartLine)
    Clear-ConsoleArea $logStartLine ([Console]::WindowHeight - 1)
    [Console]::SetCursorPosition(0, $logStartLine)
    
    Write-ColorText "ACTIVITY LOG" $Colors.Header
    Write-ColorText "--------------------------------------------------------------------------------" $Colors.Muted
    
    if ($Global:ActivityLog.Count -eq 0) {
        Write-ColorText "No recent activity" $Colors.Muted
    } else {
        $logArray = $Global:ActivityLog.ToArray()
        $displayCount = [Math]::Min(5, $logArray.Length)
        for ($i = $logArray.Length - $displayCount; $i -lt $logArray.Length; $i++) {
            Write-ColorText $logArray[$i] $Colors.Muted
        }
    }
}

function Show-WakeDeviceManager {
    $devices = Get-WakeProgrammableDevices
    $armedDevices = Get-WakeDevices
    
    if ($devices.Count -eq 0) {
        Add-ActivityLog "No wake-programmable devices found"
        return
    }
    
    $selectedIndex = 0
    $maxDisplayItems = [Console]::WindowHeight - 20
    
    while ($true) {
        # Refresh armed devices list
        $armedDevices = Get-WakeDevices
        
        [Console]::SetCursorPosition(0, 17)
        Clear-ConsoleArea 17 ([Console]::WindowHeight - 8)
        [Console]::SetCursorPosition(0, 17)
        
        Write-ColorText "WAKE DEVICE MANAGER" $Colors.Header
        Write-ColorText "--------------------------------------------------------------------------------" $Colors.Muted
        Write-ColorText "Select devices to toggle their wake capability" $Colors.Info
        Write-ColorText ""
        
        $displayDevices = if ($devices.Count -gt $maxDisplayItems) { 
            $devices[0..($maxDisplayItems-1)] 
        } else { 
            $devices 
        }
        
        for ($i = 0; $i -lt $displayDevices.Count; $i++) {
            $device = $displayDevices[$i]
            $isArmed = $armedDevices -contains $device
            $status = if ($isArmed) { "[ENABLED]" } else { "[DISABLED]" }
            $statusColor = if ($isArmed) { $Colors.Warning } else { $Colors.Success }
            
            if ($i -eq $selectedIndex) {
                Write-Host ("  > $status $device").PadRight([Console]::WindowWidth - 1) -ForegroundColor $Colors.Selected.Foreground -BackgroundColor $Colors.Selected.Background
            } else {
                Write-ColorText "    " $Colors.Info -NoNewline
                Write-ColorText $status $statusColor -NoNewline
                Write-ColorText " $device" $Colors.Info
            }
        }
        
        if ($devices.Count -gt $maxDisplayItems) {
            Write-ColorText "... and $($devices.Count - $maxDisplayItems) more devices (screen too small)" $Colors.Muted
        }
        
        Write-ColorText ""
        Write-ColorText "Controls: Up/Down Navigate • Enter/Space Toggle • Esc/B Back" $Colors.Muted
        
        Show-ActivityLog
        
        $key = [Console]::ReadKey($true).Key
        
        switch ($key) {
            'UpArrow' {
                if ($selectedIndex -gt 0) { $selectedIndex-- }
            }
            'DownArrow' {
                if ($selectedIndex -lt ($displayDevices.Count - 1)) { $selectedIndex++ }
            }
            'Enter' {
                $device = $displayDevices[$selectedIndex]
                $isCurrentlyArmed = $armedDevices -contains $device
                
                try {
                    if ($isCurrentlyArmed) {
                        $result = powercfg -devicedisablewake "$device" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Add-ActivityLog "Disabled wake for: $($device.Split([Environment]::NewLine)[0])"
                        } else {
                            Add-ActivityLog "Failed to disable wake for device"
                        }
                    } else {
                        $result = powercfg -deviceenablewake "$device" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Add-ActivityLog "Enabled wake for: $($device.Split([Environment]::NewLine)[0])"
                        } else {
                            Add-ActivityLog "Failed to enable wake for device"
                        }
                    }
                } catch {
                    Add-ActivityLog "Error toggling wake device: $($_.Exception.Message)"
                }
            }
            'Spacebar' {
                $device = $displayDevices[$selectedIndex]
                $isCurrentlyArmed = $armedDevices -contains $device
                
                try {
                    if ($isCurrentlyArmed) {
                        $result = powercfg -devicedisablewake "$device" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Add-ActivityLog "Disabled wake for: $($device.Split([Environment]::NewLine)[0])"
                        } else {
                            Add-ActivityLog "Failed to disable wake for device"
                        }
                    } else {
                        $result = powercfg -deviceenablewake "$device" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Add-ActivityLog "Enabled wake for: $($device.Split([Environment]::NewLine)[0])"
                        } else {
                            Add-ActivityLog "Failed to enable wake for device"
                        }
                    }
                } catch {
                    Add-ActivityLog "Error toggling wake device: $($_.Exception.Message)"
                }
            }
            'Escape' {
                return
            }
            'B' {
                return
            }
        }
    }
}

function Invoke-AutoFix {
    Write-ColorText ""
    Write-ColorText "Running automatic optimization..." $Colors.Info
    
    $changes = 0
    
    # Check and fix Modern Standby
    if (Get-ModernStandbyStatus) {
        if (Disable-ModernStandby) {
            $changes++
        }
    }
    
    # Check and fix Hibernation
    if (-not (Get-HibernationStatus)) {
        if (Enable-Hibernation) {
            $changes++
        }
    }
    
    # Check and fix Power Button
    $powerButton = Get-PowerButtonAction
    if ($powerButton.AC -ne "Hibernate" -or $powerButton.DC -ne "Hibernate") {
        if (Set-PowerButtonToHibernate) {
            $changes++
        }
    }
    
    # Optionally disable all wake devices
    $wakeDevices = Get-WakeDevices
    if ($wakeDevices.Count -gt 0) {
        Add-ActivityLog "Found $($wakeDevices.Count) wake-enabled devices"
        Add-ActivityLog "Use 'Manage Wake Devices' to disable them individually"
    }
    
    if ($changes -gt 0) {
        Add-ActivityLog "Auto-fix completed with $changes changes"
    } else {
        Add-ActivityLog "No changes needed - system already optimized"
    }
}

# Main program
function Start-SleepDoctor {
    # Initialize console
    [Console]::CursorVisible = $false
    Clear-Host
    
    Add-ActivityLog "ROG Ally Sleep Doctor started"
    
    $menuItems = @(
        "Refresh Status",
        "Auto-Fix All Issues",
        "Disable Modern Standby",
        "Enable Hibernation", 
        "Set Power Button -> Hibernate",
        "Manage Wake Devices",
        "Exit"
    )
    
    $selectedIndex = 0
    $needsRedraw = $true
    
    while ($true) {
        if ($needsRedraw) {
            Show-Header
            Show-SystemStatus
            Show-Menu $menuItems $selectedIndex
            Show-ActivityLog
            $needsRedraw = $false
        }
        
        $key = [Console]::ReadKey($true).Key
        
        switch ($key) {
            'UpArrow' {
                if ($selectedIndex -gt 0) {
                    $selectedIndex--
                    Show-Menu $menuItems $selectedIndex
                }
            }
            'DownArrow' {
                if ($selectedIndex -lt ($menuItems.Count - 1)) {
                    $selectedIndex++
                    Show-Menu $menuItems $selectedIndex
                }
            }
            'Enter' {
                switch ($selectedIndex) {
                    0 { # Refresh Status
                        Add-ActivityLog "Status refreshed"
                        $needsRedraw = $true
                    }
                    1 { # Auto-Fix
                        Invoke-AutoFix
                        $needsRedraw = $true
                    }
                    2 { # Disable Modern Standby
                        if (Get-ModernStandbyStatus) {
                            [void](Disable-ModernStandby)
                        } else {
                            Add-ActivityLog "Modern Standby is already disabled"
                        }
                        $needsRedraw = $true
                    }
                    3 { # Enable Hibernation
                        if (-not (Get-HibernationStatus)) {
                            [void](Enable-Hibernation)
                        } else {
                            Add-ActivityLog "Hibernation is already enabled"
                        }
                        $needsRedraw = $true
                    }
                    4 { # Set Power Button
                        [void](Set-PowerButtonToHibernate)
                        $needsRedraw = $true
                    }
                    5 { # Wake Device Manager
                        Show-WakeDeviceManager
                        $needsRedraw = $true
                    }
                    6 { # Exit
                        break
                    }
                }
                
                if ($selectedIndex -eq 6) { break }
            }
            'Spacebar' {
                switch ($selectedIndex) {
                    0 { # Refresh Status
                        Add-ActivityLog "Status refreshed"
                        $needsRedraw = $true
                    }
                    1 { # Auto-Fix
                        Invoke-AutoFix
                        $needsRedraw = $true
                    }
                    2 { # Disable Modern Standby
                        if (Get-ModernStandbyStatus) {
                            [void](Disable-ModernStandby)
                        } else {
                            Add-ActivityLog "Modern Standby is already disabled"
                        }
                        $needsRedraw = $true
                    }
                    3 { # Enable Hibernation
                        if (-not (Get-HibernationStatus)) {
                            [void](Enable-Hibernation)
                        } else {
                            Add-ActivityLog "Hibernation is already enabled"
                        }
                        $needsRedraw = $true
                    }
                    4 { # Set Power Button
                        [void](Set-PowerButtonToHibernate)
                        $needsRedraw = $true
                    }
                    5 { # Wake Device Manager
                        Show-WakeDeviceManager
                        $needsRedraw = $true
                    }
                    6 { # Exit
                        break
                    }
                }
                
                if ($selectedIndex -eq 6) { break }
            }
            'R' {
                Add-ActivityLog "Manual refresh requested"
                $needsRedraw = $true
            }
            'Q' {
                break
            }
            'Escape' {
                break
            }
        }
    }
    
    # Cleanup
    [Console]::CursorVisible = $true
    Clear-Host
    Write-ColorText "ROG Ally Sleep Doctor - Session Complete" $Colors.Success
    Write-ColorText "System optimized for better sleep performance!" $Colors.Info
    Write-ColorText ""
    Write-ColorText "Press any key to exit..." $Colors.Muted
    [Console]::ReadKey($true) | Out-Null
}

# Run the application
Start-SleepDoctor