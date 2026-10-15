<#
.SYNOPSIS
    Sends an existing CSV report as an email attachment using Microsoft Graph.
.DESCRIPTION
    Uses app-only certificate authentication and direct REST calls. Does not generate
    the report and does not import Microsoft Graph PowerShell modules.
.NOTES
    Intended for CSV attachments up to 3 MB. Keep this script private because the
    PFX password is stored as plaintext.
#>

$ErrorActionPreference = 'Stop'

# ===================== CONFIGURATION: UPDATE THESE VALUES =====================
$TenantId             = 'Tenant'
$ClientId             = 'App ID/Client ID'
$PfxPath              = 'C:\Users\username\Documents\5062x8-pnp\PnPAppCert.pfx'
$PfxPasswordPlainText = 'YourStrongPassword' # Replace with your actual PFX password
$SenderMailbox        = 'username@5062x8.onmicrosoft.com'
$Recipient            = 'username@5062x8.onmicrosoft.com'
$CsvPath              = 'C:\Users\username\Documents\5062x8-pnp\New Microsoft Excel Worksheet.csv'
$EmailSubject         = 'SharePoint Site Inventory Report'
$EmailBody            = 'Please find the SharePoint CSV report attached.'
# ===============================================================================

$certificate = $null
$rsa = $null
$securePfxPassword = $null
$accessToken = $null
$clientAssertion = $null

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

try {
    $requiredValues = @{
        TenantId = $TenantId
        ClientId = $ClientId
        PfxPath = $PfxPath
        PfxPasswordPlainText = $PfxPasswordPlainText
        SenderMailbox = $SenderMailbox
        Recipient = $Recipient
        CsvPath = $CsvPath
    }
    foreach ($item in $requiredValues.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Value)) {
            throw "Configuration value '$($item.Key)' is blank. Update the CONFIGURATION section."
        }
    }
    
    if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
        throw "PFX certificate file was not found: $PfxPath"
    }
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "CSV file was not found: $CsvPath`nRun your report-generation script first and set CsvPath to the exact CSV file."
    }

    $csvFile = Get-Item -LiteralPath $CsvPath
    if ($csvFile.Length -eq 0) { throw "The CSV file is empty: $CsvPath" }
    if ($csvFile.Length -gt 3MB) {
        throw "The CSV is larger than 3 MB. This simple attachment script supports files up to 3 MB; larger files need a Microsoft Graph upload-session approach."
    }

    $securePfxPassword = ConvertTo-SecureString -String $PfxPasswordPlainText -AsPlainText -Force
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $PfxPath,
        $securePfxPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
    )
    if (-not $certificate.HasPrivateKey) { throw 'The PFX certificate does not contain an accessible private key.' }
    if ($certificate.NotBefore -gt (Get-Date)) { throw "The certificate is not valid until $($certificate.NotBefore)." }
    if ($certificate.NotAfter -le (Get-Date)) { throw "The certificate expired on $($certificate.NotAfter)." }

    # Build the certificate-signed JWT client assertion.
    $now = [DateTimeOffset]::UtcNow
    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $thumbprintBytes = [Convert]::FromHexString($certificate.Thumbprint)

    $jwtHeaderObject = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = (ConvertTo-Base64Url -Bytes $thumbprintBytes)
    }
    $jwtHeaderJson = $jwtHeaderObject | ConvertTo-Json -Compress
    $jwtHeader = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jwtHeaderJson))

    $jwtPayloadObject = @{
        aud = $tokenEndpoint
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.ToUnixTimeSeconds()
        exp = $now.AddMinutes(10).ToUnixTimeSeconds()
    }
    $jwtPayloadJson = $jwtPayloadObject | ConvertTo-Json -Compress
    $jwtPayload = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($jwtPayloadJson))

    $unsignedAssertion = "$jwtHeader.$jwtPayload"
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
    if ($null -eq $rsa) { throw 'Could not access the certificate RSA private key.' }

    $signatureBytes = $rsa.SignData(
        [System.Text.Encoding]::UTF8.GetBytes($unsignedAssertion),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $signature = ConvertTo-Base64Url -Bytes $signatureBytes
    $clientAssertion = "$unsignedAssertion.$signature"

    $tokenBody = @{
        client_id = $ClientId
        scope = 'https://graph.microsoft.com/.default'
        grant_type = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion = $clientAssertion
    }

    Write-Host 'Requesting Microsoft Graph access token...' -ForegroundColor Cyan
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint `
        -ContentType 'application/x-www-form-urlencoded' -Body $tokenBody
    $accessToken = $tokenResponse.access_token
    if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'Microsoft identity platform did not return an access token.' }

    $csvBytes = [System.IO.File]::ReadAllBytes($CsvPath)
    $csvBase64 = [Convert]::ToBase64String($csvBytes)
    $attachmentName = [System.IO.Path]::GetFileName($CsvPath)

    $mailPayload = @{
        message = @{
            subject = $EmailSubject
            body = @{ contentType = 'Text'; content = $EmailBody }
            toRecipients = @(@{ emailAddress = @{ address = $Recipient } })
            attachments = @(@{
                '@odata.type' = '#microsoft.graph.fileAttachment'
                name = $attachmentName
                contentType = 'text/csv'
                contentBytes = $csvBase64
            })
        }
        saveToSentItems = $true
    }
    $mailJson = $mailPayload | ConvertTo-Json -Depth 10
    $graphUri = "https://graph.microsoft.com/v1.0/users/$SenderMailbox/sendMail"
    $headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }

    Write-Host "Sending '$attachmentName' from $SenderMailbox to $Recipient..." -ForegroundColor Cyan
    Invoke-RestMethod -Method Post -Uri $graphUri -Headers $headers `
        -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($mailJson))

    Write-Host 'Microsoft Graph accepted the email request successfully (HTTP 202 expected).' -ForegroundColor Green
    Write-Host 'Check the recipient mailbox.' -ForegroundColor Green
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message -ForegroundColor Red
    }
    throw
}
finally {
    if ($null -ne $rsa) { $rsa.Dispose() }
    if ($null -ne $certificate) { $certificate.Dispose() }
    if ($null -ne $securePfxPassword) { $securePfxPassword.Dispose() }
    $accessToken = $null
    $clientAssertion = $null
}
