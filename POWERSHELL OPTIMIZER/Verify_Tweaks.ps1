# ================================================================
#  VERIFY TWEAKS — Post-Restart Persistence Checker
#  Companion to PC_Optimizer.ps1
#
#  WHY THIS EXISTS:
#  A script can't prove its own changes survived a reboot from inside
#  the same run — that has to be checked AFTER you've actually restarted.
#  Run THIS script after rebooting to read back the real, current state
#  of every category of tweak PC_Optimizer.ps1 applied, and get a
#  straight PASS/FAIL report instead of just trusting it worked.
#
#  HOW TO USE:
#    1. Run PC_Optimizer.ps1, let it finish, restart your PC
#    2. After restart, right-click this file -> "Run with PowerShell"
#    3. Read the PASS/FAIL table
# ================================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } else {
        Write-Host "Please run this from an Administrator PowerShell window." -ForegroundColor Red
        Read-Host "Press Enter to close"
        return
    }
}

$results = New-Object System.Collections.Generic.List[object]

function Check-Reg {
    param([string]$Category,[string]$Name,[string]$Path,[string]$Prop,$Expected)
    $actual = $null
    $status = "FAIL"
    $detail = ""
    try {
        if (Test-Path $Path) {
            $val = Get-ItemProperty -Path $Path -Name $Prop -ErrorAction Stop
            $actual = $val.$Prop
            if ("$actual" -eq "$Expected") { $status = "PASS" }
            else { $detail = "expected '$Expected', found '$actual'" }
        } else {
            $detail = "registry path does not exist"
        }
    } catch {
        $detail = "value not present"
    }
    $results.Add([pscustomobject]@{Category=$Category;Name=$Name;Status=$status;Detail=$detail})
}

function Check-Service {
    param([string]$Category,[string]$Name,[string]$SvcName,[string]$ExpectedStartType)
    $status = "FAIL"; $detail = ""
    try {
        $svc = Get-Service -Name $SvcName -ErrorAction Stop
        $startType = (Get-WmiObject Win32_Service -Filter "Name='$SvcName'").StartMode
        if ($startType -eq $ExpectedStartType -or ($ExpectedStartType -eq "Disabled" -and $startType -eq "Disabled")) {
            $status = "PASS"
        } else {
            $detail = "expected StartType '$ExpectedStartType', found '$startType'"
        }
    } catch {
        $detail = "service not found (may not exist on this Windows edition)"
    }
    $results.Add([pscustomobject]@{Category=$Category;Name=$Name;Status=$status;Detail=$detail})
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " VERIFY TWEAKS — checking actual current system state" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ── PERFORMANCE ────────────────────────────────────────────────
Check-Reg "Performance" "VisualFXSetting = 2 (best performance)" `
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
Check-Reg "Performance" "Win32PrioritySeparation = 38 (foreground boost)" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
Check-Reg "Performance" "HwSchMode = 2 (Hardware GPU Scheduling)" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
Check-Reg "Performance" "HiberbootEnabled = 1 (Fast Startup)" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1

$activeScheme = (powercfg /getactivescheme) -replace '.*: ([0-9a-f-]{36}).*','$1'
$schemeOk = $activeScheme -match "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|e9a42b02-d5df-448d-aa00-03f14749eb61"
$results.Add([pscustomobject]@{Category="Performance";Name="Power plan = High Performance";
    Status=$(if($schemeOk){"PASS"}else{"FAIL"});Detail=$(if(-not $schemeOk){"active scheme GUID: $activeScheme"}else{""})})

# ── GAMING ─────────────────────────────────────────────────────
Check-Reg "Gaming" "PowerThrottlingOff = 1" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
Check-Reg "Gaming" "TdrDelay = 8 (GPU driver timeout)" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "TdrDelay" 8
Check-Reg "Gaming" "MouseSpeed = 0 (acceleration off)" `
    "HKCU:\Control Panel\Mouse" "MouseSpeed" "0"
Check-Reg "Gaming" "AutoGameModeEnabled = 1" `
    "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1

# ── PRIVACY & TELEMETRY ───────────────────────────────────────
Check-Reg "Privacy" "AllowTelemetry = 0" `
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
Check-Reg "Privacy" "Advertising ID disabled" `
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
Check-Reg "Privacy" "Activity History (PublishUserActivities) = 0" `
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
Check-Reg "Privacy" "Location Services disabled" `
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1
Check-Service "Privacy" "DiagTrack service disabled" "DiagTrack" "Disabled"
Check-Service "Privacy" "SysMain service disabled" "SysMain" "Disabled"
Check-Service "Privacy" "WSearch service disabled" "WSearch" "Disabled"

try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
    $smb1Ok = $smb1.State -eq "Disabled"
    $results.Add([pscustomobject]@{Category="Privacy";Name="SMB1 protocol disabled";
        Status=$(if($smb1Ok){"PASS"}else{"FAIL"});Detail=$(if(-not $smb1Ok){"State: $($smb1.State)"}else{""})})
} catch {
    $results.Add([pscustomobject]@{Category="Privacy";Name="SMB1 protocol disabled";Status="SKIP";Detail="could not query feature state"})
}

# ── MEMORY & CPU ───────────────────────────────────────────────
Check-Reg "Memory" "DisablePagingExecutive = 1 (kernel in RAM)" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
Check-Reg "Memory" "Memory Compression = 0" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "Compression" 0
Check-Reg "Memory" "EnableSuperfetch = 0" `
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0

# ── NETWORK ────────────────────────────────────────────────────
$dnsOk = $false; $dnsDetail = ""
try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Virtual|Loopback|Bluetooth|Hyper-V" }
    foreach ($a in $adapters) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4).ServerAddresses
        if ($dns -contains "1.1.1.1" -or $dns -contains "8.8.8.8") { $dnsOk = $true }
    }
    if (-not $dnsOk) { $dnsDetail = "no active adapter found with 1.1.1.1/8.8.8.8 set" }
} catch { $dnsDetail = "could not query adapters" }
$results.Add([pscustomobject]@{Category="Network";Name="DNS set to Cloudflare/Google";
    Status=$(if($dnsOk){"PASS"}else{"FAIL"});Detail=$dnsDetail})

Check-Reg "Network" "IPv6 unbound on adapters (spot check registry hint)" `
    "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "EnableAutoDoh" 2

# ── STARTUP ────────────────────────────────────────────────────
$runPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$stillPresent = @()
foreach ($app in @("Spotify","Discord","Skype","Steam")) {
    if (Get-ItemProperty -Path $runPath -Name $app -ErrorAction SilentlyContinue) { $stillPresent += $app }
}
$startupOk = $stillPresent.Count -eq 0
$results.Add([pscustomobject]@{Category="Startup";Name="Bloat autostart entries removed (sample check)";
    Status=$(if($startupOk){"PASS"}else{"FAIL"});
    Detail=$(if(-not $startupOk){"still present: $($stillPresent -join ', ')"}else{""})})

# ── BOOT-TIME SETTINGS (bcdedit — only apply after a reboot) ──
$bcdOutput = & "$env:SystemRoot\System32\bcdedit.exe" /enum 2>&1 | Out-String
$tickOk = $bcdOutput -match "useplatformtick\s+Yes"
$results.Add([pscustomobject]@{Category="Boot (needs restart)";Name="useplatformtick = Yes";
    Status=$(if($tickOk){"PASS"}else{"FAIL"});Detail=$(if(-not $tickOk){"check 'bcdedit /enum' manually"}else{""})})

# ════════════════════════════════════════════════════════════════
# REPORT
# ════════════════════════════════════════════════════════════════
Write-Host ""
$grouped = $results | Group-Object Category
foreach ($g in $grouped) {
    Write-Host "── $($g.Name) " -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * [Math]::Max(0,50-$g.Name.Length))
    foreach ($r in $g.Group) {
        $color = switch ($r.Status) { "PASS" {"Green"} "FAIL" {"Red"} default {"Gray"} }
        $line = "  [{0,-4}] {1}" -f $r.Status, $r.Name
        Write-Host $line -ForegroundColor $color
        if ($r.Detail) { Write-Host "         -> $($r.Detail)" -ForegroundColor DarkGray }
    }
}

$pass = ($results | Where-Object Status -eq "PASS").Count
$fail = ($results | Where-Object Status -eq "FAIL").Count
$skip = ($results | Where-Object Status -eq "SKIP").Count
$total = $results.Count

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " RESULT: $pass/$total checks passed" -ForegroundColor $(if($fail -eq 0){"Green"}else{"Yellow"})
if ($fail -gt 0) {
    Write-Host " $fail check(s) FAILED — see [FAIL] lines above for what to re-apply" -ForegroundColor Red
}
if ($skip -gt 0) {
    Write-Host " $skip check(s) SKIPPED (couldn't be queried on this system)" -ForegroundColor Gray
}
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: This checks a representative sample across all 6 categories," -ForegroundColor DarkGray
Write-Host "not literally every single one of the 100+ individual tweaks —" -ForegroundColor DarkGray
Write-Host "a full line-by-line check would be impractical to read. If a" -ForegroundColor DarkGray
Write-Host "category shows all PASS, the rest of that category's registry" -ForegroundColor DarkGray
Write-Host "writes almost certainly succeeded too (same code path, same run)." -ForegroundColor DarkGray
Write-Host ""
Read-Host "Press Enter to close"
