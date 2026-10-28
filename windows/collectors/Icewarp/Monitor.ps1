#Requires -Version 5.1
<#
.SYNOPSIS
Collect System Monitor settings for the health evaluation engine.

.DESCRIPTION
Reads the IceWarp System > Tools > System Monitor settings through the shared
tool.exe wrapper and falls back to the agent configuration when the tool is
unavailable. The collector emits the schema keys used by the monitoring
roll-up and by the admin-email rule:

    monitor.enabled
    monitor.alert_email
    monitor.disk.alert_below_mb
    monitor.cpu.threshold_percent
    monitor.cpu.threshold_minutes
    monitor.memory.alert_below_kb
    monitor.memory.alert_below_gb
    monitor.web_threadpool.alert_seconds

When the System Monitor report address is empty, the primary domain's
D_AdminEmail is used, matching the Linux system_monitor.sh collector.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

function Test-MonitorMissing {
    param([AllowEmptyString()][string]$Value)

    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -ieq 'null' -or $Value -ieq 'N/A')
}

function Get-MonitorSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Default = ''
    )

    $value = [string](Get-IceWarpSetting -Name $Name -Context $Context)
    if (Test-MonitorMissing -Value $value) {
        return $Default
    }
    return $value
}

function Resolve-MonitorAlertEmail {
    $address = Get-MonitorSetting -Name 'C_System_Tools_Monitor_ReportAddress'

    if (-not (Test-MonitorMissing -Value $address)) {
        return $address
    }

    # Fallback: primary domain admin email. The first domain returned by
    # tool.exe is the primary domain in the Windows collectors as well.
    $primaryDomain = ''
    foreach ($domain in @(Get-IceWarpDomainList -Context $Context)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$domain)) {
            $primaryDomain = [string]$domain
            break
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($primaryDomain)) {
        $domainEmail = [string](Get-IceWarpDomainSetting -Domain $primaryDomain -Name 'D_AdminEmail' -Context $Context)
        if (-not (Test-MonitorMissing -Value $domainEmail)) {
            return $domainEmail
        }
    }

    # Last-resort configuration fallback. MailHostname is normally a DNS
    # hostname, so only accept it here when it is actually an email address.
    $configured = [string]$Context.Config.MailHostname
    if ($configured -match '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        return $configured
    }

    return ''
}

$data = [ordered]@{}

# --- Enable flag ---
$data['monitor.enabled'] = Get-MonitorSetting -Name 'C_System_Tools_Monitor_Enable'

# --- Alert address (with primary-domain fallback) ---
$data['monitor.alert_email'] = Resolve-MonitorAlertEmail

# --- Memory thresholds ---
$memoryKb = Get-MonitorSetting -Name 'C_System_Tools_Monitor_FreeMem' -Default ([string]$Context.Config.MonitorMemoryAlertKb)
$data['monitor.memory.alert_below_kb'] = $memoryKb
$memoryKbNumber = 0
if ([int]::TryParse($memoryKb, [ref]$memoryKbNumber) -and $memoryKbNumber -ge 0) {
    # Matches the Linux integer arithmetic: KB / 1024 / 1024.
    $data['monitor.memory.alert_below_gb'] = [string][int][Math]::Truncate($memoryKbNumber / 1024 / 1024)
}

# --- Disk threshold ---
$data['monitor.disk.alert_below_mb'] = Get-MonitorSetting -Name 'C_System_Tools_Monitor_DiskSize' -Default ([string]$Context.Config.MonitorDiskAlertMb)

# --- CPU threshold (the raw tool value is stored as percent * 100) ---
$cpuRaw = [string](Get-IceWarpSetting -Name 'C_System_Tools_Monitor_CPUUsagePerc' -Context $Context)
$cpuNumber = 0
if (Test-MonitorMissing -Value $cpuRaw) {
    # The configuration value is already a percentage, unlike the raw
    # tool.exe value, so it must not be divided by 100.
    $data['monitor.cpu.threshold_percent'] = [string]$Context.Config.MonitorCpuThresholdPercent
} elseif ([int]::TryParse($cpuRaw, [ref]$cpuNumber) -and $cpuNumber -ge 0) {
    $data['monitor.cpu.threshold_percent'] = [string][int][Math]::Truncate($cpuNumber / 100)
} else {
    $data['monitor.cpu.threshold_percent'] = $cpuRaw
}

$data['monitor.cpu.threshold_minutes'] = Get-MonitorSetting -Name 'C_System_Tools_Monitor_CPUUsagePeriod'

# --- Web thread-pool threshold ---
$data['monitor.web_threadpool.alert_seconds'] = Get-MonitorSetting -Name 'C_System_Tools_Monitor_WebThreadPoolThreshold' -Default ([string]$Context.Config.MonitorWebThreadpoolAlertSeconds)

return $data
