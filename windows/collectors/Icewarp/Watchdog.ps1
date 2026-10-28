#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp watchdog settings and derived watchdog summaries.

.DESCRIPTION
Maps to the watchdog.* section of the Linux health.json schema. Service
watchdog flags are read through the shared IceWarp tool wrapper; the
cpu/disk/memory/os_update summaries are computed from the already
collected os.* and storage.* values.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['watchdog.smtp'] = (Get-IceWarpSetting -Name 'C_System_Tools_WatchDog_SMTP' -Context $Context)
$data['watchdog.pop3'] = (Get-IceWarpSetting -Name 'C_System_Tools_WatchDog_POP3' -Context $Context)
$data['watchdog.im'] = (Get-IceWarpSetting -Name 'C_System_Tools_WatchDog_IM' -Context $Context)
$data['watchdog.gw'] = (Get-IceWarpSetting -Name 'C_System_Tools_Watchdog_GW' -Context $Context)
$data['watchdog.control'] = (Get-IceWarpSetting -Name 'C_System_Tools_Watchdog_Control' -Context $Context)
$data['watchdog.interval_minutes'] = (Get-IceWarpSetting -Name 'C_System_Tools_Watchdog_Int' -Context $Context)
$data['watchdog.check_protocols'] = (Get-IceWarpSetting -Name 'C_System_Tools_Watchdog_Check_Protocols' -Context $Context)
$data['watchdog.check_iplist'] = (Get-IceWarpSetting -Name 'C_System_Tools_Watchdog_Check_IPList' -Context $Context)

$data['watchdog.remoteserver.enable'] = (Get-IceWarpSetting -Name 'C_System_Tools_RemoteServer_Enable' -Context $Context)
$data['watchdog.remoteserver.down_after_minutes'] = (Get-IceWarpSetting -Name 'C_System_Tools_RemoteServer_MoreThan' -Context $Context)
$data['watchdog.remoteserver.report_email'] = (Get-IceWarpSetting -Name 'C_System_Tools_RemoteServer_Email' -Context $Context)
$data['watchdog.remoteserver.notify_when_back'] = (Get-IceWarpSetting -Name 'C_System_Tools_RemoteServer_NotifyAgain' -Context $Context)

# --- Derived watchdog summaries (mirror collectors/watchdog/watchdog_percentage.sh) ---
#
# NOTE: each collector runs in an isolated PowerShell runspace, so
# $Context.Data does NOT contain the os.* / storage.* values emitted by
# other collectors. The summaries below are computed directly from the
# local system instead of reading other collectors' output.

function Get-WatchdogCpuLoad {
    [CmdletBinding()]
    param()
    # Win32_Processor.LoadPercentage is already a 0-100 percentage (per the
    # MSDN contract), so it is used directly - unlike the Linux 1-min load
    # average, it must NOT be divided by the core count and multiplied by 100.
    $load = 0.0
    $cores = 1
    try {
        $procs = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $cores = [Math]::Max(1, $procs.Count)
        $sum = 0.0
        $n = 0
        foreach ($p in $procs) {
            if ($p.LoadPercentage -ge 0) {
                $sum += [double]$p.LoadPercentage
                $n++
            }
        }
        if ($n -gt 0) {
            $load = [Math]::Round($sum / $n, 2)
        }
    } catch { }
    return [psobject]@{ Load1 = $load; Cores = $cores }
}


function Get-WatchdogDiskUsage {
    [CmdletBinding()]
    param()
    $pct = 0
    $ok = $false
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop |
            Where-Object { $_.DeviceID -eq 'C:' } | Select-Object -First 1
        if ($disk -and $disk.TotalSize -gt 0) {
            $pct = [Math]::Round((($disk.TotalSize - $disk.FreeSpace) / $disk.TotalSize) * 100, 2)
            $ok = $true
        }
    } catch { }
    return [psobject]@{ Percent = $pct; Ok = $ok }
}


function Get-WatchdogMemoryUsage {
    [CmdletBinding()]
    param()
    # Win32_OperatingSystem reports physical memory in kilobytes, so the
    # values are used directly (no /1024 conversion).
    $totalKb = 0
    $availKb = 0
    $ok = $false
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os -and $os.TotalPhysicalMemory) {
            $totalKb = [long]$os.TotalPhysicalMemory
            $availKb = [long]$os.FreePhysicalMemory
            $ok = $totalKb -gt 0
        }
    } catch { }
    return [psobject]@{ TotalKb = $totalKb; AvailableKb = $availKb; Ok = $ok }
}


function Get-WatchdogOsUpdateDays {
    [CmdletBinding()]
    param()
    $days = -1
    try {
        $hotfix = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
            Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
        if ($hotfix -and $hotfix.InstalledOn) {
            $date = [datetime]$hotfix.InstalledOn
            $days = [int](([datetime]::UtcNow - $date).TotalDays)
        }
    } catch { }
    return $days
}

# --- Disk ---
$disk = Get-WatchdogDiskUsage
if ($disk.Ok) {
    if ($disk.Percent -ge 80) {
        $data['watchdog.disk.status'] = 'WARN'
        $data['watchdog.disk.message'] = "Disk usage is $disk.Percent% (threshold: 80%)"
    } else {
        $data['watchdog.disk.status'] = 'PASS'
        $data['watchdog.disk.message'] = "Disk usage is $disk.Percent% (OK)"
    }
} else {
    $data['watchdog.disk.status'] = 'INFO'
    $data['watchdog.disk.message'] = 'Disk usage data not available'
}

# --- CPU ---
# Win32_Processor.LoadPercentage is already a 0-100 percentage, so it is
# used directly (the Linux 1-min load average would need /cores * 100, but
# the Windows counter does not).
$cpu = Get-WatchdogCpuLoad
if ($cpu.Cores -gt 0) {
    $cpuPct = [Math]::Round($cpu.Load1, 2)
    if ($cpuPct -gt 50) {
        $data['watchdog.cpu.status'] = 'WARN'
        $data['watchdog.cpu.message'] = "CPU load (1-min) is $cpuPct% (threshold: 50%)"
    } else {
        $data['watchdog.cpu.status'] = 'PASS'
        $data['watchdog.cpu.message'] = "CPU load (1-min) is $cpuPct% (OK)"
    }
} else {
    $data['watchdog.cpu.status'] = 'INFO'
    $data['watchdog.cpu.message'] = 'CPU count not available'
}

# --- Memory ---
$mem = Get-WatchdogMemoryUsage
if ($mem.Ok) {
    $memPct = [Math]::Round((($mem.TotalKb - $mem.AvailableKb) / $mem.TotalKb) * 100, 2)
    if ($memPct -gt 60) {
        $data['watchdog.memory.status'] = 'WARN'
        $data['watchdog.memory.message'] = "Memory usage is $memPct% (threshold: 60%)"
    } else {
        $data['watchdog.memory.status'] = 'PASS'
        $data['watchdog.memory.message'] = "Memory usage is $memPct% (OK)"
    }
} else {
    $data['watchdog.memory.status'] = 'INFO'
    $data['watchdog.memory.message'] = 'Memory data not available'
}

# --- OS update ---
$days = Get-WatchdogOsUpdateDays
if ($days -ge 0) {
    if ($days -gt 3) {
        $data['watchdog.os_update.status'] = 'WARN'
        $data['watchdog.os_update.message'] = "OS last update was $days days ago (threshold: 3 days)"
    } else {
        $data['watchdog.os_update.status'] = 'PASS'
        $data['watchdog.os_update.message'] = "OS last update was $days days ago (OK)"
    }
} else {
    $data['watchdog.os_update.status'] = 'INFO'
    $data['watchdog.os_update.message'] = 'OS last update date not available'
}

$warnCount = 0
foreach ($k in @('watchdog.disk.status', 'watchdog.cpu.status', 'watchdog.memory.status', 'watchdog.os_update.status')) {
    if ($data[$k] -eq 'WARN') { $warnCount++ }
}
$data['watchdog.summary.warnings'] = $warnCount
if ($warnCount -eq 0) {
    $data['watchdog.summary.overall'] = 'PASS'
} else {
    $data['watchdog.summary.overall'] = 'WARN'
}

return $data