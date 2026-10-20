# =====================================================
# SHAREPOINT ONLINE SITE INVENTORY / USAGE REPORT - POWER AUTOMATE DELIVERY
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
#   - Keep the approved inventory columns and calculations unchanged
#   - Build CSV text in memory and upload directly to SharePoint (no local CSV)
#   - Authenticate directly from a PFX file; prompt securely for its password
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

$Tenant = "YOUR-TENANT.onmicrosoft.com"

$ClientId = "YOUR-ENTRA-APP-CLIENT-ID"

# Full path to your password-protected PFX certificate file.
# Example: "C:\\Certificates\\SharePointAutomation.pfx"
$PfxPath = "C:\\Certificates\\YourCertificate.pfx"


# -----------------------------------------------------
# SHAREPOINT ADMIN CENTER
# -----------------------------------------------------

$AdminCenterUrl =
    "https://YOUR-TENANT-admin.sharepoint.com"


# -----------------------------------------------------
# SHAREPOINT TENANT ROOT URL
# -----------------------------------------------------

$SharePointRootUrl =
    "https://YOUR-TENANT.sharepoint.com"


# -----------------------------------------------------
# UNIQUE SHAREPOINT REPORT FILE NAME
# -----------------------------------------------------

$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$UploadFileName = "SharePointSiteInventory_$DateStamp.csv"


# -----------------------------------------------------
# PARALLEL PROCESSING
# -----------------------------------------------------

$ThrottleLimit = 3


# =====================================================
# SHAREPOINT REPORT UPLOAD CONFIGURATION
# =====================================================
# Create the destination folder before running this script.
# Use this same site and folder in the Power Automate flow.

$ReportSiteUrl =
    "https://YOUR-TENANT.sharepoint.com/sites/SharePointReports"

# Site-relative document library/folder path.
# Example: "Shared Documents/Reports/SharePointSiteInventory/Incoming"
$ReportFolder =
    "Shared Documents/Reports/SharePointSiteInventory/Incoming"


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
# CHECK PFX FILE AND PROMPT FOR PASSWORD
# -----------------------------------------------------

if ([string]::IsNullOrWhiteSpace($PfxPath) -or
    $PfxPath -eq "C:\\Certificates\\YourCertificate.pfx")
{
    throw "Update PfxPath in the configuration section with the full path to your .pfx file."
}

if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf))
{
    throw "PFX file not found: $PfxPath. Check the file path and try again."
}

$PfxPassword = Read-Host -Prompt "Enter the password for the PFX certificate" -AsSecureString
if ($null -eq $PfxPassword -or $PfxPassword.Length -eq 0)
{
    throw "The PFX password cannot be blank."
}

if ([string]::IsNullOrWhiteSpace($ReportSiteUrl) -or
    $ReportSiteUrl -like "*YOUR-TENANT*")
{
    throw "Update ReportSiteUrl in the configuration section."
}
if ([string]::IsNullOrWhiteSpace($ReportFolder))
{
    throw "ReportFolder is blank. Configure the destination library/folder."
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
# BUILD AND VALIDATE CSV IN MEMORY
# =====================================================

Write-Host ""
Write-Host "Building CSV content in memory..." -ForegroundColor Cyan

if (-not $FinalResults -or $FinalResults.Count -eq 0)
{
    throw "No site inventory rows were generated. CSV upload cancelled."
}

# Convert the approved report objects into CSV text without creating a local file.
$CsvLines = @($FinalResults | ConvertTo-Csv -NoTypeInformation)
if ($CsvLines.Count -lt 2)
{
    throw "CSV generation did not produce a header and at least one data row."
}

$CsvContent = $CsvLines -join "`r`n"
$CsvContent += "`r`n"

# Validate the actual serialized CSV header and data in memory.
$CsvRowsForValidation = @($CsvLines | ConvertFrom-Csv)
if ($CsvRowsForValidation.Count -eq 0)
{
    throw "In-memory CSV validation failed: no data rows were parsed."
}

$CsvHeader = @(
    $CsvRowsForValidation[0].PSObject.Properties |
    Select-Object -ExpandProperty Name
)
$UnexpectedCsvColumns = @($CsvHeader | Where-Object { $_ -notin $ExpectedColumns })
$MissingCsvColumns = @($ExpectedColumns | Where-Object { $_ -notin $CsvHeader })

if ($UnexpectedCsvColumns.Count -gt 0 -or $MissingCsvColumns.Count -gt 0)
{
    throw "In-memory CSV validation failed. Unexpected columns: $($UnexpectedCsvColumns -join ', '); missing columns: $($MissingCsvColumns -join ', ')"
}

Write-Host "CSV content generated and validated in memory." -ForegroundColor Green
Write-Host "Data rows: $($CsvRowsForValidation.Count)"
Write-Host "File to create in SharePoint: $UploadFileName"


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
# UPLOAD IN-MEMORY CSV DIRECTLY TO SHAREPOINT
# =====================================================

Write-Host ""
Write-Host "Uploading the in-memory CSV directly to SharePoint..." -ForegroundColor Cyan
Write-Host "Destination site: $ReportSiteUrl"
Write-Host "Destination folder: $ReportFolder"
Write-Host "Filename: $UploadFileName"

try
{
    Connect-PnPOnline `
        -Url $ReportSiteUrl `
        -ClientId $ClientId `
        -Tenant $Tenant `
        -CertificatePath $PfxPath `
        -CertificatePassword $PfxPassword `
        -ErrorAction Stop

    $UploadedFile = Add-PnPFile `
        -Folder $ReportFolder `
        -FileName $UploadFileName `
        -Content $CsvContent `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "REPORT UPLOADED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "Uploaded filename: $UploadFileName"
    if ($UploadedFile -and $UploadedFile.ServerRelativeUrl)
    {
        Write-Host "SharePoint path: $($UploadedFile.ServerRelativeUrl)"
    }
}
catch
{
    Write-Host ""
    Write-Host "SHAREPOINT UPLOAD FAILED. No local CSV was created." -ForegroundColor Red
    Write-Host "Destination: $ReportSiteUrl / $ReportFolder" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally
{
    Disconnect-PnPOnline
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

Write-Host "CSV was generated in memory and uploaded to SharePoint." -ForegroundColor Green

Write-Host ""

Write-Host "=============================================" `
    -ForegroundColor Cyan