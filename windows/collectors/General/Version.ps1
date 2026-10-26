#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp version and basic Windows host information.

.DESCRIPTION
Maps to the general.* and icewarp.version / icewarp.tool / icewarp.installed
sections of the Linux health.json schema. Produces exactly the same keys
the Linux collectors produce, nothing more and nothing less. The agent
framework injects agent.hostname, agent.time and agent.version itself,
so this collector does not touch those.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$iceWarpVersion = (Get-IceWarpSetting -Name 'C_Version' -Context $Context)
$toolPath = [string]$Context.Config.ToolPath
$toolAvailable = (Test-IceWarpTool -ToolPath $toolPath)

# general.icewarp.version - the human-readable version string.
$data['general.icewarp.version'] = $iceWarpVersion

# icewarp.version - the same value under the icewarp.* namespace.
$data['icewarp.version'] = $iceWarpVersion

# icewarp.tool / icewarp.tool.exists - the tool path and whether it is
# present, mirroring the Linux env collector.
$data['icewarp.tool'] = $toolPath
$data['icewarp.tool.exists'] = [bool]$toolAvailable

# icewarp.installed - true when the IceWarp home directory exists.
$data['icewarp.installed'] = (Test-Path -LiteralPath $Context.Config.IceWarpHome -PathType Container)

# general.company - from the configuration file.
$data['general.company'] = [string]$Context.Config.CompanyName

# general.date - current timestamp, matching the Linux date format.
$data['general.date'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# general.os.* - Windows equivalents of /etc/os-release.
$os = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch { }
if ($os) {
    $data['general.os.name'] = [string]$os.Caption
    $data['general.os.pretty'] = [string]$os.Caption
    $data['general.os.version'] = [string]$os.Version
} else {
    $data['general.os.name'] = [string]$env.OS
    $data['general.os.pretty'] = [string]$env.OS
    $data['general.os.version'] = ''
}

return $data