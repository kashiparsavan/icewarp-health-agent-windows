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

$diskPctText = [string]$Context.Data['storage.root_fs.used_percent']
$diskPct = 0
if ([int]::TryParse($diskPctText -replace '%', [ref]$null)) { }
if ([int]::TryParse(([string]$diskPctText).Replace('%',''), [ref]$diskPct)) {
    if ($diskPct -ge 80) {
        $data['watchdog.disk.status'] = 'WARN'
        $data['watchdog.disk.message'] = "Disk usage is $diskPct% (threshold: 80%)"
    } else {
        $data['watchdog.disk.status'] = 'PASS'
        $data['watchdog.disk.message'] = "Disk usage is $diskPct% (OK)"
    }
} else {
    $data['watchdog.disk.status'] = 'INFO'
    $data['watchdog.disk.message'] = 'Disk usage data not available'
}

$load1Text = [string]$Context.Data['os.cpu.load1']
$coresText = [string]$Context.Data['os.cpu.count']
$load1 = 0.0
$cores = 1
[double]::TryParse($load1Text, [ref]$load1) | Out-Null
[int]::TryParse($coresText, [ref]$cores) | Out-Null
if ($cores -gt 0) {
    $cpuPct = [Math]::Round(($load1 / $cores) * 100, 2)
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

$totalKb = 0
$availKb = 0
[int]::TryParse([string]$Context.Data['os.memory.total_kb'], [ref]$totalKb) | Out-Null
[int]::TryParse([string]$Context.Data['os.memory.available_kb'], [ref]$availKb) | Out-Null
if ($totalKb -gt 0) {
    $memPct = [Math]::Round((($totalKb - $availKb) / $totalKb) * 100, 2)
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

$lastUpdate = [string]$Context.Data['os.last_update_date']
if (-not [string]::IsNullOrEmpty($lastUpdate) -and $lastUpdate -ne 'null') {
    $days = 0
    try {
        $date = [datetime]$lastUpdate
        $days = [int](([datetime]::UtcNow - $date).TotalDays)
    } catch { }
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