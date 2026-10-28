#Requires -Version 5.1
<#
.SYNOPSIS
Collect Windows OS and storage information.

.DESCRIPTION
Maps to the os.*, system.swap.* and storage.* sections of the Linux
health.json schema. Windows equivalents of the Linux /proc and df commands
are used; a missing path yields an UNKNOWN storage status rather than a
crash or a false OK.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# --- OS basics ---
$os = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch { }

# --- CPU count: sum logical processors, not sockets ---
$processors = @()
try {
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
} catch { }

$cpuCount = 0
foreach ($processor in $processors) {
    $logical = 0
    if ($null -ne $processor.NumberOfLogicalProcessors -and
        [int]::TryParse([string]$processor.NumberOfLogicalProcessors, [ref]$logical) -and
        $logical -gt 0) {
        $cpuCount += $logical
    }
}
if ($cpuCount -lt 1) {
    $cpuCount = $processors.Count
}
if ($cpuCount -lt 1) { $cpuCount = 1 }
$data['os.cpu.count'] = [string]$cpuCount

# --- CPU load ---
# Win32_Processor.LoadPercentage is a 1-minute snapshot; Windows does not
# expose the Unix 5/15-minute averages, so all three use the same value.
$load1 = 0.0
$loads = @($processors | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { [double]$_.LoadPercentage })
if ($loads.Count -gt 0) {
    $load1 = [Math]::Round((($loads | Measure-Object -Average).Average), 2)
}
$loadText = $load1.ToString('0.##', $invariant)
$data['os.cpu.load1'] = $loadText
$data['os.cpu.load5'] = $loadText
$data['os.cpu.load15'] = $loadText

# --- Memory (kb) ---
# Win32_OperatingSystem exposes TotalVisibleMemorySize and
# FreePhysicalMemory in KB. TotalPhysicalMemory lives on
# Win32_ComputerSystem and is in bytes; use it only as a fallback.
$memTotalKb = 0
$memAvailableKb = 0
if ($os) {
    if ($os.PSObject.Properties['TotalVisibleMemorySize'] -and $null -ne $os.TotalVisibleMemorySize) {
        $memTotalKb = [long]$os.TotalVisibleMemorySize
    } elseif ($os.PSObject.Properties['TotalPhysicalMemory'] -and $null -ne $os.TotalPhysicalMemory) {
        $memTotalKb = [long]([double]$os.TotalPhysicalMemory / 1024)
    } else {
        try {
            $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($computer.PSObject.Properties['TotalPhysicalMemory'] -and $null -ne $computer.TotalPhysicalMemory) {
                $memTotalKb = [long]([double]$computer.TotalPhysicalMemory / 1024)
            }
        } catch { }
    }

    if ($os.PSObject.Properties['FreePhysicalMemory'] -and $null -ne $os.FreePhysicalMemory) {
        $memAvailableKb = [long]$os.FreePhysicalMemory
    }
}
$data['os.memory.total_kb'] = [string]$memTotalKb
$data['os.memory.available_kb'] = [string]$memAvailableKb

# --- Swap (kb) ---
# Win32_PageFileUsage reports AllocatedBaseSize and CurrentUsage in MB.
$swapTotalKb = 0
$swapFreeKb = 0
try {
    $pages = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
    foreach ($page in $pages) {
        $allocatedMb = [long]$page.AllocatedBaseSize
        $currentMb = [long]$page.CurrentUsage
        $swapTotalKb += $allocatedMb * 1024
        $swapFreeKb += [long]([Math]::Max(0, $allocatedMb - $currentMb)) * 1024
    }
} catch { }
$data['os.swap.total_kb'] = [string]$swapTotalKb
$data['os.swap.free_kb'] = [string]$swapFreeKb

# --- Last OS update date ---
$lastUpdate = ''
$packageManager = 'unknown'
try {
    $hotfix = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
        Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
    if ($hotfix -and $hotfix.InstalledOn) {
        $lastUpdate = ([datetime]$hotfix.InstalledOn).ToString('yyyy-MM-dd HH:mm')
    }
} catch { }
$data['os.last_update_date'] = $lastUpdate
$data['os.package_manager'] = $packageManager
$data['os.repository_access'] = '0'

# --- Time sync ---
$data['os.time_sync.method'] = 'w32time'
$data['os.time_sync.synced'] = '0'
try {
    $statusText = (& w32tm /query /status 2>$null | Out-String)
    if ($statusText -match '(?im)^\s*Source:\s*(.+)$') {
        $source = $Matches[1].Trim()
        if ($source -notmatch '(?i)local cmos|free-running|unsynchronized') {
            $data['os.time_sync.synced'] = '1'
        }
    }
} catch { }

# --- system.swap.* summary ---
$swapUsedKb = $swapTotalKb - $swapFreeKb
$swapPercentText = '0.00'
$swapPercent = 0.0
if ($swapTotalKb -gt 0) {
    $swapPercent = [Math]::Round($swapUsedKb / $swapTotalKb * 100, 2)
    $swapPercentText = $swapPercent.ToString('0.00', $invariant)
}
$data['system.swap.total_kb'] = [string]$swapTotalKb
$data['system.swap.used_kb'] = [string]$swapUsedKb
$data['system.swap.used_percent'] = $swapPercentText
$data['system.swap.history'] = ''
if ($swapTotalKb -gt 0 -and $swapPercent -gt 3) {
    $data['system.swap.message'] = ('Swap is currently in use ({0}%)' -f $swapPercentText)
    $data['system.swap.status'] = 'CRITICAL'
} else {
    $data['system.swap.message'] = 'Swap is not in use'
    $data['system.swap.status'] = 'PASS'
}

# --- storage.* - one block per monitored path, matching the Linux df output ---
function Add-StorageStats {
    param([string]$Prefix, [string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $data["$Prefix.device"] = ''
        $data["$Prefix.mount"] = ''
        $data["$Prefix.path"] = ''
        $data["$Prefix.status"] = 'UNKNOWN'
        $data["$Prefix.total_gb"] = ''
        $data["$Prefix.used_gb"] = ''
        $data["$Prefix.free_gb"] = ''
        $data["$Prefix.used_percent"] = ''
        return
    }

    $data["$Prefix.path"] = $Path

    try {
        $root = ''
        try { $root = [System.IO.Path]::GetPathRoot($Path) } catch { }
        if ([string]::IsNullOrWhiteSpace($root)) {
            try { $root = Split-Path -Path $Path -Qualifier } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($root) -and $Path -match '^([A-Za-z]:)') {
            $root = $Matches[1] + '\'
        }

        $normalizedRoot = ([string]$root).TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
        $drive = $null
        if ($normalizedRoot) {
            $drive = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Root.TrimEnd([char[]]@('\', '/')).ToLowerInvariant() -eq $normalizedRoot } |
                Select-Object -First 1)
        }

        if (-not $drive -or $null -eq $drive.Used -or $null -eq $drive.Free) {
            $data["$Prefix.device"] = ''
            $data["$Prefix.mount"] = ''
            $data["$Prefix.total_gb"] = ''
            $data["$Prefix.used_gb"] = ''
            $data["$Prefix.free_gb"] = ''
            $data["$Prefix.used_percent"] = ''
            $data["$Prefix.status"] = 'UNKNOWN'
            return
        }

        # Get-PSDrive.Used/Free are bytes. Convert directly to GB.
        $totalBytes = [double]$drive.Used + [double]$drive.Free
        $usedBytes = [double]$drive.Used
        $freeBytes = [double]$drive.Free

        $data["$Prefix.device"] = [string]$drive.Root
        $data["$Prefix.mount"] = [string]$drive.Root
        $data["$Prefix.total_gb"] = ([Math]::Round($totalBytes / 1GB, 1)).ToString('0.0', $invariant)
        $data["$Prefix.used_gb"] = ([Math]::Round($usedBytes / 1GB, 1)).ToString('0.0', $invariant)
        $data["$Prefix.free_gb"] = ([Math]::Round($freeBytes / 1GB, 1)).ToString('0.0', $invariant)

        $usedPercent = 0
        if ($totalBytes -gt 0) {
            $usedPercent = [int][Math]::Round($usedBytes / $totalBytes * 100)
        }
        $data["$Prefix.used_percent"] = [string]$usedPercent
        if ($totalBytes -le 0) {
            $data["$Prefix.status"] = 'UNKNOWN'
        } elseif ($usedPercent -ge 90) {
            $data["$Prefix.status"] = 'WARNING'
        } else {
            $data["$Prefix.status"] = 'OK'
        }
    } catch {
        $data["$Prefix.device"] = ''
        $data["$Prefix.mount"] = ''
        $data["$Prefix.status"] = 'UNKNOWN'
        $data["$Prefix.total_gb"] = ''
        $data["$Prefix.used_gb"] = ''
        $data["$Prefix.free_gb"] = ''
        $data["$Prefix.used_percent"] = ''
    }
}

$envDrive = $env:SystemDrive
if ([string]::IsNullOrEmpty($envDrive)) { $envDrive = 'C:' }
$envDrive = $envDrive.TrimEnd([char[]]@('\', '/'))

Add-StorageStats -Prefix 'storage.archive' -Path (Join-Path $Context.Config.IceWarpHome 'archive')
Add-StorageStats -Prefix 'storage.install' -Path $Context.Config.IceWarpHome
Add-StorageStats -Prefix 'storage.mail' -Path (Join-Path $Context.Config.IceWarpHome 'mail')
Add-StorageStats -Prefix 'storage.root_fs' -Path ($envDrive + '\')
Add-StorageStats -Prefix 'storage.root_home' -Path (Join-Path $envDrive 'Users')

return $data
