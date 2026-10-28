#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp version and basic Windows host information.

.DESCRIPTION
Maps to the general.* and icewarp.version / icewarp.tool / icewarp.installed
sections of the Linux health.json schema. The agent framework injects
agent.*, general.company and general.technician itself, so this collector
does not touch those.
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

# general.date - current timestamp, matching the Linux date format.
$data['general.date'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# general.os.* - Windows equivalents of /etc/os-release. The Linux schema
# stores general.os.version as a JSON number (e.g. 9.8), so emit the Windows
# major.minor pair ("10.0") rather than the three-part build string, which
# could not be coerced to a number.
$os = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch { }
if ($os) {
    $data['general.os.name'] = [string]$os.Caption
    $data['general.os.pretty'] = [string]$os.Caption

    $versionParts = @(([string]$os.Version).Split('.'))
    $major = 0
    $minor = 0
    if ($versionParts.Count -ge 1 -and [int]::TryParse($versionParts[0], [ref]$major)) {
        if ($versionParts.Count -ge 2 -and [int]::TryParse($versionParts[1], [ref]$minor)) {
            $data['general.os.version'] = ('{0}.{1}' -f $major, $minor)
        } else {
            $data['general.os.version'] = [string]$major
        }
    } else {
        $data['general.os.version'] = ''
    }
} else {
    $data['general.os.name'] = [string]$env:OS
    $data['general.os.pretty'] = [string]$env:OS
    $data['general.os.version'] = ''
}

return $data
