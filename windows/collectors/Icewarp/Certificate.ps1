#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp TLS certificate status.

.DESCRIPTION
Maps to the icewarp.ssl.* section of the Linux health.json schema. A live
check against the mail hostname on port 443 is performed with .NET SslStream
(the Windows equivalent of openssl s_client). When that fails, the
configured certificate path is used as a fallback data point.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['icewarp.ssl.days_left'] = ''
$data['icewarp.ssl.expiration'] = ''

$hostname = [string]$Context.Config.MailHostname
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = [string]$Context.Config.MailDomain
}
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = 'localhost'
}
$hostname = (ConvertTo-AgentHostName -Value $hostname)
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = 'localhost'
}

$data['icewarp.ssl.live_check_host'] = "${hostname}:443"

$certPath = ''
try {
    $certPath = (Get-IceWarpSetting -Name 'C_System_Ssl_CertFile' -Context $Context)
} catch { }
if ([string]::IsNullOrEmpty($certPath)) {
    $certPath = (Join-Path $Context.Config.IceWarpHome 'data\cert.pem')
}
$data['icewarp.ssl.cert_path'] = $certPath

$expiration = ''
$daysLeft = $null
$source = 'live check failed (no TLS listener on ${hostname}:443, or handshake failed)'

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcp.ConnectAsync($hostname, 443)
    if ($connectTask.Wait(2000)) {
        try {
            $stream = $tcp.GetStream()
            $ssl = New-Object System.Net.Security.SslStream($stream, $false,
                { param($sender, $certificate, $chain, $sslPolicyErrors) return $true })
            $authTask = $ssl.AuthenticateAsClientAsync($hostname)
            if ($authTask.Wait(2000)) {
                $cert = $ssl.RemoteCertificate
                if ($null -ne $cert) {
                    $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
                    $expiration = $x509.GetExpirationString()
                    $now = [datetime]::UtcNow
                    $expDate = $x509.NotAfter.ToUniversalTime()
                    $daysLeft = [int](($expDate - $now).TotalDays)
                    $source = "live (SslStream ${hostname}:443)"
                }
            }
        } catch { }
        finally {
            if ($ssl) { $ssl.Dispose() }
            if ($stream) { $stream.Dispose() }
        }
    }
    $tcp.Close()
} catch { }

if (-not [string]::IsNullOrEmpty($expiration)) {
    $data['icewarp.ssl.expiration'] = $expiration
    $data['icewarp.ssl.source'] = $source
    if ($null -ne $daysLeft) {
        $data['icewarp.ssl.days_left'] = [int]$daysLeft
    }
} elseif (Test-Path -LiteralPath $certPath -PathType Leaf) {
    try {
        $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
        $expiration = $x509.GetExpirationString()
        $data['icewarp.ssl.expiration'] = $expiration
        $data['icewarp.ssl.source'] = "local file only (live check failed): $certPath"
        $daysLeft = [int](($x509.NotAfter.ToUniversalTime() - [datetime]::UtcNow).TotalDays)
        $data['icewarp.ssl.days_left'] = [int]$daysLeft
    } catch {
        $data['icewarp.ssl.source'] = $source
    }
} else {
    $data['icewarp.ssl.source'] = $source
}

return $data