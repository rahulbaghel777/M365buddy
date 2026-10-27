# ============================================================
# AZURE AUTOMATION - SHAREPOINT ONLINE SITE CONSUMPTION REPORT
# AZURE ENERGY
# ============================================================
#
# REQUIRED AZURE AUTOMATION VARIABLES:
#   Tenant
#   ClientId
#   PfxBase64
#   PFX Password
#   MailClientId
#   MailClientSecret
#   MailFrom
#   MailTo
#
# APPLICATION PERMISSIONS:
# SharePoint:
#   Sites.FullControl.All - Application
#
# Microsoft Graph:
#   Group.Read.All - Application
#   Mail.Send      - Application
#
# IMPORTANT DESIGN:
#   - SharePoint uses PnP certificate authentication.
#   - PFX password is converted to SecureString because PnP requires it.
#   - M365 Group visibility is preloaded once from Microsoft Graph instead
#     of making one Graph request per group site.
#   - Graph access tokens are refreshed before expiry and immediately after
#     a 401 response.
#   - A single bad site never stops the inventory.
#   - The CSV contains only the requested site detail columns.
#   - No Status/Error columns are written to CSV.
#   - Azure Automation sandbox jobs have a hard 3-hour runtime limit.
#     See notes after the script for the long-running solution.
#
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# ============================================================
# CONFIGURATION
# ============================================================

$AdminUrl = "https://5062x8energy-admin.sharepoint.com"

# CSOM request timeout is per SharePoint HTTP request, NOT the Azure
# Automation job runtime. 120 seconds prevents one bad request from
# waiting indefinitely while still allowing slower sites to respond.
$CsomRequestTimeoutMs = 120000

# Retry settings for SharePoint operations.
$MaxAttempts = 3
$RetryBaseSeconds = 5
$RetryMaxSeconds = 30

# Refresh Graph token 5 minutes before its reported expiry.
$GraphTokenRefreshBufferMinutes = 5

# Standard Graph sendMail file attachments must remain under 3 MB.
# If the CSV is >= 3 MB, the script creates a ZIP and attempts to send
# the ZIP instead. This keeps the existing Mail.Send permission only.
$GraphSmallAttachmentLimitBytes = 3MB

# ============================================================
# RETRY HELPER
# ============================================================
# IMPORTANT:
# Do NOT use Write-Output for logging inside this function.
# Write-Output would become part of the returned object and can turn a
# PnPConnection into System.Object[] when the function is used for a
# connection command.
# ============================================================

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [int]$MaxAttempts = 3,
        [int]$BaseDelaySeconds = 5,
        [int]$MaxDelaySeconds = 30
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            # Do not log successful attempts. A large tenant can execute
            # tens of thousands of successful operations, which can exceed
            # Azure Automation's 1 MiB job-stream limit.
            $Result = & $ScriptBlock
            return $Result
        }
        catch {
            $ErrorMessage = $_.Exception.Message

            if ($Attempt -eq $MaxAttempts) {
                throw "$OperationName failed after $MaxAttempts attempts. Error: $ErrorMessage"
            }

            $Delay = [Math]::Min(
                $MaxDelaySeconds,
                [Math]::Pow(2, $Attempt - 1) * $BaseDelaySeconds
            )

            Write-Warning "$OperationName failed. Retry $Attempt of $MaxAttempts in $Delay seconds. Error: $ErrorMessage"
            Start-Sleep -Seconds ([int]$Delay)
        }
    }
}

# ============================================================
# HTTP STATUS HELPER
# ============================================================

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ErrorRecord
    )

    try {
        if ($null -ne $ErrorRecord.Exception.Response) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    }
    catch {
    }

    try {
        if ($null -ne $ErrorRecord.Exception.InnerException.Response) {
            return [int]$ErrorRecord.Exception.InnerException.Response.StatusCode
        }
    }
    catch {
    }

    if ($ErrorRecord.Exception.Message -match "\b401\b|Unauthorized") {
        return 401
    }

    if ($ErrorRecord.Exception.Message -match "\b429\b|Too Many Requests") {
        return 429
    }

    return 0
}

# ============================================================
# MICROSOFT GRAPH TOKEN
# ============================================================

function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    $TokenUri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"

    $Body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }

    $TokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri $TokenUri `
        -Body $Body `
        -ContentType "application/x-www-form-urlencoded" `
        -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace([string]$TokenResponse.access_token)) {
        throw "Microsoft Graph access token was not returned."
    }

    $ExpiresInSeconds = 2700

    if ($null -ne $TokenResponse.expires_in) {
        try {
            $ExpiresInSeconds = [int]$TokenResponse.expires_in
        }
        catch {
            $ExpiresInSeconds = 2700
        }
    }

    return [PSCustomObject]@{
        AccessToken = [string]$TokenResponse.access_token
        ExpiresAt   = (Get-Date).AddSeconds($ExpiresInSeconds)
    }
}

# ============================================================
# GRAPH TOKEN STATE
# ============================================================

$script:GraphAccessToken = $null
$script:GraphAccessTokenExpiresAt = [datetime]::MinValue

function Refresh-GraphAccessToken {
    Write-Host "Refreshing Microsoft Graph access token..."

    $TokenResult = Invoke-WithRetry `
        -OperationName "Acquire Microsoft Graph access token" `
        -MaxAttempts $MaxAttempts `
        -BaseDelaySeconds $RetryBaseSeconds `
        -MaxDelaySeconds $RetryMaxSeconds `
        -ScriptBlock {
            Get-GraphAccessToken `
                -Tenant $Tenant `
                -ClientId $MailClientId `
                -ClientSecret $MailClientSecret
        }

    $script:GraphAccessToken = $TokenResult.AccessToken
    $script:GraphAccessTokenExpiresAt = $TokenResult.ExpiresAt

    Write-Host "Microsoft Graph access token refreshed successfully."
}

function Get-GraphHeaders {
    $RefreshAt = $script:GraphAccessTokenExpiresAt.AddMinutes(-$GraphTokenRefreshBufferMinutes)

    if (
        [string]::IsNullOrWhiteSpace([string]$script:GraphAccessToken) -or
        (Get-Date) -ge $RefreshAt
    ) {
        Refresh-GraphAccessToken
    }

    return @{
        Authorization = "Bearer $script:GraphAccessToken"
    }
}

# ============================================================
# GRAPH GET WITH TOKEN REFRESH / RETRY
# ============================================================

function Invoke-GraphGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [string]$OperationName = "Microsoft Graph GET"
    )

    $MaxGraphAttempts = 3

    for ($Attempt = 1; $Attempt -le $MaxGraphAttempts; $Attempt++) {
        try {
            $Headers = Get-GraphHeaders

            return Invoke-RestMethod `
                -Method Get `
                -Uri $Uri `
                -Headers $Headers `
                -ErrorAction Stop
        }
        catch {
            $StatusCode = Get-HttpStatusCode -ErrorRecord $_
            $ErrorMessage = $_.Exception.Message

            # 401 is special: the old token must NOT be retried.
            # Get a fresh token and retry the same request.
            if ($StatusCode -eq 401 -and $Attempt -lt $MaxGraphAttempts) {
                Write-Warning "$OperationName returned 401 Unauthorized. Refreshing Graph token before retry $Attempt of $MaxGraphAttempts."
                Refresh-GraphAccessToken
                continue
            }

            # Retry throttling and transient Graph/server errors.
            if (
                $StatusCode -in @(408, 429, 500, 502, 503, 504) -and
                $Attempt -lt $MaxGraphAttempts
            ) {
                $Delay = [Math]::Min(
                    $RetryMaxSeconds,
                    [Math]::Pow(2, $Attempt - 1) * $RetryBaseSeconds
                )

                Write-Warning "$OperationName returned HTTP $StatusCode. Retry $Attempt of $MaxGraphAttempts in $Delay seconds."
                Start-Sleep -Seconds ([int]$Delay)
                continue
            }

            throw "$OperationName failed. HTTP status: $StatusCode. Error: $ErrorMessage"
        }
    }
}

# ============================================================
# PRELOAD M365 GROUP VISIBILITY
# ============================================================
# Microsoft Graph supports up to 999 groups per page. We follow the
# complete @odata.nextLink returned by Graph until all Unified/M365
# groups have been loaded.
# ============================================================

function Get-GraphGroupVisibilityCache {
    $Cache = @{}

    # Use a single Graph collection query rather than one request per site.
    # The URL is deliberately kept as an opaque string. Subsequent pages
    # use exactly the @odata.nextLink returned by Graph.
    $NextUri = 'https://graph.microsoft.com/v1.0/groups?$filter=groupTypes/any(c:c+eq+%27Unified%27)&$select=id,visibility&$top=999'

    $PageNumber = 0

    while (-not [string]::IsNullOrWhiteSpace($NextUri)) {
        $PageNumber++

        Write-Host "Loading Microsoft 365 Groups - Graph page $PageNumber..."

        $Response = Invoke-GraphGet `
            -Uri $NextUri `
            -OperationName "Get Microsoft 365 Group visibility page $PageNumber"

        foreach ($Group in @($Response.value)) {
            if ([string]::IsNullOrWhiteSpace([string]$Group.id)) {
                continue
            }

            $GroupKey = ([string]$Group.id).ToLowerInvariant()
            $Visibility = [string]$Group.visibility

            switch ($Visibility) {
                "Public" {
                    $Cache[$GroupKey] = "Public"
                }

                "Private" {
                    $Cache[$GroupKey] = "Private"
                }

                default {
                    # The report intentionally only exposes Public/Private.
                    $Cache[$GroupKey] = ""
                }
            }
        }

        $NextUri = [string]$Response.'@odata.nextLink'
    }

    return $Cache
}

# ============================================================
# GRAPH MAIL - STANDARD ATTACHMENT
# ============================================================
# Uses only Mail.Send. This avoids the Mail.ReadWrite requirement of
# the large Outlook attachment upload-session API.
# ============================================================

function Send-GraphMailSmallAttachment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [string]$From,

        [Parameter(Mandatory = $true)]
        [string[]]$To,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [string]$AttachmentPath,

        [string]$AttachmentContentType = "text/csv"
    )

    $AttachmentBytes = [System.IO.File]::ReadAllBytes($AttachmentPath)
    $AttachmentBase64 = [System.Convert]::ToBase64String($AttachmentBytes)
    $FileName = [System.IO.Path]::GetFileName($AttachmentPath)

    $MailPayload = @{
        message = @{
            subject = $Subject
           body = @{
    contentType = "HTML"
    content     = $Body
}
            toRecipients = @(
    foreach ($Recipient in $To) {
        $Address = $Recipient.Trim()
 
        if (-not [string]::IsNullOrWhiteSpace($Address)) {
            @{
                emailAddress = @{
                    address = $Address
                }
            }
        }
    }
)
            attachments = @(
                @{
                    "@odata.type" = "#microsoft.graph.fileAttachment"
                    name          = $FileName
                    contentType   = $AttachmentContentType
                    contentBytes  = $AttachmentBase64
                }
            )
        }
        saveToSentItems = $true
    }

    $JsonBody = $MailPayload | ConvertTo-Json -Depth 10

    $SendMailUri =
        "https://graph.microsoft.com/v1.0/users/" +
        [uri]::EscapeDataString($From) +
        "/sendMail"

    Invoke-RestMethod `
        -Method Post `
        -Uri $SendMailUri `
        -Headers @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        } `
        -Body $JsonBody `
        -ErrorAction Stop
}

# ============================================================
# AZURE AUTOMATION VARIABLES
# ============================================================

$Tenant           = Get-AutomationVariable -Name "Tenant"
$ClientId         = Get-AutomationVariable -Name "ClientId"
$PfxBase64        = Get-AutomationVariable -Name "PfxBase64"
$PfxPasswordString = Get-AutomationVariable -Name "PFX Password"
$MailClientId     = Get-AutomationVariable -Name "MailClientId"
$MailClientSecret = Get-AutomationVariable -Name "MailClientSecret"
$MailFrom = Get-AutomationVariable -Name "MailFrom"
$MailToRaw = Get-AutomationVariable -Name "MailTo"
$MailTo = @(
    $MailToRaw -split '[,;\r\n]+' |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

# ============================================================
# VALIDATE VARIABLES
# ============================================================

$RequiredVariables = [ordered]@{
    "Tenant"           = $Tenant
    "ClientId"         = $ClientId
    "PfxBase64"        = $PfxBase64
    "PFX Password"     = $PfxPasswordString
    "MailClientId"     = $MailClientId
    "MailClientSecret" = $MailClientSecret
    "MailFrom"         = $MailFrom
    "MailTo"           = $MailTo
}

foreach ($Variable in $RequiredVariables.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$Variable.Value)) {
        throw "Azure Automation variable '$($Variable.Key)' is empty."
    }
}

# ============================================================
# MODULE CHECK
# ============================================================

Import-Module PnP.PowerShell -DisableNameChecking -ErrorAction Stop

$PnPCommand = Get-Command Connect-PnPOnline -ErrorAction Stop
$TenantCommand = Get-Command Get-PnPTenantSite -ErrorAction Stop
$WebCommand = Get-Command Get-PnPWeb -ErrorAction Stop
$UserCommand = Get-Command Get-PnPUser -ErrorAction Stop
$GroupCommand = Get-Command Get-PnPGroup -ErrorAction Stop
$GroupMemberCommand = Get-Command Get-PnPGroupMember -ErrorAction Stop

$LoadedPnPModule = Get-Module PnP.PowerShell -ListAvailable |
    Sort-Object Version -Descending |
    Select-Object -First 1

Write-Host "PnP.PowerShell available: $($LoadedPnPModule.Version)"
Write-Host "PnP cmdlets validated successfully."

# ============================================================
# CONVERT PFX PASSWORD TO SECURESTRING
# ============================================================
# PnP -CertificatePassword is SecureString. Do not pass the Automation
# variable directly as a normal string.
# ============================================================

$PfxPassword = ConvertTo-SecureString `
    -String $PfxPasswordString `
    -AsPlainText `
    -Force

# ============================================================
# OUTPUT PATH
# ============================================================

$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$TempPath = [System.IO.Path]::GetTempPath()
$CsvPath = Join-Path `
    -Path $TempPath `
    -ChildPath "5062x8Energy-SPOSiteConsumption_$DateStamp.csv"

$ZipPath = Join-Path `
    -Path $TempPath `
    -ChildPath "5062x8Energy-SPOSiteConsumption_$DateStamp.zip"

# ============================================================
# CONNECT TO SHAREPOINT ADMIN CENTER
# ============================================================

Write-Host ""
Write-Host "Connecting to SharePoint Admin Center..."

$AdminConnection = Invoke-WithRetry `
    -OperationName "Connect to SharePoint Admin Center" `
    -MaxAttempts $MaxAttempts `
    -BaseDelaySeconds $RetryBaseSeconds `
    -MaxDelaySeconds $RetryMaxSeconds `
    -ScriptBlock {
        Connect-PnPOnline `
            -Url $AdminUrl `
            -ClientId $ClientId `
            -CertificateBase64Encoded $PfxBase64 `
            -CertificatePassword $PfxPassword `
            -Tenant $Tenant `
            -ReturnConnection `
            -ErrorAction Stop
    }

if ($null -eq $AdminConnection) {
    throw "Could not establish SharePoint Admin connection."
}

if ($AdminConnection.GetType().FullName -notlike "*PnPConnection*") {
    throw "SharePoint Admin connection is not a valid PnPConnection. Returned type: $($AdminConnection.GetType().FullName)"
}

try {
    if ($null -ne $AdminConnection.Context) {
        $AdminConnection.Context.RequestTimeout = $CsomRequestTimeoutMs
    }
}
catch {
    Write-Warning "Could not set SharePoint Admin CSOM request timeout. Continuing."
}

Write-Host "Connected to SharePoint Admin Center."

# ============================================================
# GET ALL SHAREPOINT SITES
# ============================================================

Write-Host ""
Write-Host "Retrieving SharePoint Online sites..."

$Sites = Invoke-WithRetry `
    -OperationName "Get SharePoint tenant sites" `
    -MaxAttempts $MaxAttempts `
    -BaseDelaySeconds $RetryBaseSeconds `
    -MaxDelaySeconds $RetryMaxSeconds `
    -ScriptBlock {
        Get-PnPTenantSite `
            -Connection $AdminConnection `
            -Detailed `
            -ErrorAction Stop
    }

$Sites = @($Sites)
$TotalSites = $Sites.Count

Write-Host "Total SharePoint sites found: $TotalSites" -ForegroundColor Green

if ($TotalSites -eq 0) {
    throw "No SharePoint sites were returned."
}

# ============================================================
# ACQUIRE GRAPH TOKEN AND PRELOAD GROUP VISIBILITY
# ============================================================

Write-Host ""
Write-Host "Acquiring Microsoft Graph token and loading M365 Group visibility..."

Refresh-GraphAccessToken

$GroupVisibilityCache = Get-GraphGroupVisibilityCache

Write-Host "Microsoft 365 Groups loaded into visibility cache: $($GroupVisibilityCache.Count)" -ForegroundColor Green

# ============================================================
# TENANT STORAGE SUMMARY
# ============================================================
# Get the organization-level SharePoint storage quota once. The total
# consumed value is calculated from the tenant site inventory already
# retrieved above, so no per-site storage calls are required.
# ============================================================

$TenantStorageQuotaGB = 0
$TenantStorageConsumedGB = 0

try {
    $TenantProperties = Invoke-WithRetry `
        -OperationName "Get SharePoint tenant storage properties" `
        -MaxAttempts $MaxAttempts `
        -BaseDelaySeconds $RetryBaseSeconds `
        -MaxDelaySeconds $RetryMaxSeconds `
        -ScriptBlock {
            Get-PnPTenant `
                -Connection $AdminConnection `
                -ErrorAction Stop
        }

    if ($null -ne $TenantProperties.StorageQuota) {
        # SharePoint tenant storage quota is returned in MB.
        $TenantStorageQuotaGB = [math]::Round(
            ([double]$TenantProperties.StorageQuota / 1024),
            2
        )
    }
}
catch {
    Write-Warning "Could not retrieve tenant-level SharePoint storage quota: $($_.Exception.Message)"
}

$TenantStorageConsumedMB = 0
foreach ($TenantSite in $Sites) {
    if ($null -ne $TenantSite.StorageUsageCurrent) {
        $TenantStorageConsumedMB += [double]$TenantSite.StorageUsageCurrent
    }
}

$TenantStorageConsumedGB = [math]::Round(
    ($TenantStorageConsumedMB / 1024),
    2
)

$TenantStorageAvailableGB = 0
if ($TenantStorageQuotaGB -gt 0) {
    $TenantStorageAvailableGB = [math]::Round(
        [math]::Max(0, ($TenantStorageQuotaGB - $TenantStorageConsumedGB)),
        2
    )
}

# SharePoint reports storage in binary GB (1024 GB = 1 TB).
# These values are calculated from the automatically retrieved tenant
# StorageQuota and the site inventory; nothing is hard-coded.
$TenantStorageQuotaTB = [math]::Round(($TenantStorageQuotaGB / 1024), 2)
$TenantStorageConsumedTB = [math]::Round(($TenantStorageConsumedGB / 1024), 2)
$TenantStorageAvailableTB = [math]::Round(($TenantStorageAvailableGB / 1024), 2)

# Count M365 group sites from the already-loaded GroupId -> Visibility
# cache. This includes sites even if a later per-site SharePoint call fails.
$TotalPrivateSites = 0
$TotalPublicGroupSites = 0

foreach ($TenantSite in $Sites) {
    if ($null -eq $TenantSite.GroupId) {
        continue
    }

    try {
        $TenantGroupId = [guid]$TenantSite.GroupId
        if ($TenantGroupId -eq [guid]::Empty) {
            continue
        }

        $TenantGroupIdString = $TenantGroupId.ToString().ToLowerInvariant()

        if ($GroupVisibilityCache.ContainsKey($TenantGroupIdString)) {
            switch ([string]$GroupVisibilityCache[$TenantGroupIdString]) {
                "Private" { $TotalPrivateSites++ }
                "Public"  { $TotalPublicGroupSites++ }
            }
        }
    }
    catch {
        # Ignore invalid/non-group IDs.
    }
}

Write-Host "Tenant storage capacity : $TenantStorageQuotaGB GB" -ForegroundColor Green
Write-Host "Tenant storage available : $TenantStorageAvailableGB GB" -ForegroundColor Green
Write-Host "Tenant storage consumed : $TenantStorageConsumedGB GB" -ForegroundColor Green
Write-Host "Total private sites     : $TotalPrivateSites" -ForegroundColor Green
Write-Host "Total public group sites: $TotalPublicGroupSites" -ForegroundColor Green

if ($GroupVisibilityCache.Count -eq 0) {
    Write-Warning "Graph returned zero Microsoft 365 Groups. Verify MailClientId is the app with Group.Read.All Application permission and admin consent."
}

# ============================================================
# RESULTS
# ============================================================

$Results = New-Object System.Collections.Generic.List[object]
$FailedSites = New-Object System.Collections.Generic.List[object]

# ============================================================
# PROCESS SITES
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "STARTING SITE PROCESSING"
Write-Host "============================================================"
Write-Host ""

$Index = 0

foreach ($Site in $Sites) {
    $Index++

    $PercentComplete = [math]::Round(($Index / $TotalSites) * 100, 2)

    Write-Progress `
        -Activity "Processing SharePoint Online sites" `
        -Status "[$Index/$TotalSites] $($Site.Url)" `
        -PercentComplete $PercentComplete

    # Keep the Azure Automation output stream small. The progress bar
    # shows every site; text logging is emitted periodically and on errors.
    if ($Index -eq 1 -or ($Index % 50) -eq 0 -or $Index -eq $TotalSites) {
        Write-Host "[$Index/$TotalSites] Processing: $($Site.Url)"
    }

    $SiteConnection = $null

    try {
        # --------------------------------------------------------
        # RESET PER-SITE VARIABLES
        # --------------------------------------------------------

        $SiteTitle = ""
        $SiteCreatedDate = ""
        $LastActivityDate = ""
        $SiteOwners = @()
        $SPOwners = ""
        $SiteAdmins = @()
        $SiteCollectionAdmins = ""
        $Office365Visibility = ""
        $StorageUsedGB = 0
        $GroupId = $null
        $HasGroupId = $false

        # --------------------------------------------------------
        # CONNECT TO SITE
        # --------------------------------------------------------

        $SiteConnection = Invoke-WithRetry `
            -OperationName "Connect to $($Site.Url)" `
            -MaxAttempts $MaxAttempts `
            -BaseDelaySeconds $RetryBaseSeconds `
            -MaxDelaySeconds $RetryMaxSeconds `
            -ScriptBlock {
                Connect-PnPOnline `
                    -Url $Site.Url `
                    -ClientId $ClientId `
                    -CertificateBase64Encoded $PfxBase64 `
                    -CertificatePassword $PfxPassword `
                    -Tenant $Tenant `
                    -ReturnConnection `
                    -ErrorAction Stop
            }

        if ($null -eq $SiteConnection) {
            throw "Site connection was not returned."
        }

        if ($SiteConnection.GetType().FullName -notlike "*PnPConnection*") {
            throw "Invalid PnPConnection returned for site."
        }

        try {
            if ($null -ne $SiteConnection.Context) {
                $SiteConnection.Context.RequestTimeout = $CsomRequestTimeoutMs
            }
        }
        catch {
            # Do not fail the site because timeout assignment failed.
        }

        # --------------------------------------------------------
        # WEB DETAILS
        # --------------------------------------------------------

        $Web = Invoke-WithRetry `
            -OperationName "Get web details for $($Site.Url)" `
            -MaxAttempts $MaxAttempts `
            -BaseDelaySeconds $RetryBaseSeconds `
            -MaxDelaySeconds $RetryMaxSeconds `
            -ScriptBlock {
                Get-PnPWeb `
                    -Includes Title,Created,AssociatedOwnerGroup `
                    -Connection $SiteConnection `
                    -ErrorAction Stop
            }

        if ($null -ne $Web) {
            $SiteTitle = [string]$Web.Title

            if ($null -ne $Web.Created) {
                $SiteCreatedDate = ([datetime]$Web.Created).ToString("yyyy-MM-dd")
            }

            # LastContentModifiedDate is the SharePoint site-level activity
            # timestamp exposed by the tenant site inventory. It is kept as
            # a site property rather than making another per-site API call.
            if ($null -ne $Site.LastContentModifiedDate) {
                $LastActivityDate = ([datetime]$Site.LastContentModifiedDate).ToString("yyyy-MM-dd")
            }
        }

        # --------------------------------------------------------
        # STORAGE
        # --------------------------------------------------------
        # Storage is already available from Get-PnPTenantSite.
        # No additional storage API call is made.
        # --------------------------------------------------------

        if ($null -ne $Site.StorageUsageCurrent) {
            $StorageUsedGB = [math]::Round(
                ([double]$Site.StorageUsageCurrent / 1024),
                2
            )
        }


        # --------------------------------------------------------
        # SITE COLLECTION ADMINS
        # --------------------------------------------------------
        # Keep the original Get-PnPUser approach for compatibility and
        # because this version was faster in the user's environment.
        # --------------------------------------------------------

        $SiteAdmins = Invoke-WithRetry `
            -OperationName "Get site admins for $($Site.Url)" `
            -MaxAttempts $MaxAttempts `
            -BaseDelaySeconds $RetryBaseSeconds `
            -MaxDelaySeconds $RetryMaxSeconds `
            -ScriptBlock {
                Get-PnPUser `
                    -Connection $SiteConnection `
                    -ErrorAction Stop |
                Where-Object {
                    $_.IsSiteAdmin -eq $true
                }
            }

        $SiteAdmins = @($SiteAdmins)

        if ($SiteAdmins.Count -gt 0) {
            $SiteCollectionAdmins = (
                $SiteAdmins |
                ForEach-Object {
                    if (-not [string]::IsNullOrWhiteSpace($_.Email)) {
                        $_.Email
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($_.LoginName)) {
                        $_.LoginName
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($_.Title)) {
                        $_.Title
                    }
                } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Sort-Object -Unique
            ) -join "; "
        }

        # --------------------------------------------------------
        # SHAREPOINT OWNER GROUP
        # --------------------------------------------------------
        # IMPORTANT:
        # Do NOT call Get-PnPGroup -AssociatedOwnerGroup here.
        # Some site collections (for example App Catalog / certain
        # classic or system sites) have no AssociatedOwnerGroup.
        # In those cases PnP can throw a null-object error instead
        # of simply returning $null.
        #
        # AssociatedOwnerGroup is already loaded with Get-PnPWeb above,
        # so use the property directly. This also avoids an additional
        # SharePoint request for every site.
        # --------------------------------------------------------

        $OwnerGroup = $null

        if ($null -ne $Web) {
            try {
                if ($null -ne $Web.AssociatedOwnerGroup) {
                    $OwnerGroup = $Web.AssociatedOwnerGroup
                }
            }
            catch {
                # A missing AssociatedOwnerGroup is valid. Keep owners blank.
                $OwnerGroup = $null
            }
        }

        # --------------------------------------------------------
        # SHAREPOINT OWNER GROUP MEMBERS
        # --------------------------------------------------------

        if ($null -ne $OwnerGroup -and $OwnerGroup.Id -gt 0) {
            try {
                $SiteOwners = Invoke-WithRetry `
                    -OperationName "Get SharePoint Owner Group members for $($Site.Url)" `
                    -MaxAttempts $MaxAttempts `
                    -BaseDelaySeconds $RetryBaseSeconds `
                    -MaxDelaySeconds $RetryMaxSeconds `
                    -ScriptBlock {
                        Get-PnPGroupMember `
                            -Group $OwnerGroup `
                            -Connection $SiteConnection `
                            -ErrorAction Stop
                    }

                $SiteOwners = @($SiteOwners)
            }
            catch {
                $SiteOwners = @()
            }
        }
        else {
            $SiteOwners = @()
        }

        if ($SiteOwners.Count -gt 0) {
            $SPOwners = (
                $SiteOwners |
                ForEach-Object {
                    if (-not [string]::IsNullOrWhiteSpace($_.Email)) {
                        $_.Email
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($_.LoginName)) {
                        $_.LoginName
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($_.Title)) {
                        $_.Title
                    }
                } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Sort-Object -Unique
            ) -join "; "
        }

        # --------------------------------------------------------
        # GROUP ID
        # --------------------------------------------------------

        if ($null -ne $Site.GroupId) {
            try {
                $GroupId = [guid]$Site.GroupId

                if ($GroupId -ne [guid]::Empty) {
                    $HasGroupId = $true
                }
            }
            catch {
                $HasGroupId = $false
                $GroupId = $null
            }
        }

        # --------------------------------------------------------
        # M365 GROUP VISIBILITY
        # --------------------------------------------------------
        # Normal case: O(1) hashtable lookup; no Graph request.
        # Fallback: if a GroupId was not present in the preload cache,
        # perform one direct GET. This handles eventual-consistency cases.
        # --------------------------------------------------------

        if ($HasGroupId) {
            $GroupIdString = $GroupId.ToString().ToLowerInvariant()

            if ($GroupVisibilityCache.ContainsKey($GroupIdString)) {
                $Office365Visibility = [string]$GroupVisibilityCache[$GroupIdString]
            }
            else {
                try {
                    $GroupUri =
                        "https://graph.microsoft.com/v1.0/groups/" +
                        $GroupIdString +
                        "?`$select=visibility"

                    $GroupResponse = Invoke-GraphGet `
                        -Uri $GroupUri `
                        -OperationName "Get M365 Group visibility for $($Site.Url)"

                    switch ([string]$GroupResponse.visibility) {
                        "Public" {
                            $Office365Visibility = "Public"
                        }

                        "Private" {
                            $Office365Visibility = "Private"
                        }

                        default {
                            $Office365Visibility = ""
                        }
                    }

                    $GroupVisibilityCache[$GroupIdString] = $Office365Visibility
                }
                catch {
                    # Visibility is optional for the report. Do not fail the
                    # entire site because a group object cannot be resolved.
                    Write-Warning "Could not retrieve M365 Group visibility for $($Site.Url): $($_.Exception.Message)"
                    $Office365Visibility = ""
                    $GroupVisibilityCache[$GroupIdString] = ""
                }
            }
        }

        # --------------------------------------------------------
        # RESULT - REQUESTED SITE DETAIL COLUMNS
        # --------------------------------------------------------

        [void]$Results.Add(
            [PSCustomObject]@{
                SiteName             = $SiteTitle
                SiteUrl              = $Site.Url
                SiteCreatedDate      = $SiteCreatedDate
                LastActivityDate     = $LastActivityDate
                SPOwners             = $SPOwners
                SiteCollectionAdmins = $SiteCollectionAdmins
                Office365Visibility  = $Office365Visibility
                StorageUsedGB        = $StorageUsedGB
            }
        )
    }
    catch {
        $FailureMessage = $_.Exception.Message

        Write-Warning ""
        Write-Warning "FAILED SITE: $($Site.Url)"
        Write-Warning "ERROR: $FailureMessage"
        Write-Warning "Continuing with next site..."
        Write-Warning ""

        [void]$FailedSites.Add(
            [PSCustomObject]@{
                Url   = $Site.Url
                Error = $FailureMessage
            }
        )
    }
    finally {
        if ($null -ne $SiteConnection) {
            try {
                Disconnect-PnPOnline `
                    -Connection $SiteConnection `
                    -ErrorAction SilentlyContinue
            }
            catch {
                # Ignore disconnect failures.
            }
        }
    }
}

Write-Progress -Activity "Processing SharePoint Online sites" -Completed

# ============================================================
# EXPORT CSV
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "SITE PROCESSING COMPLETE"
Write-Host "============================================================"
Write-Host "Successful sites : $($Results.Count)"
Write-Host "Failed sites     : $($FailedSites.Count)"

if ($Results.Count -eq 0) {
    throw "No successful site records were generated. CSV will not be created."
}

Write-Host ""
Write-Host "Exporting CSV..."

$Results |
    Export-Csv `
        -Path $CsvPath `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host "CSV created: $CsvPath"

# ============================================================
# PREPARE EMAIL ATTACHMENT
# ============================================================

$AttachmentPath = $CsvPath
$AttachmentContentType = "text/csv"
$AttachmentWasZipped = $false

$CsvSizeBytes = (Get-Item $CsvPath).Length
$CsvSizeMB = [math]::Round(($CsvSizeBytes / 1MB), 2)

Write-Host "CSV size: $CsvSizeMB MB"

# If the CSV is >= 3 MB, compress it. This avoids using the Graph
# upload-session API, which requires Mail.ReadWrite for message upload
# sessions. The existing application only needs Mail.Send.
if ($CsvSizeBytes -ge $GraphSmallAttachmentLimitBytes) {
    Write-Host "CSV is 3 MB or larger. Creating ZIP attachment..."

    if (Test-Path $ZipPath) {
        Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
    }

    Compress-Archive `
        -Path $CsvPath `
        -DestinationPath $ZipPath `
        -CompressionLevel Optimal `
        -Force

    $ZipSizeBytes = (Get-Item $ZipPath).Length
    $ZipSizeMB = [math]::Round(($ZipSizeBytes / 1MB), 2)

    Write-Host "ZIP size: $ZipSizeMB MB"

    if ($ZipSizeBytes -ge $GraphSmallAttachmentLimitBytes) {
        throw "The CSV is $CsvSizeMB MB and the compressed ZIP is $ZipSizeMB MB. The current Mail.Send-only design cannot send an attachment this large. Either grant Mail.ReadWrite and use an upload session, or store the report externally and email a link."
    }

    $AttachmentPath = $ZipPath
    $AttachmentContentType = "application/zip"
    $AttachmentWasZipped = $true
}

# ============================================================
# SEND EMAIL
# ============================================================

$EmailSubject =
    "5062x8 Energy - SharePoint Online Site Consumption Report - $(Get-Date -Format 'yyyy-MM-dd')"

$EmailBody = @"

Hello Team,<br><br>

Please find attached the latest SharePoint Online Site Consumption Report for 5062x8 Energy.<br><br>

Report Date: $(Get-Date -Format "yyyy-MM-dd")<br><br>

<b>SharePoint Tenant Summary</b><br>
-------------------------<br>
Total SharePoint Storage Provided by Microsoft: $TenantStorageQuotaTB TB<br>
Total Available Storage: $TenantStorageAvailableTB TB<br>
Total Storage Consumed: $TenantStorageConsumedTB TB<br>
Total Sites: $TotalSites<br>
Total Private Sites: $TotalPrivateSites<br>
Total Public Group Sites: $TotalPublicGroupSites<br><br>

Regards,<br>
SharePoint Automation
"@

try {
    Write-Host "Sending report email..."

    # Refresh token if the long inventory caused the token to approach expiry.
    Refresh-GraphAccessToken

    Invoke-WithRetry `
        -OperationName "Send SharePoint report email" `
        -MaxAttempts $MaxAttempts `
        -BaseDelaySeconds $RetryBaseSeconds `
        -MaxDelaySeconds $RetryMaxSeconds `
        -ScriptBlock {
            Send-GraphMailSmallAttachment `
                -AccessToken $script:GraphAccessToken `
                -From $MailFrom `
                -To $MailTo `
                -Subject $EmailSubject `
                -Body $EmailBody `
                -AttachmentPath $AttachmentPath `
                -AttachmentContentType $AttachmentContentType
        }

    Write-Host "Email sent successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to send email."
    Write-Warning "Error: $($_.Exception.Message)"

    if ($_.ErrorDetails.Message) {
        Write-Warning "Graph response: $($_.ErrorDetails.Message)"
    }

    throw
}

# ============================================================
# CLEANUP
# ============================================================

try {
    if ($AttachmentWasZipped -and (Test-Path $ZipPath)) {
        Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
    }
}
catch {
    # Ignore cleanup failures.
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "RUNBOOK COMPLETE"
Write-Host "============================================================"
Write-Host "Total sites discovered : $TotalSites"
Write-Host "Successful records     : $($Results.Count)"
Write-Host "Failed sites           : $($FailedSites.Count)"
Write-Host "Tenant storage capacity: $TenantStorageQuotaGB GB"
Write-Host "Tenant storage available: $TenantStorageAvailableGB GB"
Write-Host "Tenant storage consumed: $TenantStorageConsumedGB GB"
Write-Host "Total private sites    : $TotalPrivateSites"
Write-Host "Public group sites     : $TotalPublicGroupSites"
Write-Host "CSV                    : $CsvPath"
Write-Host "============================================================"

if ($FailedSites.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed sites (console only):"
    Write-Host "------------------------------------------------------------"

    foreach ($FailedSite in $FailedSites) {
        Write-Host "$($FailedSite.Url)"
        Write-Host "  $($FailedSite.Error)"
    }

    Write-Host "------------------------------------------------------------"
}
