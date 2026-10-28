#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp license status, type, and trial expiration.

.DESCRIPTION
Maps to checklist item "IceWarp Expiration Date". The flat properties are
read through tool.exe. On Windows the license is not necessarily a
license.xml file, so the presence check also enumerates the IceWarp registry
hives. Only 411-key schema keys are emitted.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$licenseXmlPath = Join-Path $Context.Config.IceWarpHome 'license.xml'
$filePresent = (Test-Path -LiteralPath $licenseXmlPath -PathType Leaf)

# On Windows the license may be stored in the registry. Check the known
# hives first, then enumerate one level below HKLM\SOFTWARE and the
# WOW6432Node view for any IceWarp key with a License* value.
if (-not $filePresent) {
    $registryCandidates = @(
        'HKLM:\SOFTWARE\IceWarp Networks\IceWarp Server',
        'HKLM:\SOFTWARE\WOW6432Node\IceWarp Networks\IceWarp Server',
        'HKLM:\SOFTWARE\IceWarp',
        'HKLM:\SOFTWARE\WOW6432Node\IceWarp'
    )
    foreach ($hive in $registryCandidates) {
        if ($filePresent) { break }
        try {
            $properties = Get-ItemProperty -LiteralPath $hive -ErrorAction SilentlyContinue
            if ($properties) {
                foreach ($property in $properties.PSObject.Properties) {
                    if ($property.Name -match '(?i)^license' -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                        $filePresent = $true
                        break
                    }
                }
            }
        } catch {
            # Not this hive, or registry not accessible - skip silently.
        }
    }

    if (-not $filePresent) {
        foreach ($base in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
            if ($filePresent) { break }
            try {
                $iceWarpKeys = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match '(?i)^IceWarp' })
                foreach ($iceWarpKey in $iceWarpKeys) {
                    if ($filePresent) { break }
                    $keysToCheck = @($iceWarpKey) + @(Get-ChildItem -LiteralPath $iceWarpKey.PSPath -Recurse -Depth 1 -ErrorAction SilentlyContinue)
                    foreach ($key in $keysToCheck) {
                        if ($filePresent) { break }
                        try {
                            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                            if (-not $properties) { continue }
                            foreach ($property in $properties.PSObject.Properties) {
                                if ($property.Name -match '(?i)^license' -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                                    $filePresent = $true
                                    break
                                }
                            }
                        } catch { }
                    }
                }
            } catch { }
        }
    }
}
$data['icewarp.license.file_present'] = [bool]$filePresent

$statusCode = (Get-IceWarpSetting -Name 'C_LicenseStatus' -Context $Context)
$data['icewarp.license.status_code'] = $statusCode
$data['icewarp.license.type'] = (Get-IceWarpSetting -Name 'C_License_Type' -Context $Context)

$trialExpire = (Get-IceWarpSetting -Name 'C_License_TrialExpire' -Context $Context)
$data['icewarp.license.trial_expiration'] = $trialExpire

# Cross-check the trial expiration against the license XML when the flat
# property came back empty. Do not emit a source/debug key: it is not part
# of the 411-key schema.
if ([string]::IsNullOrWhiteSpace($trialExpire)) {
    try {
        $xml = Invoke-IceWarpTool -ToolPath $Context.Config.ToolPath `
            -Arguments ('display system {0}' -f 'C_License_XML') `
            -TimeoutSeconds ([int]$Context.Config.ToolTimeoutSeconds)
        if ($xml -match '(?is)<(?:TrialExpire|TrialExpiration|Expire|ExpirationDate)>([^<]+)') {
            $data['icewarp.license.trial_expiration'] = $Matches[1].Trim()
        }
    } catch {
        Write-AgentLog -Level WARN -Message ('Could not read license XML: {0}' -f $_.Exception.Message)
    }
}

# Seat-usage detail is not exposed by tool.exe on Windows either; keep the
# schema's informational keys and the same explanation the Linux collector
# uses.
$data['icewarp.license.seats_info_available'] = $false
$data['icewarp.license.used_seats_note'] = 'not available via tool.exe - use API or database query'

# Keep the legacy status key for anything already reading it.
if (-not [string]::IsNullOrWhiteSpace($statusCode)) {
    $data['icewarp.license.status'] = 'ok'
} elseif ($filePresent) {
    $data['icewarp.license.status'] = 'installed'
} else {
    $data['icewarp.license.status'] = 'not_found'
}

return $data
