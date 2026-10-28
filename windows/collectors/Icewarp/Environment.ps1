#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp environment and installation layout.

.DESCRIPTION
Maps to the icewarp.* environment section of the Linux health.json schema.
The home directory, config directory and the default storage paths are
discovered from the configured IceWarp home. Only the keys that are not
already emitted by other collectors are set here, so the agent does not
emit duplicate keys.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$iceHome = [string]$Context.Config.IceWarpHome
$data['icewarp.home'] = $iceHome
$data['icewarp.config'] = (Join-Path $iceHome 'config')
$data['icewarp.mail.default'] = (Join-Path $iceHome 'mail')
$data['icewarp.logs.default'] = (Join-Path $iceHome 'logs')
$data['icewarp.temp.default'] = (Join-Path $iceHome 'temp')

# On Windows the IceWarp paths are read through tool.exe, so the source is
# always tool_exe. (Linux uses tool.sh and reports tool_sh.)
$data['icewarp.path.source'] = 'tool_exe'

return $data