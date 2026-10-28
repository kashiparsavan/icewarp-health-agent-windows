#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp antivirus update status.

.DESCRIPTION
Maps to the icewarp.antivirus.* section of the Linux health.json schema.
The update date, version and size are read through the shared IceWarp tool
wrapper first; when that is empty the Sophos update.json "ide" field is used
as a fallback, and when neither is available the source is marked not_found.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['icewarp.antivirus.db_version'] = ''
$data['icewarp.antivirus.last_update_size_bytes'] = ''

$lastUpdate = (Get-IceWarpSetting -Name 'C_AV_Info_UpdateDate' -Context $Context)
$version = (Get-IceWarpSetting -Name 'C_AV_Info_UpdateVersion' -Context $Context)
$size = (Get-IceWarpSetting -Name 'C_AV_Info_UpdateSize' -Context $Context)

if (-not [string]::IsNullOrEmpty($lastUpdate)) {
    $data['icewarp.antivirus.last_update'] = $lastUpdate
    $data['icewarp.antivirus.last_update_source'] = 'tool_sh'
    $data['icewarp.antivirus.db_version'] = $version
    $data['icewarp.antivirus.last_update_size_bytes'] = $size
    return $data
}

# Fallback: Sophos update.json "ide" field (epoch seconds).
#
# On Windows the Sophos directory is not always under the IceWarp home
# (it frequently lives under the per-user or program-data directory), so
# probe several candidate locations before giving up.
$sophosPath = $null
$candidatePaths = @()
$candidatePaths += (Join-Path $Context.Config.IceWarpHome 'sophos')
foreach ($envRoot in @($env:APPDATA, $env:PROGRAMDATA, $env:USERPROFILE, $env:PUBLIC)) {
    if (-not [string]::IsNullOrEmpty($envRoot)) {
        $candidatePaths += (Join-Path (Join-Path $envRoot 'IceWarp') 'sophos')
    }
}
foreach ($candidate in $candidatePaths) {
    if (-not [string]::IsNullOrEmpty($candidate) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'update.json') -PathType Leaf)) {
        $sophosPath = $candidate
        break
    }
}

$ideTs = ''
if ($sophosPath) {
    $jsonPath = Join-Path $sophosPath 'update.json'
    if (Test-Path -LiteralPath $jsonPath -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $jsonPath -Raw -ErrorAction Stop
            if ($raw -match '"ide"\s*:\s*(\d+)') {
                $ideTs = $Matches[1]
            }
        } catch { }
    }
}

if (-not [string]::IsNullOrEmpty($ideTs)) {
    try {
        $epoch = [long]$ideTs
        $date = ([datetime]'1970-01-01').AddSeconds($epoch).ToString('yyyy-MM-dd HH:mm:ss')
        $data['icewarp.antivirus.last_update'] = $date
    } catch {
        $data['icewarp.antivirus.last_update'] = $ideTs
    }
    $data['icewarp.antivirus.last_update_source'] = 'sophos_update_json_ide'
} else {
    $data['icewarp.antivirus.last_update'] = ''
    $data['icewarp.antivirus.last_update_source'] = 'not_found'
}

# DB version file, when present.
$avdbPath = if ($sophosPath) { Join-Path $sophosPath 'avdbinfo.dat' } else { $null }
if ($avdbPath -and (Test-Path -LiteralPath $avdbPath -PathType Leaf)) {
    try {
        $raw = [System.IO.File]::ReadAllText($avdbPath)
        $clean = ($raw -replace '[\r\n\0]').Substring(0, [Math]::Min(100, $raw.Length))
        $data['icewarp.antivirus.db_version'] = $clean
    } catch { }
}

return $data