#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Intel Driver Scanner & Updater
    Scans installed Intel drivers, checks Intel's official download center for newer versions,
    and optionally installs updates — similar to winget upgrade.

.NOTES
    Run in Windows Terminal as Administrator:
        powershell -ExecutionPolicy Bypass -File "Intel-Driver-Updater.ps1"
    Or with auto-update flag:
        powershell -ExecutionPolicy Bypass -File "Intel-Driver-Updater.ps1" -AutoUpdate
#>

param (
    [switch]$AutoUpdate,       # Skip confirmation prompts and auto-install all updates
    [switch]$ScanOnly,         # Only scan, never download/install
    [switch]$Recheck           # Force a recheck pass after updates
)

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
$script:Config = @{
    LogFile       = "$env:TEMP\IntelDriverUpdater_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    DownloadDir   = "$env:TEMP\IntelDriverDownloads"
    IntelAPIBase  = "https://downloadmirror.intel.com"
    IntelAPISearch= "https://www.intel.com/content/www/us/en/download-center/home.html"
    # Intel DSA (Driver & Support Assistant) silent installer URL — always points to latest
    DSA_URL       = "https://dsaredir.intel.com/api/download/IntelDriverAndSupportAssistant.exe"
    WingetID      = "Intel.IntelDriverAndSupportAssistant"
}

# ─────────────────────────────────────────────────────────────────────────────
#  COLOUR HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Header  { param($t) Write-Host "`n$('─'*70)" -ForegroundColor Cyan; Write-Host "  $t" -ForegroundColor Cyan; Write-Host "$('─'*70)" -ForegroundColor Cyan }
function Write-Ok      { param($t) Write-Host "  [✔] $t" -ForegroundColor Green  }
function Write-Warn    { param($t) Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err     { param($t) Write-Host "  [✘] $t" -ForegroundColor Red    }
function Write-Info    { param($t) Write-Host "  [i] $t" -ForegroundColor Cyan   }
function Write-Step    { param($t) Write-Host "  [>] $t" -ForegroundColor White  }

function Log {
    param($Message, $Level = "INFO")
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp [$Level] $Message" | Out-File -FilePath $script:Config.LogFile -Append -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host @"

  ██╗███╗   ██╗████████╗███████╗██╗         ██████╗ ██████╗ ██╗██╗   ██╗███████╗██████╗
  ██║████╗  ██║╚══██╔══╝██╔════╝██║        ██╔══██╗██╔══██╗██║██║   ██║██╔════╝██╔══██╗
  ██║██╔██╗ ██║   ██║   █████╗  ██║        ██║  ██║██████╔╝██║██║   ██║█████╗  ██████╔╝
  ██║██║╚██╗██║   ██║   ██╔══╝  ██║        ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  ██╔══██╗
  ██║██║ ╚████║   ██║   ███████╗███████╗   ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██║  ██║
  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚══════╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
                             U P D A T E R   v2.0
"@ -ForegroundColor Blue
    Write-Host "  Scans Intel drivers · Checks intel.com · Updates like winget upgrade`n" -ForegroundColor DarkCyan
}

# ─────────────────────────────────────────────────────────────────────────────
#  VERSION COMPARISON  (handles Intel formats: 31.0.101.5379, 10.1.1.45, etc.)
# ─────────────────────────────────────────────────────────────────────────────
function Compare-Versions {
    param([string]$Installed, [string]$Latest)
    try {
        $i = [Version]($Installed -replace '[^0-9.]','')
        $l = [Version]($Latest    -replace '[^0-9.]','')
        return $l.CompareTo($i)   # >0 means latest is newer
    } catch {
        return [string]::Compare($Latest, $Installed, $true)
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  1. ENUMERATE INSTALLED INTEL DRIVERS
# ─────────────────────────────────────────────────────────────────────────────
function Get-InstalledIntelDrivers {
    Write-Header "STEP 1 — Scanning Installed Intel Drivers"
    Log "Starting Intel driver scan"

    $drivers = @()

    # ── A) PnP devices with Intel provider ──────────────────────────────────
    Write-Step "Querying PnP device drivers (Intel)…"
    $pnpDrivers = Get-WmiObject Win32_PnPSignedDriver |
        Where-Object { $_.Manufacturer -like "*Intel*" -or $_.ProviderName -like "*Intel*" } |
        Select-Object DeviceName, DriverVersion, Manufacturer, DriverDate, DeviceClass, HardWareID

    foreach ($d in $pnpDrivers) {
        if (-not $d.DriverVersion) { continue }
        $drivers += [PSCustomObject]@{
            Name        = ($d.DeviceName  -replace '\s+',' ').Trim()
            Version     = $d.DriverVersion
            Date        = $d.DriverDate
            Class       = $d.DeviceClass
            HardwareID  = ($d.HardWareID | Select-Object -First 1)
            Source      = "PnP"
            UpdateAvail = $false
            LatestVer   = ""
            DownloadURL = ""
        }
    }

    # ── B) Add-Remove Programs (Intel software w/ versions) ─────────────────
    Write-Step "Scanning installed Intel software (registry)…"
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        Get-ItemProperty $rp -ErrorAction SilentlyContinue |
            Where-Object { $_.Publisher -like "*Intel*" -and $_.DisplayVersion } |
            ForEach-Object {
                $name = $_.DisplayName
                if ($drivers.Name -notcontains $name) {
                    $drivers += [PSCustomObject]@{
                        Name        = $name
                        Version     = $_.DisplayVersion
                        Date        = $_.InstallDate
                        Class       = "Software"
                        HardwareID  = ""
                        Source      = "Registry"
                        UpdateAvail = $false
                        LatestVer   = ""
                        DownloadURL = ""
                    }
                }
            }
    }

    # ── C) Deduplicate by name, keep highest version ─────────────────────────
    $drivers = $drivers |
        Group-Object Name |
        ForEach-Object {
            $_.Group | Sort-Object Version -Descending | Select-Object -First 1
        }

    Write-Ok "Found $($drivers.Count) Intel driver/software entries"
    Log "Found $($drivers.Count) Intel entries"
    return $drivers
}

# ─────────────────────────────────────────────────────────────────────────────
#  2. LOOKUP LATEST VERSIONS VIA INTEL DSA API  (unofficial JSON endpoints)
# ─────────────────────────────────────────────────────────────────────────────

# Map of known Intel product keywords → Intel Download Center category IDs
$script:IntelCategoryMap = @{
    "Graphics"              = @{ ProductLine="Graphics"; Keywords=@("graphics","display","uhd","iris","arc","xe") }
    "Wireless"              = @{ ProductLine="Wireless-Networking"; Keywords=@("wireless","wi-fi","wifi","bluetooth","ax","be") }
    "Ethernet"              = @{ ProductLine="Ethernet-Products"; Keywords=@("ethernet","i219","i225","i226","network") }
    "Chipset"               = @{ ProductLine="Chipset"; Keywords=@("chipset","management engine","mei","heci") }
    "Storage"               = @{ ProductLine="Solid-State-Drives"; Keywords=@("storage","rst","rapid storage","optane","nvme","ssd") }
    "Thunderbolt"           = @{ ProductLine="Thunderbolt"; Keywords=@("thunderbolt","usb4") }
    "Serial IO"             = @{ ProductLine="Serial-IO"; Keywords=@("serial io","gpio","i2c","spi","uart") }
    "Management Engine"     = @{ ProductLine="Converged-Security-Management-Engine"; Keywords=@("management engine","csme","mei") }
    "Bluetooth"             = @{ ProductLine="Wireless-Networking"; Keywords=@("bluetooth") }
}

function Get-IntelCategoryForDriver {
    param([string]$DriverName)
    $lower = $DriverName.ToLower()
    foreach ($cat in $script:IntelCategoryMap.Keys) {
        foreach ($kw in $script:IntelCategoryMap[$cat].Keywords) {
            if ($lower -match [regex]::Escape($kw)) {
                return $cat
            }
        }
    }
    return $null
}

function Get-LatestVersionFromIntel {
    param([string]$DriverName, [string]$InstalledVersion)

    $category = Get-IntelCategoryForDriver -DriverName $DriverName
    if (-not $category) { return $null }

    $productLine = $script:IntelCategoryMap[$category].ProductLine

    try {
        # Intel's unofficial JSON API used by their download pages
        $apiUrl = "https://www.intel.com/content/dam/www/central-libraries/us/en/documents/download-center/download-redirect.json"
        
        # Use Intel's search API endpoint
        $searchUrl = "https://www.intel.com/bin/inteldownloadcenter/getDownloadsByProductLine?productLine=$productLine&lang=eng&os=OS101&downloadsType=Drivers"
        
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            "Accept"     = "application/json, text/plain, */*"
            "Referer"    = "https://www.intel.com/content/www/us/en/download-center/home.html"
        }

        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop

        if ($response -and $response.downloads) {
            $latest = $response.downloads |
                Sort-Object { [Version]($_.version -replace '[^0-9.]','') } -Descending |
                Select-Object -First 1

            if ($latest) {
                return [PSCustomObject]@{
                    Version     = $latest.version
                    DownloadURL = if ($latest.downloadURL) { $latest.downloadURL } else { "https://www.intel.com/content/www/us/en/download-center/home.html" }
                    Title       = $latest.title
                }
            }
        }
    } catch {
        # Fallback: try winget source for known Intel packages
    }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
#  2b. WINGET FALLBACK — check Intel packages in winget
# ─────────────────────────────────────────────────────────────────────────────
$script:WingetIntelPackages = @(
    [PSCustomObject]@{ Keyword="graphics driver";        WingetID="Intel.IntelGraphicsCommandCenter"         }
    [PSCustomObject]@{ Keyword="wireless";               WingetID="Intel.IntelWirelessNetworkAdapter"        }
    [PSCustomObject]@{ Keyword="bluetooth";              WingetID="Intel.IntelBluetooth"                     }
    [PSCustomObject]@{ Keyword="ethernet";               WingetID="Intel.EthernetAdapterCompleteDriverPack"  }
    [PSCustomObject]@{ Keyword="chipset";                WingetID="Intel.IntelChipsetDeviceSoftware"         }
    [PSCustomObject]@{ Keyword="rapid storage";          WingetID="Intel.IntelRapidStorageTechnology"        }
    [PSCustomObject]@{ Keyword="management engine";      WingetID="Intel.IntelManagementEngineComponents"    }
    [PSCustomObject]@{ Keyword="serial io";              WingetID="Intel.IntelSerialIO"                      }
    [PSCustomObject]@{ Keyword="thunderbolt";            WingetID="Intel.ThunderboltSoftware"                }
    [PSCustomObject]@{ Keyword="arc";                    WingetID="Intel.IntelArcControlPanel"               }
    [PSCustomObject]@{ Keyword="optane";                 WingetID="Intel.IntelOptaneMemoryRapidStorageTech"  }
)

function Get-WingetVersionForDriver {
    param([string]$DriverName)
    $lower = $DriverName.ToLower()
    foreach ($pkg in $script:WingetIntelPackages) {
        if ($lower -match [regex]::Escape($pkg.Keyword)) {
            try {
                $info = winget show $pkg.WingetID 2>&1 | Select-String "Version:"
                if ($info) {
                    $ver = ($info -split ":")[-1].Trim()
                    return [PSCustomObject]@{
                        Version     = $ver
                        WingetID    = $pkg.WingetID
                        DownloadURL = "winget"
                    }
                }
            } catch {}
        }
    }
    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
#  3. CHECK FOR UPDATES
# ─────────────────────────────────────────────────────────────────────────────
function Check-DriverUpdates {
    param([array]$Drivers)
    Write-Header "STEP 2 — Checking Intel Download Center for Updates"
    Log "Checking for updates"

    $updatesAvailable = @()
    $total = $Drivers.Count
    $i = 0

    foreach ($drv in $Drivers) {
        $i++
        $pct = [math]::Round(($i / $total) * 100)
        Write-Progress -Activity "Checking Intel servers…" -Status "$($drv.Name)" -PercentComplete $pct

        # Try Intel API first, then winget fallback
        $latest = Get-LatestVersionFromIntel -DriverName $drv.Name -InstalledVersion $drv.Version
        $source = "Intel API"

        if (-not $latest) {
            $latest = Get-WingetVersionForDriver -DriverName $drv.Name
            $source = "winget"
        }

        if ($latest -and $latest.Version) {
            $cmp = Compare-Versions -Installed $drv.Version -Latest $latest.Version
            if ($cmp -gt 0) {
                $drv.UpdateAvail = $true
                $drv.LatestVer   = $latest.Version
                $drv.DownloadURL = $latest.DownloadURL
                if ($latest.WingetID) { $drv | Add-Member -NotePropertyName WingetID -NotePropertyValue $latest.WingetID -Force }
                $updatesAvailable += $drv
                Log "UPDATE AVAILABLE: $($drv.Name) [$($drv.Version) → $($latest.Version)] via $source"
            }
        }
    }
    Write-Progress -Activity "Checking Intel servers…" -Completed
    return $updatesAvailable
}

# ─────────────────────────────────────────────────────────────────────────────
#  4. DISPLAY RESULTS TABLE
# ─────────────────────────────────────────────────────────────────────────────
function Show-ScanResults {
    param([array]$All, [array]$Updates)

    Write-Header "SCAN RESULTS"
    $upToDate = $All.Count - $Updates.Count

    Write-Host ""
    Write-Host "  Total Intel drivers scanned : " -NoNewline; Write-Host $All.Count -ForegroundColor White
    Write-Host "  Up to date                  : " -NoNewline; Write-Host $upToDate -ForegroundColor Green
    Write-Host "  Updates available           : " -NoNewline
    if ($Updates.Count -gt 0) { Write-Host $Updates.Count -ForegroundColor Yellow }
    else                       { Write-Host "0" -ForegroundColor Green }
    Write-Host ""

    if ($Updates.Count -gt 0) {
        Write-Host "  ┌─────────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "  │  UPDATES AVAILABLE                                                  │" -ForegroundColor Yellow
        Write-Host "  ├────────────────────────────────┬──────────────────┬─────────────────┤" -ForegroundColor Yellow
        Write-Host "  │ Driver                         │ Installed        │ Available       │" -ForegroundColor Yellow
        Write-Host "  ├────────────────────────────────┼──────────────────┼─────────────────┤" -ForegroundColor Yellow
        foreach ($u in $Updates) {
            $n  = $u.Name.PadRight(30).Substring(0,30)
            $iv = $u.Version.PadRight(16).Substring(0,[Math]::Min(16,$u.Version.Length)).PadRight(16)
            $lv = $u.LatestVer.PadRight(15).Substring(0,[Math]::Min(15,$u.LatestVer.Length)).PadRight(15)
            Write-Host "  │ $n │ $iv │ $lv │" -ForegroundColor Yellow
        }
        Write-Host "  └────────────────────────────────┴──────────────────┴─────────────────┘" -ForegroundColor Yellow
    } else {
        Write-Ok "All Intel drivers are up to date!"
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  5. INSTALL UPDATES
# ─────────────────────────────────────────────────────────────────────────────
function Install-DriverUpdate {
    param([PSCustomObject]$Driver)

    $name = $Driver.Name

    # ── Path A: winget ID available ──────────────────────────────────────────
    if ($Driver.WingetID) {
        Write-Step "Upgrading via winget: $($Driver.WingetID)"
        Log "winget upgrade $($Driver.WingetID)"
        $result = winget upgrade --id $Driver.WingetID --silent --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Updated: $name → $($Driver.LatestVer)"
            Log "SUCCESS: $name upgraded via winget"
            return $true
        } else {
            Write-Warn "winget upgrade failed (exit $LASTEXITCODE). Trying direct download…"
            Log "winget failed for $name — $result"
        }
    }

    # ── Path B: direct download URL ─────────────────────────────────────────
    if ($Driver.DownloadURL -and $Driver.DownloadURL -ne "winget") {
        $ext      = if ($Driver.DownloadURL -match "\.exe") { ".exe" } else { ".exe" }
        $fileName = "$env:TEMP\IntelDrv_$([System.IO.Path]::GetRandomFileName())$ext"
        Write-Step "Downloading: $($Driver.DownloadURL)"
        Log "Downloading $($Driver.DownloadURL)"
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            $wc.DownloadFile($Driver.DownloadURL, $fileName)
            Write-Step "Running silent installer…"
            $proc = Start-Process -FilePath $fileName -ArgumentList "/s /norestart" -Wait -PassThru
            if ($proc.ExitCode -in 0, 3010) {
                Write-Ok "Updated: $name"
                Log "SUCCESS: $name installed (exit $($proc.ExitCode))"
                return $true
            } else {
                Write-Warn "Installer exited with code $($proc.ExitCode) — may require reboot or manual check"
                Log "WARN: $name installer exit $($proc.ExitCode)"
            }
        } catch {
            Write-Err "Download/install failed: $_"
            Log "ERROR: $name — $_" -Level "ERROR"
        }
    }

    # ── Path C: open Intel download page ────────────────────────────────────
    Write-Warn "Cannot auto-install '$name'. Opening Intel Download Center…"
    Start-Process "https://www.intel.com/content/www/us/en/download-center/home.html"
    return $false
}

function Update-AllDrivers {
    param([array]$Updates)

    if ($Updates.Count -eq 0) { return }

    Write-Header "STEP 3 — Installing Updates"

    if (-not $AutoUpdate) {
        Write-Host "  The following drivers will be updated:" -ForegroundColor Cyan
        $Updates | ForEach-Object { Write-Host "    • $($_.Name)  $($_.Version) → $($_.LatestVer)" -ForegroundColor Yellow }
        Write-Host ""
        $ans = Read-Host "  Proceed with all updates? [Y/n]"
        if ($ans -match "^[Nn]") {
            Write-Info "Skipped. Re-run with -AutoUpdate to skip this prompt."
            return
        }
    }

    $success = 0; $fail = 0
    foreach ($upd in $Updates) {
        Write-Host ""
        Write-Host "  ▶ $($upd.Name)" -ForegroundColor Cyan
        if (Install-DriverUpdate -Driver $upd) { $success++ } else { $fail++ }
    }

    Write-Host ""
    Write-Ok "Updated successfully : $success"
    if ($fail -gt 0) { Write-Warn "Failed / manual needed: $fail" }
    Log "Update pass: $success success, $fail fail"
}

# ─────────────────────────────────────────────────────────────────────────────
#  6. INTEL DSA (Driver & Support Assistant) — bonus install/launch
# ─────────────────────────────────────────────────────────────────────────────
function Offer-IntelDSA {
    $dsaInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*Intel*Driver*Support*" }

    Write-Header "BONUS — Intel Driver & Support Assistant (DSA)"
    if ($dsaInstalled) {
        Write-Ok "Intel DSA is already installed: $($dsaInstalled.DisplayVersion)"
        Write-Info "Launch it for a full GUI scan: Start Menu → Intel Driver & Support Assistant"
    } else {
        Write-Info "Intel DSA provides a full GUI-based driver scanner from Intel."
        Write-Info "Install via winget: winget install --id Intel.IntelDriverAndSupportAssistant"
        if (-not $ScanOnly) {
            $ans = Read-Host "  Install Intel DSA now? [y/N]"
            if ($ans -match "^[Yy]") {
                Write-Step "Installing Intel DSA via winget…"
                winget install --id Intel.IntelDriverAndSupportAssistant --silent --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -eq 0) { Write-Ok "Intel DSA installed successfully!" }
                else { Write-Warn "winget install failed. Downloading directly…"; Start-Process $script:Config.DSA_URL }
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  RECHECK PASS
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Recheck {
    Write-Header "RECHECK — Verifying Updates Applied Correctly"
    Log "Starting recheck pass"
    Write-Step "Re-scanning drivers…"
    Start-Sleep -Seconds 2

    $freshDrivers  = Get-InstalledIntelDrivers
    $stillPending  = Check-DriverUpdates -Drivers $freshDrivers

    if ($stillPending.Count -eq 0) {
        Write-Ok "All Intel drivers are confirmed up to date after update pass!"
        Log "Recheck: all up to date"
    } else {
        Write-Warn "$($stillPending.Count) driver(s) still show updates pending (may need reboot):"
        $stillPending | ForEach-Object {
            Write-Host "    • $($_.Name)  installed=$($_.Version)  latest=$($_.LatestVer)" -ForegroundColor Yellow
        }
        Write-Info "A system reboot may be required to complete pending updates."
        Log "Recheck: $($stillPending.Count) still pending"
    }
    Show-ScanResults -All $freshDrivers -Updates $stillPending
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────
Show-Banner

# Prerequisite checks
Write-Header "PRE-FLIGHT CHECKS"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Err "This script must be run as Administrator. Right-click → Run as Administrator."
    exit 1
}
Write-Ok "Running as Administrator"

# Check winget
$wingetAvail = $null
try { $wingetAvail = Get-Command winget -ErrorAction Stop } catch {}
if ($wingetAvail) { Write-Ok "winget is available (v$(winget --version 2>&1))" }
else              { Write-Warn "winget not found — direct download fallback will be used" }

# Check internet
try {
    $null = Invoke-WebRequest -Uri "https://www.intel.com" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Write-Ok "Internet connection confirmed"
} catch {
    Write-Err "No internet connection. Cannot check for updates."
    exit 1
}

New-Item -ItemType Directory -Path $script:Config.DownloadDir -Force | Out-Null
Log "Script started | AutoUpdate=$AutoUpdate | ScanOnly=$ScanOnly | Recheck=$Recheck"

# ── Run pipeline ─────────────────────────────────────────────────────────────
$allDrivers = Get-InstalledIntelDrivers
$updates    = Check-DriverUpdates -Drivers $allDrivers

Show-ScanResults -All $allDrivers -Updates $updates

if (-not $ScanOnly -and $updates.Count -gt 0) {
    Update-AllDrivers -Updates $updates
    if ($Recheck -or $AutoUpdate) {
        Invoke-Recheck
    } else {
        $ans = Read-Host "`n  Run a recheck to verify updates? [y/N]"
        if ($ans -match "^[Yy]") { Invoke-Recheck }
    }
} elseif ($updates.Count -eq 0) {
    Write-Ok "Nothing to update. All Intel drivers are current!"
}

Offer-IntelDSA

# ── Footer ───────────────────────────────────────────────────────────────────
Write-Header "DONE"
Write-Ok "Log saved to: $($script:Config.LogFile)"
Write-Info "Tip: Run with -AutoUpdate for fully unattended updates"
Write-Info "Tip: Run with -ScanOnly to check without installing"
Write-Info "Tip: Run with -Recheck to force a verification pass"
Write-Host ""
Log "Script completed"
