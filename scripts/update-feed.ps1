# scripts/update-feed.ps1

[CmdletBinding()]
param(
    [switch]$CheckOnly,

    [string]$ServiceTagName = "AzureTrafficManager"
)

$ErrorActionPreference = "Stop"

# Helps Windows PowerShell 5.1 with modern HTTPS endpoints.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
    # Ignore if not applicable.
}

$ConfirmationUrl = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$FeedsDir = Join-Path $RepoRoot "feeds"

$RepoAllFile = Join-Path $FeedsDir "azure-traffic-manager-probes.txt"
$RepoIpv4File = Join-Path $FeedsDir "azure-traffic-manager-probes-ipv4.txt"
$RepoIpv6File = Join-Path $FeedsDir "azure-traffic-manager-probes-ipv6.txt"

$GeneratedDir = Join-Path ([System.IO.Path]::GetTempPath()) ("azure-traffic-manager-probes-feed-" + [System.Guid]::NewGuid().ToString("N"))
$GeneratedAllFile = Join-Path $GeneratedDir "azure-traffic-manager-probes.txt"
$GeneratedIpv4File = Join-Path $GeneratedDir "azure-traffic-manager-probes-ipv4.txt"
$GeneratedIpv6File = Join-Path $GeneratedDir "azure-traffic-manager-probes-ipv6.txt"

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-LfUtf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    if ($Lines.Count -gt 0) {
        $Content = ($Lines -join "`n") + "`n"
    }
    else {
        $Content = ""
    }

    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Get-TextFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $WebClient = [System.Net.WebClient]::new()
    $WebClient.Headers.Add("User-Agent", "SCBC Azure Traffic Manager probe feed updater")
    return $WebClient.DownloadString($Url)
}

function Get-CidrIpVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    $Parts = $Prefix.Split("/")

    if ($Parts.Count -ne 2) {
        throw "Invalid CIDR prefix: $Prefix"
    }

    $IpAddressText = $Parts[0]
    $PrefixLengthText = $Parts[1]

    $IpAddress = $null

    if (-not [System.Net.IPAddress]::TryParse($IpAddressText, [ref]$IpAddress)) {
        throw "Invalid IP address in CIDR prefix: $Prefix"
    }

    $PrefixLength = 0

    if (-not [int]::TryParse($PrefixLengthText, [ref]$PrefixLength)) {
        throw "Invalid prefix length in CIDR prefix: $Prefix"
    }

    if ($IpAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
            throw "Invalid IPv4 prefix length in CIDR prefix: $Prefix"
        }

        return 4
    }

    if ($IpAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($PrefixLength -lt 0 -or $PrefixLength -gt 128) {
            throw "Invalid IPv6 prefix length in CIDR prefix: $Prefix"
        }

        return 6
    }

    throw "Unsupported address family in CIDR prefix: $Prefix"
}

function Show-FileContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host $Path
    Write-Host "================================================================================"
    Get-Content -Path $Path -Encoding UTF8
}

function Compare-FeedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoFile,

        [Parameter(Mandatory = $true)]
        [string]$GeneratedFile,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Diff: $Label"
    Write-Host "================================================================================"

    if (Get-Command git -ErrorAction SilentlyContinue) {
        & git --no-pager diff --no-index `
            --ignore-cr-at-eol `
            $RepoFile `
            $GeneratedFile

        $GitExitCode = $LASTEXITCODE

        if ($GitExitCode -eq 0) {
            Write-Host "No differences found for $Label"
            return $false
        }

        if ($GitExitCode -eq 1) {
            Write-Host "Differences found for $Label"
            return $true
        }

        throw "git diff failed for $Label with exit code $GitExitCode"
    }

    Write-Warning "git was not found. Falling back to Compare-Object output."

    $RepoContent = Get-Content -Path $RepoFile -Encoding UTF8
    $GeneratedContent = Get-Content -Path $GeneratedFile -Encoding UTF8

    $Diff = Compare-Object -ReferenceObject $RepoContent -DifferenceObject $GeneratedContent

    if ($Diff) {
        $Diff | Format-Table -AutoSize
        Write-Host "Differences found for $Label"
        return $true
    }

    Write-Host "No differences found for $Label"
    return $false
}

try {
    if (-not (Test-Path $FeedsDir)) {
        throw "Feeds directory not found: $FeedsDir"
    }

    New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null

    Write-Host "Downloading Microsoft confirmation page:"
    Write-Host $ConfirmationUrl

    $ConfirmationHtml = Get-TextFromUrl -Url $ConfirmationUrl

    $DownloadUrlMatches = [regex]::Matches(
        $ConfirmationHtml,
        'https://download\.microsoft\.com/download/[^"''<> ]+/ServiceTags_Public_[0-9]+\.json'
    )

    $DownloadUrls = @(
        $DownloadUrlMatches |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )

    if ($DownloadUrls.Count -eq 0) {
        throw "Could not find ServiceTags_Public_*.json URL on Microsoft download page."
    }

    $JsonUrl = $DownloadUrls |
        Sort-Object -Property @{
            Expression = {
                if ($_ -match 'ServiceTags_Public_([0-9]+)\.json') {
                    [int64]$Matches[1]
                }
                else {
                    0
                }
            }
        } -Descending |
        Select-Object -First 1

    Write-Host ""
    Write-Host "Downloading Service Tags JSON:"
    Write-Host $JsonUrl

    $JsonText = Get-TextFromUrl -Url $JsonUrl
    $ServiceTags = $JsonText | ConvertFrom-Json

    Write-Host ""
    Write-Host "Service Tags changeNumber: $($ServiceTags.changeNumber)"
    Write-Host "Service Tags cloud: $($ServiceTags.cloud)"
    Write-Host "Looking for service tag: $ServiceTagName"

    $ServiceTag = $ServiceTags.values |
        Where-Object { $_.name -eq $ServiceTagName } |
        Select-Object -First 1

    if (-not $ServiceTag) {
        throw "Service tag not found: $ServiceTagName"
    }

    $Prefixes = @($ServiceTag.properties.addressPrefixes)

    if ($Prefixes.Count -eq 0) {
        throw "Service tag $ServiceTagName does not contain any address prefixes."
    }

    $Ipv4Prefixes = New-Object System.Collections.Generic.List[string]
    $Ipv6Prefixes = New-Object System.Collections.Generic.List[string]

    foreach ($Prefix in $Prefixes) {
        $IpVersion = Get-CidrIpVersion -Prefix $Prefix

        if ($IpVersion -eq 4) {
            $Ipv4Prefixes.Add($Prefix)
        }
        elseif ($IpVersion -eq 6) {
            $Ipv6Prefixes.Add($Prefix)
        }
    }

    Write-LfUtf8NoBomFile -Path $GeneratedAllFile -Lines $Prefixes
    Write-LfUtf8NoBomFile -Path $GeneratedIpv4File -Lines $Ipv4Prefixes.ToArray()
    Write-LfUtf8NoBomFile -Path $GeneratedIpv6File -Lines $Ipv6Prefixes.ToArray()

    Write-Host ""
    Write-Host "Generated files:"
    Write-Host "  $GeneratedAllFile : $($Prefixes.Count) lines"
    Write-Host "  $GeneratedIpv4File : $($Ipv4Prefixes.Count) lines"
    Write-Host "  $GeneratedIpv6File : $($Ipv6Prefixes.Count) lines"

    Show-FileContent -Path $GeneratedAllFile
    Show-FileContent -Path $GeneratedIpv4File
    Show-FileContent -Path $GeneratedIpv6File

    $DiffFound = $false

    $DiffFound = (Compare-FeedFile `
        -RepoFile $RepoAllFile `
        -GeneratedFile $GeneratedAllFile `
        -Label "feeds/azure-traffic-manager-probes.txt") -or $DiffFound

    $DiffFound = (Compare-FeedFile `
        -RepoFile $RepoIpv4File `
        -GeneratedFile $GeneratedIpv4File `
        -Label "feeds/azure-traffic-manager-probes-ipv4.txt") -or $DiffFound

    $DiffFound = (Compare-FeedFile `
        -RepoFile $RepoIpv6File `
        -GeneratedFile $GeneratedIpv6File `
        -Label "feeds/azure-traffic-manager-probes-ipv6.txt") -or $DiffFound

    Write-Host ""
    Write-Host "================================================================================"
    Write-Host "Result"
    Write-Host "================================================================================"

    if (-not $DiffFound) {
        Write-Host "No differences found. Repository feed files are already up to date."
        exit 0
    }

    Write-Host "Differences found."

    if ($CheckOnly) {
        Write-Host "CheckOnly mode is enabled. Repository files were not updated."
        exit 0
    }

    Write-Host "Updating repository feed files..."

    Copy-Item -Path $GeneratedAllFile -Destination $RepoAllFile -Force
    Copy-Item -Path $GeneratedIpv4File -Destination $RepoIpv4File -Force
    Copy-Item -Path $GeneratedIpv6File -Destination $RepoIpv6File -Force

    Write-Host "Repository feed files updated."
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  git diff -- feeds"
    Write-Host "  git add feeds"
    Write-Host '  git commit -m "Update Azure Traffic Manager probe feeds"'
    Write-Host "  git push"
}
finally {
    if (Test-Path $GeneratedDir) {
        Remove-Item -Path $GeneratedDir -Recurse -Force
    }
}