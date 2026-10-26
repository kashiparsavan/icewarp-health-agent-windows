#Requires -Version 5.1
<#
.SYNOPSIS
Collect Windows OS and storage information.

.DESCRIPTION
Maps to the os.*, system.swap.* and storage.* sections of the Linux
health.json schema. Produces exactly the same keys the Linux collectors
produce, nothing more and nothing less. Windows equivalents of the Linux
/proc and df commands are used; a missing path yields an empty string
rather than a crash.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# --- OS basics ---
# NOTE: the Linux schema only exposes os.cpu.*, os.memory.*,
# os.swap.*, os.last_update_date, os.package_manager,
# os.repository_access and os.time_sync.*. There is no os.caption /
# os.version / os.build / os.architecture in the schema, so those are
# deliberately NOT emitted here.
$os = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch { }

# --- CPU count ---
$cpuCount = 0
try {
    $cpuCount = (Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop).Count
} catch { }
if ($cpuCount -lt 1) { $cpuCount = 1 }
$data['os.cpu.count'] = [string]$cpuCount

# --- CPU load (1/5/15 min) - Win32_Processor.LoadPercentage is a 1-min
# snapshot; the 5 and 15 min averages are not exposed, so we approximate
# them as the same value. ---
$load1 = 0
try {
    $load1 = [int]([Math]::Round((Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop).LoadPercentage))
} catch { }
$data['os.cpu.load1'] = [string]$load1
$data['os.cpu.load5'] = [string]$load1
$data['os.cpu.load15'] = [string]$load1

# --- Memory (kb) ---
$memTotal = 0
$memFree = 0
if ($os) {
    $memTotal = [long]$os.TotalPhysicalMemory
    $memFree = [long]$os.FreePhysicalMemory
}
$data['os.memory.total_kb'] = [string]($memTotal / 1024)
$data['os.memory.available_kb'] = [string]($memFree / 1024)

# --- Swap (kb) ---
$swapTotal = 0
$swapFree = 0
try {
    $pages = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
    foreach ($p in $pages) {
        $swapTotal += [long]$p.AllocatedBaseSize
        $swapFree += [long]([Math]::Max(0, $p.AllocatedBaseSize - $p.CurrentUsage))
    }
} catch { }
$data['os.swap.total_kb'] = [string]($swapTotal * 1024)
$data['os.swap.free_kb'] = [string]($swapFree * 1024)

# --- Last OS update date ---
$lastUpdate = ''
$packageManager = 'unknown'
if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
    try {
        $hotfixes = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
            Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
        if ($hotfixes) {
            $lastUpdate = $hotfixes.InstalledOn.ToString('yyyy-MM-dd HH:mm')
        }
    } catch { }
}
$data['os.last_update_date'] = $lastUpdate
$data['os.package_manager'] = $packageManager
$data['os.repository_access'] = '0'

# --- Time sync ---
$data['os.time_sync.method'] = 'w32time'
$data['os.time_sync.synced'] = '0'
try {
    $ts = (w32tm query status 2>$null)
    if ($ts -match 'Local Clock Precision') { $data['os.time_sync.method'] = 'w32time' }
    if ($ts -match 'Last Successful Sync Time') { $data['os.time_sync.synced'] = '1' }
} catch { }

# --- system.swap.* summary ---
$swapUsed = 0
$swapTotalKb = 0
if ([int]::TryParse([string]$data['os.swap.total_kb'], [ref]$swapTotalKb)) {
    $swapFreeKb = 0
    if ([int]::TryParse([string]$data['os.swap.free_kb'], [ref]$swapFreeKb)) {
        $swapUsed = $swapTotalKb - $swapFreeKb
    }
}
$data['system.swap.total_kb'] = [string]$swapTotalKb
$data['system.swap.used_kb'] = [string]$swapUsed
if ($swapTotalKb -gt 0) {
    $data['system.swap.used_percent'] = [Math]::Round($swapUsed / $swapTotalKb * 100, 2).ToString('0.00')
} else {
    $data['system.swap.used_percent'] = '0.00'
}
if ($swapTotalKb -gt 0 -and $swapUsed / $swapTotalKb * 100 -gt 3) {
    $data['system.swap.history'] = ''
    $data['system.swap.message'] = 'Swap is currently in use ({0}%)' -f $data['system.swap.used_percent']
    $data['system.swap.status'] = 'CRITICAL'
} else {
    $data['system.swap.history'] = ''
    $data['system.swap.message'] = 'Swap is not in use'
    $data['system.swap.status'] = 'PASS'
}

# --- storage.* - one block per monitored path, matching the Linux df output ---
function Add-StorageStats {
    param([string]$Prefix, [string]$Path)
    if ([string]::IsNullOrEmpty($Path)) {
        $data["$prefix.device"] = ''
        $data["$prefix.mount"] = ''
        $data["$prefix.path"] = ''
        $data["$prefix.status"] = ''
        $data["$prefix.total_gb"] = ''
        $data["$prefix.used_gb"] = ''
        $data["$prefix.free_gb"] = ''
        $data["$prefix.used_percent"] = ''
        return
    }
    $data["$prefix.path"] = $Path
    try {
        $drive = (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Root -eq (Split-Path -Path $Path -Qualifier) } | Select-Object -First 1)
        if (-not $drive) {
            $drive = (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        $data["$prefix.device"] = [string]$drive.Root
        $data["$prefix.mount"] = [string]$drive.Root
        $totalKb = [long]($drive.Used + $drive.Free) * 1024
        $usedKb = [long]$drive.Used * 1024
        $freeKb = [long]$drive.Free * 1024
        $data["$prefix.total_gb"] = ([Math]::Round($totalKb / 1024 / 1024, 1)).ToString('0.0')
        $data["$prefix.used_gb"] = ([Math]::Round($usedKb / 1024 / 1024, 1)).ToString('0.0')
        $data["$prefix.free_gb"] = ([Math]::Round($freeKb / 1024 / 1024, 1)).ToString('0.0')
        if ($totalKb -gt 0) {
            $data["$prefix.used_percent"] = [Math]::Round($usedKb / $totalKb * 100).ToString()
        } else {
            $data["$prefix.used_percent"] = '0'
        }
        $data["$prefix.status"] = if ([int]$data["$prefix.used_percent"] -lt 90) { 'OK' } else { 'WARNING' }
    } catch {
        $data["$prefix.device"] = ''
        $data["$prefix.mount"] = ''
        $data["$prefix.status"] = ''
        $data["$prefix.total_gb"] = ''
        $data["$prefix.used_gb"] = ''
        $data["$prefix.free_gb"] = ''
        $data["$prefix.used_percent"] = ''
    }
}

$envDrive = $env:SystemDrive
if ([string]::IsNullOrEmpty($envDrive)) { $envDrive = 'C:' }

Add-StorageStats -Prefix 'storage.archive' -Path (Join-Path $Context.Config.IceWarpHome 'archive')
Add-StorageStats -Prefix 'storage.install' -Path $Context.Config.IceWarpHome
Add-StorageStats -Prefix 'storage.mail' -Path (Join-Path $Context.Config.IceWarpHome 'mail')
Add-StorageStats -Prefix 'storage.root_fs' -Path $envDrive
Add-StorageStats -Prefix 'storage.root_home' -Path (Join-Path $envDrive 'Users')

return $data