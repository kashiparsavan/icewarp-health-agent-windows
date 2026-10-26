#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp license status, type, and trial expiration.

.DESCRIPTION
Maps to checklist item "IceWarp Expiration Date". Reads the license status
code, the license type (onpremise/cloud/saas), and the trial expiration
date. The flat C_License_TrialExpire property is read first; if it comes
back empty the license XML is fetched as a cross-check, because the flat
property has been observed to return empty on a server that genuinely has
an active trial license.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$licenseXmlPath = Join-Path $Context.Config.IceWarpHome 'license.xml'
$data['icewarp.license.file_present'] = (Test-Path -LiteralPath $licenseXmlPath -PathType Leaf)

$data['icewarp.license.status_code'] = (Get-IceWarpSetting -Name 'C_LicenseStatus' -Context $Context)
$data['icewarp.license.type'] = (Get-IceWarpSetting -Name 'C_License_Type' -Context $Context)
$trialExpire = (Get-IceWarpSetting -Name 'C_License_TrialExpire' -Context $Context)
$data['icewarp.license.trial_expiration'] = $trialExpire

# Cross-check the trial expiration against the license XML when the flat
# property came back empty. The flat property is a single line; the XML
# holds the real date, so the flat reader can silently destroy it.
if ([string]::IsNullOrWhiteSpace($trialExpire)) {
    try {
        $xml = Invoke-IceWarpTool -ToolPath $Context.Config.ToolPath `
            -Arguments ('display system {0}' -f 'C_License_XML') `
            -TimeoutSeconds ([int]$Context.Config.ToolTimeoutSeconds)
        if ($xml -match '<(?:TrialExpire|TrialExpiration|Expire|ExpirationDate)>([^<]+)') {
            $data['icewarp.license.trial_expiration'] = $Matches[1].Trim()
            $data['icewarp.license.trial_expiration_source'] = 'XML fallback (flat property was empty)'
        }
    } catch {
        Write-AgentLog -Level WARN -Message ('Could not read license XML: {0}' -f $_.Exception.Message)
    }
}

# Keep the old status key for backward compatibility with anything already
# reading it.
if (-not [string]::IsNullOrWhiteSpace($data['icewarp.license.status_code'])) {
    $data['icewarp.license.status'] = 'ok'
} elseif ($data['icewarp.license.file_present']) {
    $data['icewarp.license.status'] = 'installed'
} else {
    $data['icewarp.license.status'] = 'not_found'
}

return $data
