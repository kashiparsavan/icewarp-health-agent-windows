#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp storage paths.

.DESCRIPTION
Maps to the icewarp.path.* section of the Linux health.json schema. The
paths are read through the shared IceWarp tool wrapper first (the live
configuration) and fall back to the configured IceWarp home defaults when
tool.exe is unavailable. The source flag records which path was used.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$iceHome = [string]$Context.Config.IceWarpHome
$defaultMail = Join-Path $iceHome 'mail'
$defaultTemp = Join-Path $iceHome 'temp'
$defaultLogs = Join-Path $iceHome 'logs'
$defaultArchive = Join-Path $iceHome 'archive'

$toolMail = (Get-IceWarpSetting -Name 'C_System_Storage_Dir_MailPath' -Context $Context)
$toolTemp = (Get-IceWarpSetting -Name 'C_System_Storage_Dir_TempPath' -Context $Context)
$toolLogs = (Get-IceWarpSetting -Name 'C_System_Storage_Dir_LogPath' -Context $Context)
$toolArchive = (Get-IceWarpSetting -Name 'C_System_Tools_AutoArchive_Path' -Context $Context)

$source = if ([string]::IsNullOrEmpty($toolMail)) { 'config_default' } else { 'tool_sh' }

$data['icewarp.path.mail'] = if ([string]::IsNullOrEmpty($toolMail)) { $defaultMail } else { $toolMail }
$data['icewarp.path.temp'] = if ([string]::IsNullOrEmpty($toolTemp)) { $defaultTemp } else { $toolTemp }
$data['icewarp.path.logs'] = if ([string]::IsNullOrEmpty($toolLogs)) { $defaultLogs } else { $toolLogs }
$data['icewarp.path.archive'] = if ([string]::IsNullOrEmpty($toolArchive)) { $defaultArchive } else { $toolArchive }
$data['icewarp.path.source'] = $source

return $data