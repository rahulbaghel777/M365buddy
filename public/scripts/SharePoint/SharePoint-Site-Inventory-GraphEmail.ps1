# =====================================================
# SHAREPOINT ONLINE SITE INVENTORY / USAGE REPORT
# =====================================================
#
# Purpose:
#   - Inventory SharePoint Online site collections
#   - Use tenant-level site metadata for site inventory
#   - Retrieve Root Web creation date
#   - Identify Microsoft 365 Group-connected sites by GroupId
#   - Retrieve ONLY M365 Group Public / Private visibility
#   - Retrieve SharePoint site admins
#   - Retrieve SharePoint associated owner group members
#   - Export ONLY the approved CSV columns
#   - Email the report with storage utilization summary using Microsoft Graph app-only auth
#
# FINAL CSV COLUMNS:
#
#   1. SiteName
#   2. SiteUrl
#   3. SiteType
#   4. Template
#   5. WebCreatedDate
#   6. Office365Visibility
#   7. StorageGB
#   8. SiteCollectionAdmins
#   9. SPOwners
#
# REMOVED FROM REPORT:
#
#   Status
#   Successful Sites
#   Failed Sites
#   M365GroupOwners
#   M365GroupConnected
#   M365GroupVisibility
#   M365GroupName
#   M365GroupCreatedDate
#   GroupId
#   SiteAccessType
#   IsTeamsConnected
#   IsTeamsChannelConnected
#   TeamsChannelType
#   LastUserModifiedDate
#   LastContentModifiedDate
#   SiteCreatedDate
#
# =====================================================


# =====================================================
# CONFIGURATION
# =====================================================

$Tenant = "domain.onmicrosoft.com"

$ClientId = "84ede95e-a45a-427c-862c-9afef6132839"

$PfxPath =
    "D:\PnPCert\PnPAppCert.pfx"


# -----------------------------------------------------
# CERTIFICATE PASSWORD
# -----------------------------------------------------
#
# IMPORTANT:
# Replace the placeholder with your actual certificate
# password or preferably retrieve it from your approved
# secret-management solution.
#
# -----------------------------------------------------

# Use a secret store for production. Do not publish a real password in a public repository.
$PfxPasswordPlainText = 'YourStrongPassword'
$PfxPassword = ConvertTo-SecureString -String $PfxPasswordPlainText -AsPlainText -Force


# -----------------------------------------------------
# SHAREPOINT ADMIN CENTER
# -----------------------------------------------------

$AdminCenterUrl =
    "https://domain-admin.sharepoint.com"


# -----------------------------------------------------
# SHAREPOINT TENANT ROOT URL
# -----------------------------------------------------

$SharePointRootUrl =
    "https://domain.sharepoint.com"


# -----------------------------------------------------
# OUTPUT DIRECTORY
# -----------------------------------------------------

$OutputDirectory =
    "D:\"


# -----------------------------------------------------
# UNIQUE REPORT FILE NAME
# -----------------------------------------------------
#
# Date + time prevents an old CSV from being confused
# with a newly generated report during same-day reruns.
#
# -----------------------------------------------------

$DateStamp =
    Get-Date -Format "yyyyMMdd"

$OutputCsv =
    Join-Path `
        $OutputDirectory `
        "-SPOSiteConsumption_$DateStamp.csv"


# -----------------------------------------------------
# PARALLEL PROCESSING
# -----------------------------------------------------

$ThrottleLimit = 3


# =====================================================
# MICROSOFT GRAPH EMAIL CONFIGURATION
# =====================================================

# Sender must be a mailbox that the app is allowed to send as.
$From = 'rahul@5062x8.onmicrosoft.com'
$To = @('rahul@5062x8.onmicrosoft.com')

# App registration must have Microsoft Graph Mail.Send APPLICATION permission
# with admin consent. Exchange application-access restrictions must allow $From.
# The script uses Graph REST directly and does not import Graph PowerShell modules.

# =====================================================
# PRE-CHECKS
# =====================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host "SharePoint Online Usage Report" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""


# -----------------------------------------------------
# CHECK CERTIFICATE
# -----------------------------------------------------

if (-not (Test-Path $PfxPath))
{
    throw "Certificate file not found: $PfxPath"
}


# -----------------------------------------------------
# CREATE OUTPUT DIRECTORY
# -----------------------------------------------------

if (-not (Test-Path $OutputDirectory))
{
    New-Item `
        -Path $OutputDirectory `
        -ItemType Directory `
        -Force |
        Out-Null
}


# -----------------------------------------------------
# LOAD PnP POWER SHELL
# -----------------------------------------------------

Import-Module `
    PnP.PowerShell `
    -DisableNameChecking `
    -ErrorAction Stop


# =====================================================
# CONNECT TO SHAREPOINT ADMIN CENTER
# =====================================================

Write-Host "Connecting to SharePoint Admin Center..." `
    -ForegroundColor Cyan

Connect-PnPOnline `
    -Url $AdminCenterUrl `
    -ClientId $ClientId `
    -Tenant $Tenant `
    -CertificatePath $PfxPath `
    -CertificatePassword $PfxPassword `
    -ErrorAction Stop


Write-Host "Connected successfully." `
    -ForegroundColor Green


# =====================================================
# GET TENANT-LEVEL SITE INVENTORY
# =====================================================
#
# Get-PnPTenantSite -Detailed is used as the primary
# source for:
#
#   Site Title
#   Site URL
#   Template
#   GroupId
#   StorageUsageCurrent
#
# We intentionally DO NOT use:
#
#   LastContentModifiedDate
#   LastUserModifiedDate
#   IsTeamsConnected
#   IsTeamsChannelConnected
#   TeamsChannelType
#
# =====================================================

Write-Host ""
Write-Host "Retrieving SharePoint site inventory..." `
    -ForegroundColor Cyan


$sites =
    Get-PnPTenantSite `
        -Detailed `
        -ErrorAction Stop


# -----------------------------------------------------
# FILTER INVALID / REDIRECT SITES
# -----------------------------------------------------

$sites = @(
    $sites |
        Where-Object {
            $_.Url -and
            $_.Template -ne "REDIRECTSITE#0"
        }
)


Write-Host ""
Write-Host "Total Sites Found: $($sites.Count)" `
    -ForegroundColor Green


# =====================================================
# TENANT STORAGE
# =====================================================
#
# IMPORTANT:
#
# DO NOT CHANGE THIS CALCULATION.
#
# SharePoint StorageQuota is reported in MB.
#
# Existing calculation:
#
#     StorageQuota / 1024 = GB
#
# =====================================================

Write-Host ""
Write-Host "Retrieving tenant storage allocation..." `
    -ForegroundColor Cyan


$TenantInfo =
    Get-PnPTenant `
        -ErrorAction Stop


$TotalAllocatedStorageGB =
    [Math]::Round(
        ($TenantInfo.StorageQuota / 1024),
        2
    )


Write-Host `
    "Allocated Storage : $TotalAllocatedStorageGB GB" `
    -ForegroundColor Cyan


# =====================================================
# PROCESS SITES
# =====================================================

Write-Host ""
Write-Host "Processing SharePoint sites..." `
    -ForegroundColor Cyan

Write-Host `
    "Throttle Limit    : $ThrottleLimit" `
    -ForegroundColor DarkGray

Write-Host ""


$results =
    $sites |
    ForEach-Object -Parallel {

        $site = $_


        # =================================================
        # COPY VARIABLES INTO PARALLEL RUNSPACE
        # =================================================

        $ClientId =
            $using:ClientId

        $Tenant =
            $using:Tenant

        $PfxPath =
            $using:PfxPath

        $PfxPassword =
            $using:PfxPassword

        $SharePointRootUrl =
            $using:SharePointRootUrl


        # =================================================
        # LOAD PnP MODULE IN PARALLEL RUNSPACE
        # =================================================

        try
        {
            Import-Module `
                PnP.PowerShell `
                -DisableNameChecking `
                -ErrorAction Stop
        }
        catch
        {
            # Continue. If module is already available,
            # PnP commands may still work.
        }


        # =================================================
        # INITIALIZE VARIABLES
        # =================================================

        $siteName =
            $null

        $siteType =
            "Other / Custom Site"

        $web =
            $null

        $siteConnection =
            $null

        $SiteAdmins =
            @()

        $Owners =
            @()

        $Group =
            $null

        $GroupId =
            $null

        $HasGroupId =
            $false

        $Office365Visibility =
            ""

        $WebCreatedDate =
            $null

        $storageGB =
            $null


        # =================================================
        # MAIN SITE PROCESSING
        # =================================================

        try
        {

            # =============================================
            # GROUP ID
            # =============================================

            $GroupId =
                $site.GroupId


            $HasGroupId = (
                $null -ne $GroupId -and
                $GroupId -ne [Guid]::Empty
            )


            # =============================================
            # SITE NAME
            # =============================================

            if ($site.Title)
            {
                $siteName =
                    $site.Title
            }
            else
            {
                $siteName =
                    $site.Url.Split("/")[-1]

                if (-not $siteName)
                {
                    $siteName =
                        "Unknown Site"
                }
            }


            # =============================================
            # STORAGE
            # =============================================
            #
            # DO NOT CHANGE THIS CALCULATION.
            #
            # StorageUsageCurrent is reported in MB.
            #
            # =============================================

            if ($null -ne $site.StorageUsageCurrent)
            {
                $storageGB =
                    [Math]::Round(
                        ($site.StorageUsageCurrent / 1024),
                        2
                    )
            }


            # =============================================
            # CONNECT TO INDIVIDUAL SITE
            # =============================================
            #
            # Required for:
            #
            #   Root Web Created date
            #   Site Collection Administrators
            #   SharePoint Owners
            #
            # =============================================

            try
            {
                $siteConnection =
                    Connect-PnPOnline `
                        -Url $site.Url `
                        -ClientId $ClientId `
                        -Tenant $Tenant `
                        -CertificatePath $PfxPath `
                        -CertificatePassword $PfxPassword `
                        -ReturnConnection `
                        -ErrorAction Stop
            }
            catch
            {
                $siteConnection =
                    $null
            }


            # =============================================
            # ROOT WEB INFORMATION
            # =============================================

            if ($siteConnection)
            {
                try
                {
                    $web =
                        Get-PnPWeb `
                            -Connection $siteConnection `
                            -Includes Title,Created `
                            -ErrorAction Stop


                    if ($web)
                    {
                        $WebCreatedDate =
                            $web.Created


                        if ($web.Title)
                        {
                            $siteName =
                                $web.Title
                        }
                    }
                }
                catch
                {
                    $WebCreatedDate =
                        $null
                }
            }


            # =============================================
            # SHAREPOINT SITE COLLECTION ADMINS
            # =============================================
            #
            # If no administrator is returned,
            # the final CSV value remains blank.
            #
            # =============================================

            if ($siteConnection)
            {
                try
                {
                    $SiteAdmins =
                        Get-PnPUser `
                            -Connection $siteConnection `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.IsSiteAdmin
                        } |
                        Select-Object `
                            -ExpandProperty Email
                }
                catch
                {
                    $SiteAdmins =
                        @()
                }
            }


            # =============================================
            # SHAREPOINT ASSOCIATED OWNER GROUP
            # =============================================
            #
            # This is SharePoint's associated Owner Group.
            #
            # M365 Group Owners are NOT retrieved.
            #
            # If there are no owners,
            # the final CSV value remains blank.
            #
            # =============================================

            if ($siteConnection)
            {
                try
                {
                    $OwnerGroup =
                        Get-PnPGroup `
                            -AssociatedOwnerGroup `
                            -Connection $siteConnection `
                            -ErrorAction Stop


                    if ($OwnerGroup -and $OwnerGroup.Id)
                    {
                        $Owners =
                            Get-PnPGroupMember `
                                -Identity $OwnerGroup `
                                -Connection $siteConnection `
                                -ErrorAction Stop |
                            Select-Object `
                                -ExpandProperty Email
                    }
                }
                catch
                {
                    $Owners =
                        @()
                }
            }


            # =============================================
            # M365 GROUP VISIBILITY
            # =============================================
            #
            # GroupId indicates an underlying Microsoft 365
            # Group.
            #
            # ONLY Public / Private visibility is retrieved.
            #
            # We do NOT retrieve:
            #
            #   Group Name
            #   Group Email
            #   Group Creation Date
            #   Group Owners
            #   Group ID in the final CSV
            #
            # =============================================

            if ($HasGroupId)
            {
                try
                {
                    $Group =
                        Get-PnPMicrosoft365Group `
                            -Identity $GroupId `
                            -ErrorAction Stop


                    if ($Group)
                    {
                        switch ([string]$Group.Visibility)
                        {

                            "Public"
                            {
                                $Office365Visibility =
                                    "Public"
                            }


                            "Private"
                            {
                                $Office365Visibility =
                                    "Private"
                            }


                            default
                            {
                                $Office365Visibility =
                                    ""
                            }
                        }
                    }
                }
                catch
                {
                    $Office365Visibility =
                        ""
                }
            }


            # =============================================
            # SITE TYPE CLASSIFICATION
            # =============================================

            if (
                $site.Url.TrimEnd("/") -eq
                $SharePointRootUrl
            )
            {
                $siteType =
                    "Root Site"
            }


            elseif (
                $site.Template -eq
                "TEAMCHANNEL#0"
            )
            {
                $siteType =
                    "Teams Private Channel Site"
            }


            elseif (
                $site.Template -eq
                "TEAMCHANNEL#1"
            )
            {
                $siteType =
                    "Teams Shared Channel Site"
            }


            elseif ($HasGroupId)
            {
                if (
                    $site.Template -eq
                    "GROUP#0"
                )
                {
                    $siteType =
                        "Microsoft 365 Group / Teams Site"
                }
                else
                {
                    $siteType =
                        "Microsoft 365 Group Site"
                }
            }


            else
            {
                switch -Regex ($site.Template)
                {

                    "^SITEPAGEPUBLISHING#0$"
                    {
                        $siteType =
                            "Communication Site"

                        break
                    }


                    "^STS#3$"
                    {
                        $siteType =
                            "Modern Team Site"

                        break
                    }


                    "^STS#0$"
                    {
                        $siteType =
                            "Classic Team Site"

                        break
                    }


                    "^EDISC#0$"
                    {
                        $siteType =
                            "eDiscovery Center"

                        break
                    }


                    "^BDR#0$"
                    {
                        $siteType =
                            "Document Center"

                        break
                    }


                    "^SRCHCEN#0$"
                    {
                        $siteType =
                            "Search Center"

                        break
                    }


                    "^PROJECTSITE#0$"
                    {
                        $siteType =
                            "Project Site"

                        break
                    }


                    "^BLANKINTERNET#0$"
                    {
                        $siteType =
                            "Publishing Portal"

                        break
                    }


                    "^SPSPERS#10$"
                    {
                        $siteType =
                            "OneDrive Site"

                        break
                    }


                    default
                    {
                        $siteType =
                            "Other / Custom Site"
                    }
                }
            }


            # =============================================
            # FINAL SITE OBJECT
            # =============================================
            #
            # IMPORTANT:
            #
            # ONLY these 9 properties are created.
            #
            # There is NO Status property.
            # There is NO Error property.
            # There is NO Success property.
            # There is NO Group Owner property.
            #
            # =============================================

            [PSCustomObject]@{

                SiteName =
                    $siteName


                SiteUrl =
                    $site.Url


                SiteType =
                    $siteType


                Template =
                    $site.Template


                WebCreatedDate =
                    if ($WebCreatedDate)
                    {
                        $WebCreatedDate.ToString(
                            "yyyy-MM-dd"
                        )
                    }
                    else
                    {
                        ""
                    }


                Office365Visibility =
                    $Office365Visibility


                StorageGB =
                    $storageGB


                SiteCollectionAdmins =
                    (
                        $SiteAdmins |
                        Sort-Object -Unique
                    ) -join "; "


                SPOwners =
                    (
                        $Owners |
                        Sort-Object -Unique
                    ) -join "; "
            }

        }
        catch
        {

            # =============================================
            # FALLBACK
            # =============================================
            #
            # The site remains in the report using the
            # tenant-level information that is available.
            #
            # IMPORTANT:
            #
            # NO Status or Error field is created.
            #
            # =============================================


            if (-not $siteName)
            {
                if ($site.Title)
                {
                    $siteName =
                        $site.Title
                }
                else
                {
                    $siteName =
                        $site.Url.Split("/")[-1]
                }
            }


            # =============================================
            # STORAGE
            # =============================================

            if ($null -ne $site.StorageUsageCurrent)
            {
                $storageGB =
                    [Math]::Round(
                        ($site.StorageUsageCurrent / 1024),
                        2
                    )
            }


            # =============================================
            # SITE TYPE
            # =============================================

            if (
                $site.Url.TrimEnd("/") -eq
                $SharePointRootUrl
            )
            {
                $siteType =
                    "Root Site"
            }


            elseif (
                $site.Template -eq
                "TEAMCHANNEL#0"
            )
            {
                $siteType =
                    "Teams Private Channel Site"
            }


            elseif (
                $site.Template -eq
                "TEAMCHANNEL#1"
            )
            {
                $siteType =
                    "Teams Shared Channel Site"
            }


            elseif (
                $null -ne $site.GroupId -and
                $site.GroupId -ne [Guid]::Empty
            )
            {
                if (
                    $site.Template -eq
                    "GROUP#0"
                )
                {
                    $siteType =
                        "Microsoft 365 Group / Teams Site"
                }
                else
                {
                    $siteType =
                        "Microsoft 365 Group Site"
                }
            }


            else
            {
                switch -Regex ($site.Template)
                {

                    "^SITEPAGEPUBLISHING#0$"
                    {
                        $siteType =
                            "Communication Site"

                        break
                    }


                    "^STS#3$"
                    {
                        $siteType =
                            "Modern Team Site"

                        break
                    }


                    "^STS#0$"
                    {
                        $siteType =
                            "Classic Team Site"

                        break
                    }


                    "^EDISC#0$"
                    {
                        $siteType =
                            "eDiscovery Center"

                        break
                    }


                    "^BDR#0$"
                    {
                        $siteType =
                            "Document Center"

                        break
                    }


                    "^SRCHCEN#0$"
                    {
                        $siteType =
                            "Search Center"

                        break
                    }


                    "^PROJECTSITE#0$"
                    {
                        $siteType =
                            "Project Site"

                        break
                    }


                    "^BLANKINTERNET#0$"
                    {
                        $siteType =
                            "Publishing Portal"

                        break
                    }


                    "^SPSPERS#10$"
                    {
                        $siteType =
                            "OneDrive Site"

                        break
                    }


                    default
                    {
                        $siteType =
                            "Other / Custom Site"
                    }
                }
            }


            # =============================================
            # FALLBACK OBJECT
            # =============================================
            #
            # EXACTLY THE SAME 9 PROPERTIES.
            #
            # =============================================

            [PSCustomObject]@{

                SiteName =
                    $siteName


                SiteUrl =
                    $site.Url


                SiteType =
                    $siteType


                Template =
                    $site.Template


                WebCreatedDate =
                    ""


                Office365Visibility =
                    ""


                StorageGB =
                    $storageGB


                SiteCollectionAdmins =
                    ""


                SPOwners =
                    ""
            }
        }

    } `
    -ThrottleLimit $ThrottleLimit


# =====================================================
# RESULT SUMMARY
# =====================================================

Write-Host ""
Write-Host "Results Count = $($results.Count)" `
    -ForegroundColor Cyan


# =====================================================
# STORAGE SUMMARY
# =====================================================
#
# IMPORTANT:
#
# DO NOT CHANGE THE STORAGE SUM CALCULATION.
#
# =====================================================

$StorageSum =
    (
        $results |
        Measure-Object `
            -Property StorageGB `
            -Sum
    ).Sum


if ($null -eq $StorageSum)
{
    $StorageSum =
        0
}


$TotalStorageUsedGB =
    [Math]::Round(
        $StorageSum,
        2
    )


# =====================================================
# OVER-UTILIZATION CALCULATION
# =====================================================
#
# Formula:
#
# Over Utilized Storage =
#     Used Storage - Allocated Storage
#
# Over Utilized % =
#     (Over Utilized Storage / Allocated Storage) * 100
#
# Example:
#
# Allocated = 157 TB
# Over-used = 358 TB
#
# 358 / 157 * 100 = 228.03%
#
# =====================================================

$OverUtilizedStorageGB =
    [Math]::Round(
        (
            $TotalStorageUsedGB -
            $TotalAllocatedStorageGB
        ),
        2
    )


# -----------------------------------------------------
# Prevent negative "over utilization"
# -----------------------------------------------------

if ($OverUtilizedStorageGB -lt 0)
{
    $OverUtilizedStorageGB =
        0
}


$OverUtilizedPercent =

    if ($TotalAllocatedStorageGB -gt 0)
    {
        [Math]::Round(
            (
                (
                    $OverUtilizedStorageGB /
                    $TotalAllocatedStorageGB
                ) * 100
            ),
            2
        )
    }
    else
    {
        0
    }


# =====================================================
# STORAGE DISPLAY VALUES IN TB
# =====================================================
#
# The actual storage calculations remain in GB.
# TB values are only for email/display purposes.
#
# 1024 GB = 1 TB
#
# =====================================================

$TotalStorageUsedTB =
    [Math]::Round(
        ($TotalStorageUsedGB / 1024),
        2
    )


$TotalAllocatedStorageTB =
    [Math]::Round(
        ($TotalAllocatedStorageGB / 1024),
        2
    )


$OverUtilizedStorageTB =
    [Math]::Round(
        ($OverUtilizedStorageGB / 1024),
        2
    )


# =====================================================
# M365 GROUP SUMMARY
# =====================================================

$M365GroupCount =
    (
        $results |
        Where-Object {
            $_.Office365Visibility -eq "Public" -or
            $_.Office365Visibility -eq "Private"
        }
    ).Count


$M365PublicCount =
    (
        $results |
        Where-Object {
            $_.Office365Visibility -eq "Public"
        }
    ).Count


$M365PrivateCount =
    (
        $results |
        Where-Object {
            $_.Office365Visibility -eq "Private"
        }
    ).Count


# =====================================================
# FINAL CSV OBJECT
# =====================================================
#
# THIS IS THE IMPORTANT PROTECTION AGAINST OLD COLUMNS.
#
# We do NOT export $results directly.
#
# We create a brand-new object containing ONLY the
# approved 9 columns.
#
# Therefore columns such as:
#
#   Status
#   Success
#   Failed
#   M365GroupOwners
#   GroupId
#   TeamsChannelType
#
# CANNOT appear in the CSV.
#
# =====================================================

$FinalResults =
    $results |
    Select-Object `
        SiteName,
        SiteUrl,
        SiteType,
        Template,
        WebCreatedDate,
        Office365Visibility,
        StorageGB,
        SiteCollectionAdmins,
        SPOwners |
    Sort-Object `
        SiteType,
        SiteName


# =====================================================
# CSV VALIDATION
# =====================================================
#
# Validate the actual object properties before writing
# the file.
#
# =====================================================

$ExpectedColumns = @(
    "SiteName"
    "SiteUrl"
    "SiteType"
    "Template"
    "WebCreatedDate"
    "Office365Visibility"
    "StorageGB"
    "SiteCollectionAdmins"
    "SPOwners"
)


$ActualColumns =
    @(
        $FinalResults |
        Select-Object -First 1 |
        Get-Member -MemberType NoteProperty |
        Select-Object -ExpandProperty Name
    )


if ($FinalResults.Count -gt 0)
{

    $UnexpectedColumns =
        $ActualColumns |
        Where-Object {
            $_ -notin $ExpectedColumns
        }


    if ($UnexpectedColumns.Count -gt 0)
    {
        throw `
            "Unexpected CSV columns detected: $($UnexpectedColumns -join ', ')"
    }


    $MissingColumns =
        $ExpectedColumns |
        Where-Object {
            $_ -notin $ActualColumns
        }


    if ($MissingColumns.Count -gt 0)
    {
        throw `
            "Required CSV columns missing: $($MissingColumns -join ', ')"
    }
}


# =====================================================
# EXPORT CSV
# =====================================================

Write-Host ""
Write-Host "Exporting final CSV..." `
    -ForegroundColor Cyan


$FinalResults |
    Export-Csv `
        -Path $OutputCsv `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Force


Write-Host `
    "CSV created: $OutputCsv" `
    -ForegroundColor Green


# =====================================================
# FINAL CSV HEADER CHECK
# =====================================================
#
# Read the actual CSV header back from disk.
#
# This gives an additional safeguard that the physical
# CSV file contains only the expected columns.
#
# =====================================================

$CsvHeader =
    (
        Import-Csv `
            -Path $OutputCsv |
        Select-Object -First 1 |
        Get-Member `
            -MemberType NoteProperty |
        Select-Object -ExpandProperty Name
    )


$UnexpectedCsvColumns =
    $CsvHeader |
    Where-Object {
        $_ -notin $ExpectedColumns
    }


if ($UnexpectedCsvColumns.Count -gt 0)
{
    Remove-Item `
        -Path $OutputCsv `
        -Force `
        -ErrorAction SilentlyContinue


    throw `
        "CSV validation failed. Unexpected columns: $($UnexpectedCsvColumns -join ', ')"
}


# =====================================================
# DISPLAY SUMMARY
# =====================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host "REPORT SUMMARY" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host `
    "Total Sites          : $($results.Count)" `
    -ForegroundColor Green

Write-Host `
    "M365 Group Sites     : $M365GroupCount" `
    -ForegroundColor Cyan

Write-Host `
    "M365 Public Groups   : $M365PublicCount" `
    -ForegroundColor Cyan

Write-Host `
    "M365 Private Groups  : $M365PrivateCount" `
    -ForegroundColor Cyan

Write-Host `
    "Storage Used         : $TotalStorageUsedGB GB ($TotalStorageUsedTB TB)" `
    -ForegroundColor Cyan

Write-Host `
    "Allocated Storage    : $TotalAllocatedStorageGB GB ($TotalAllocatedStorageTB TB)" `
    -ForegroundColor Cyan

Write-Host `
    "Over Utilized        : $OverUtilizedStorageGB GB ($OverUtilizedStorageTB TB)" `
    -ForegroundColor Yellow

Write-Host `
    "Over Utilized %      : $OverUtilizedPercent%" `
    -ForegroundColor Yellow

Write-Host ""


# =====================================================
# EMAIL
# =====================================================

$CurrentDate =
    Get-Date


$CurrentDateReport =
    $CurrentDate.ToString("MM/dd/yyyy")


$CurrentDateTimeReport =
    $CurrentDate.ToString("MM/dd/yyyy")


$Subject =
    "SharePoint Online Usage Report | $CurrentDateReport | $TotalStorageUsedTB TB | $($results.Count) Sites"


# =====================================================
# EMAIL BODY
# =====================================================

$Body = @"
<html>

<body style='font-family:Calibri,Arial,sans-serif;font-size:14px'>

<h3>
SharePoint Online Site Inventory Report
</h3>


<p>
The attached CSV contains the SharePoint Online site inventory
for the tenant.
</p>


<hr>


<p>

<b>Total SharePoint Sites:</b>
$($results.Count)

<br><br>


<b>Total Storage Used:</b>
$TotalStorageUsedGB GB
($TotalStorageUsedTB TB)

<br><br>


<b>Microsoft Default SharePoint Online Allocated Storage:</b>
$TotalAllocatedStorageGB GB
($TotalAllocatedStorageTB TB)

<br><br>


<b>Over-Utilized Storage:</b>
$OverUtilizedStorageGB GB
($OverUtilizedStorageTB TB)

<br><br>


<b>Over-Utilized Percentage:</b>
$OverUtilizedPercent%

</p>


<hr>


<p>

<b>M365 Group-connected Sites:</b>
$M365GroupCount

<br><br>


<b>Public M365 Groups:</b>
$M365PublicCount

<br><br>


<b>Private M365 Groups:</b>
$M365PrivateCount

</p>


<hr>


<p>

<b>Report Date:</b>
$CurrentDateReport

<br><br>


<b>Report Generated:</b>
$CurrentDateTimeReport

</p>


<p>
Regards,<br>
SharePoint Online Usage Reporting
</p>


</body>

</html>
"@


# =====================================================
# SEND EMAIL USING MICROSOFT GRAPH
# =====================================================

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-GraphAppOnlyToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$CertificatePath,
        [Parameter(Mandatory)][securestring]$CertificatePassword
    )

    $cert = $null
    $privateKey = $null
    try {
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $CertificatePath,
            $CertificatePassword,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        if (-not $cert.HasPrivateKey) { throw 'The PFX certificate does not contain an accessible private key.' }
        if ($cert.NotBefore -gt (Get-Date)) { throw "The certificate is not valid until $($cert.NotBefore)." }
        if ($cert.NotAfter -le (Get-Date)) { throw "The certificate expired on $($cert.NotAfter)." }

        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $now = [DateTimeOffset]::UtcNow
        $header = @{
            alg = 'RS256'
            typ = 'JWT'
            x5t = (ConvertTo-Base64Url -Bytes ([Convert]::FromHexString($cert.Thumbprint)))
        } | ConvertTo-Json -Compress
        $payload = @{
            aud = $tokenEndpoint
            iss = $ApplicationId
            sub = $ApplicationId
            jti = [guid]::NewGuid().ToString()
            nbf = $now.ToUnixTimeSeconds()
            exp = $now.AddMinutes(10).ToUnixTimeSeconds()
        } | ConvertTo-Json -Compress
        $encodedHeader = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($header))
        $encodedPayload = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
        $unsignedJwt = "$encodedHeader.$encodedPayload"
        $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        if ($null -eq $privateKey) { throw 'Could not access the certificate RSA private key.' }
        $signatureBytes = $privateKey.SignData(
            [Text.Encoding]::UTF8.GetBytes($unsignedJwt),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $assertion = "$unsignedJwt.$(ConvertTo-Base64Url -Bytes $signatureBytes)"
        $tokenBody = @{
            client_id = $ApplicationId
            scope = 'https://graph.microsoft.com/.default'
            grant_type = 'client_credentials'
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion = $assertion
        }
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint `
            -ContentType 'application/x-www-form-urlencoded' -Body $tokenBody -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) { throw 'The identity platform did not return an access token.' }
        return $tokenResponse.access_token
    }
    finally {
        if ($null -ne $privateKey) { $privateKey.Dispose() }
        if ($null -ne $cert) { $cert.Dispose() }
    }
}

function Send-GraphMailWithCsv {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Sender,
        [Parameter(Mandatory)][string[]]$Recipients,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$HtmlBody,
        [Parameter(Mandatory)][string]$AttachmentPath
    )

    if (-not (Test-Path -LiteralPath $AttachmentPath -PathType Leaf)) { throw "CSV attachment not found: $AttachmentPath" }
    $file = Get-Item -LiteralPath $AttachmentPath
    if ($file.Length -eq 0) { throw "CSV attachment is empty: $AttachmentPath" }

    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    $recipientObjects = @($Recipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { @{ emailAddress = @{ address = $_.Trim() } } })
    if ($recipientObjects.Count -eq 0) { throw 'Configure at least one recipient in $To.' }

    $graphRoot = 'https://graph.microsoft.com/v1.0'
    $senderEscaped = [uri]::EscapeDataString($Sender)
    $messagesUri = "$graphRoot/users/$senderEscaped/messages"
    $fileName = [IO.Path]::GetFileName($AttachmentPath)

    # Create a draft message first; attachment upload sessions are created against drafts.
    $draftPayload = @{
        subject = $Subject
        body = @{ contentType = 'HTML'; content = $HtmlBody }
        toRecipients = $recipientObjects
    }
    $draftJson = $draftPayload | ConvertTo-Json -Depth 12
    $draft = Invoke-RestMethod -Method Post -Uri $messagesUri -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($draftJson)) -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$draft.id)) { throw 'Microsoft Graph did not return a draft message ID.' }

    $messageId = [uri]::EscapeDataString([string]$draft.id)
    $sessionUri = "$graphRoot/users/$senderEscaped/messages/$messageId/attachments/createUploadSession"
    $sessionBody = @{
        AttachmentItem = @{
            attachmentType = 'file'
            name = $fileName
            size = [long]$file.Length
            contentType = 'text/csv'
        }
    } | ConvertTo-Json -Depth 5
    $session = Invoke-RestMethod -Method Post -Uri $sessionUri -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($sessionBody)) -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$session.uploadUrl)) { throw 'Microsoft Graph did not return an attachment upload URL.' }

    # Upload chunks aligned to 320 KiB; 10 units = 3.125 MiB, below the 4 MiB chunk maximum.
    $chunkSize = 320KB * 10
    [long]$totalBytes = $file.Length
    $stream = [System.IO.File]::OpenRead($AttachmentPath)
    try {
        $buffer = New-Object byte[] $chunkSize
        [long]$offset = 0
        while ($offset -lt $totalBytes) {
            $bytesToRead = [int][Math]::Min($chunkSize, $totalBytes - $offset)
            $bytesRead = $stream.Read($buffer, 0, $bytesToRead)
            if ($bytesRead -le 0) { throw "Unexpected end of file while reading '$fileName'." }
            $chunk = New-Object byte[] $bytesRead
            [Array]::Copy($buffer, 0, $chunk, 0, $bytesRead)
            $endByte = $offset + $bytesRead - 1
            $range = "bytes $offset-$endByte/$totalBytes"
            # uploadUrl is pre-authorized; do not send the Graph bearer token to it.
            $uploadHeaders = @{ 'Content-Length' = [string]$bytesRead; 'Content-Range' = $range }
            Invoke-RestMethod -Method Put -Uri $session.uploadUrl -Headers $uploadHeaders `
                -ContentType 'application/octet-stream' -Body $chunk -ErrorAction Stop | Out-Null
            $offset += $bytesRead
            $percent = [Math]::Min(100, [Math]::Round(($offset / $totalBytes) * 100, 1))
            Write-Progress -Activity "Uploading CSV attachment: $fileName" -Status "$percent% complete" -PercentComplete $percent
        }
        Write-Progress -Activity "Uploading CSV attachment: $fileName" -Completed
    }
    finally { $stream.Dispose() }

    # Send only after all chunks have been accepted.
    $sendUri = "$graphRoot/users/$senderEscaped/messages/$messageId/send"
    Invoke-RestMethod -Method Post -Uri $sendUri -Headers $headers -ErrorAction Stop | Out-Null
}
Write-Host ''
Write-Host 'Sending report email through Microsoft Graph...' -ForegroundColor Cyan

try {
    if ($PfxPasswordPlainText -eq 'REPLACE-WITH-YOUR-PFX-PASSWORD' -or [string]::IsNullOrWhiteSpace($PfxPasswordPlainText)) {
        throw 'Set PfxPasswordPlainText in the configuration section before running the script.'
    }
    if ($From -match 'contoso\.com' -or @($To | Where-Object { $_ -match 'contoso\.com' }).Count -gt 0) {
        throw 'Replace the example sender and recipient addresses in the Graph email configuration.'
    }

    $graphToken = Get-GraphAppOnlyToken -TenantId $Tenant -ApplicationId $ClientId `
        -CertificatePath $PfxPath -CertificatePassword $PfxPassword

    Send-GraphMailWithCsv -Token $graphToken -Sender $From -Recipients $To `
        -Subject $Subject -HtmlBody $Body -AttachmentPath $OutputCsv

    Write-Host 'Microsoft Graph accepted the message for sending.' -ForegroundColor Green
    Write-Host 'Check the recipient mailbox and verify the CSV attachment.' -ForegroundColor Green

    # Delete the generated CSV only after Graph's send operation succeeds. On failure, retain it for troubleshooting.
    Start-Sleep -Seconds 5
    if (Test-Path -LiteralPath $OutputCsv) {
        Remove-Item -LiteralPath $OutputCsv -Force
        Write-Host 'Temporary CSV removed after successful email.' -ForegroundColor DarkGray
    }
}
catch {
    Write-Host ''
    Write-Host 'Graph email failed. CSV has been retained for troubleshooting.' -ForegroundColor Red
    Write-Host "CSV: $OutputCsv" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }
}
finally {
    $graphToken = $null
}


# =====================================================
# FINAL DISPLAY
# =====================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host "REPORT GENERATION COMPLETE" `
    -ForegroundColor Green

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host `
    "Total Sites       : $($results.Count)" `
    -ForegroundColor Yellow

Write-Host `
    "Storage Used      : $TotalStorageUsedTB TB" `
    -ForegroundColor Yellow

Write-Host `
    "Allocated Storage : $TotalAllocatedStorageTB TB" `
    -ForegroundColor Yellow

Write-Host `
    "Over Utilized     : $OverUtilizedStorageTB TB" `
    -ForegroundColor Yellow

Write-Host `
    "Over Utilized %   : $OverUtilizedPercent%" `
    -ForegroundColor Yellow

Write-Host ""

if (Test-Path $OutputCsv)
{
    Write-Host `
        "CSV retained at   : $OutputCsv" `
        -ForegroundColor Yellow
}
else
{
    Write-Host `
        "CSV was removed after successful email." `
        -ForegroundColor DarkGray
}

Write-Host ""

Write-Host "=============================================" `
    -ForegroundColor Cyan
