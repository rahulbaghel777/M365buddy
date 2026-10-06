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
#   - Email the report with storage utilization summary
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

$Tenant = "Domain.onmicrosoft.com"

$ClientId = "App ID/Client ID"

$PfxPath =
    "C:\Users\user profile\Documents\PnPCertificate\SharePointAutomationCert.pfx"


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

$PfxPassword =
    ConvertTo-SecureString `
        "YourStrongPassword" `
        -AsPlainText `
        -Force


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
    "C:\Users\user profile\Documents\PnPCertificate\All_Sites_Email_Report"


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
# EMAIL CONFIGURATION
# =====================================================

$From =
    "SPOUsageReport@.com"

$To = @(
    "user.name@.com"
)

$SmtpServer =
    "10.20.20.10"

# Change SMTP server address as per yours

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
# SEND EMAIL
# =====================================================

Write-Host ""
Write-Host "Sending email report..." `
    -ForegroundColor Cyan


try
{

    Send-MailMessage `
        -From $From `
        -To $To `
        -Subject $Subject `
        -Body $Body `
        -BodyAsHtml `
        -Attachments $OutputCsv `
        -SmtpServer $SmtpServer `
        -ErrorAction Stop


    Write-Host ""
    Write-Host "Email sent successfully." `
        -ForegroundColor Green


    # -------------------------------------------------
    # DELETE TEMPORARY CSV AFTER EMAIL
    # -------------------------------------------------

    Start-Sleep `
        -Seconds 5


    if (Test-Path $OutputCsv)
    {
        Remove-Item `
            $OutputCsv `
            -Force


        Write-Host `
            "Temporary CSV removed after successful email." `
            -ForegroundColor DarkGray
    }

}
catch
{

    Write-Host ""
    Write-Host `
        "Email failed. CSV has been retained." `
        -ForegroundColor Red


    Write-Host `
        "CSV: $OutputCsv" `
        -ForegroundColor Yellow


    Write-Host `
        "Error: $($_.Exception.Message)" `
        -ForegroundColor Red
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