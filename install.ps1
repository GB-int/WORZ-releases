[CmdletBinding()]
param(
    [switch]$AcceptLicense,
    [switch]$Silent,
    [ValidateSet('none', 'auto', 'codex', 'claude-code', 'antigravity', 'generic-mcp')]
    [string]$Connect = 'none'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -eq 'Desktop') { $env:PSModulePath = Join-Path $PSHOME 'Modules' }

$ExpectedPublisherSubject = 'CN=WORZ Local Development Code Signing'
$ExpectedPublisherThumbprint = '49CA7AE2B77CCDAA1FC594DA8AD8D5691418F0AC'
$ApiRoot = 'https://api.github.com/repos/GB-int/WORZ-releases'
$DownloadRoot = 'https://github.com/GB-int/WORZ-releases/releases/download'

function Fail([string]$Message) {
    throw "WORZ alpha installer: $Message"
}

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Fail $Message }
}

function Get-NormalizedThumbprint([string]$Value) {
    return ($Value -replace '\s', '').ToUpperInvariant()
}

function Get-ValidAuthenticodeIdentity([string]$Path, [string]$Label) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    Assert ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) "$Label Authenticode signature is invalid: $($signature.Status)"
    Assert ($null -ne $signature.SignerCertificate) "$Label signer certificate is missing."
    $subject = [string]$signature.SignerCertificate.Subject
    $thumbprint = Get-NormalizedThumbprint ([string]$signature.SignerCertificate.Thumbprint)
    Assert (-not [string]::IsNullOrWhiteSpace($subject)) "$Label signer subject is empty."
    Assert ($thumbprint -match '^[0-9A-F]{40}$') "$Label signer thumbprint is invalid."
    return [pscustomobject]@{ Subject = $subject; Thumbprint = $thumbprint }
}

function Assert-SamePublisher($Identity, [string]$Label) {
    Assert ([string]$Identity.Subject -ceq $ExpectedPublisherSubject) "$Label signer subject does not match the signed bootstrap publisher pin."
    Assert ([string]$Identity.Thumbprint -ceq $ExpectedPublisherThumbprint) "$Label signer thumbprint does not match the signed bootstrap publisher pin."
}

function Get-DetachedManifestSigner([string]$ManifestPath, [string]$SignaturePath) {
    if ($null -eq ('System.Security.Cryptography.Pkcs.SignedCms' -as [type])) {
        try { Add-Type -AssemblyName System.Security -ErrorAction Stop }
        catch { Add-Type -AssemblyName System.Security.Cryptography.Pkcs -ErrorAction Stop }
    }
    if ($null -eq ('System.Security.Cryptography.Pkcs.SignedCms' -as [type])) {
        Fail 'SignedCms is unavailable in the current PowerShell runtime.'
    }
    $contentInfo = [System.Security.Cryptography.Pkcs.ContentInfo]::new([IO.File]::ReadAllBytes($ManifestPath))
    $signedCms = [System.Security.Cryptography.Pkcs.SignedCms]::new($contentInfo, $true)
    $signedCms.Decode([IO.File]::ReadAllBytes($SignaturePath))
    Assert ($signedCms.SignerInfos.Count -eq 1) 'release-manifest.p7s must contain exactly one signer.'
    $signedCms.CheckSignature($true)
    $certificate = $signedCms.SignerInfos[0].Certificate
    Assert ($null -ne $certificate) 'release-manifest.p7s signer certificate is missing.'
    return [pscustomobject]@{
        Subject = [string]$certificate.Subject
        Thumbprint = Get-NormalizedThumbprint ([string]$certificate.Thumbprint)
    }
}

function Get-FileEvidence([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        SizeBytes = [int64]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }
}

function Assert-ArtifactEvidence($Manifest, [string]$FileName, $DownloadedEvidence) {
    $records = @($Manifest.artifacts | Where-Object { [string]$_.file -ceq $FileName })
    Assert ($records.Count -eq 1) "release manifest must contain exactly one artifact record for $FileName."
    $record = $records[0]
    $expectedHash = ([string]$record.sha256).ToUpperInvariant()
    Assert ($expectedHash -match '^[0-9A-F]{64}$') "release manifest SHA-256 is invalid for $FileName."
    Assert ([int64]$record.sizeBytes -eq [int64]$DownloadedEvidence.SizeBytes) "downloaded size does not match signed manifest for $FileName."
    Assert ($expectedHash -ceq [string]$DownloadedEvidence.Sha256) "downloaded SHA-256 does not match signed manifest for $FileName."
    return $record
}

function Assert-WorzReleaseManifest($Manifest, [string]$Tag, [string]$Version, [string[]]$ExpectedAssets, $AssetMap) {
    Assert ($Manifest.schemaVersion -eq 2) 'unsupported release manifest schema.'
    Assert ([string]$Manifest.product -ceq 'WORZ') 'release manifest product does not match WORZ.'
    Assert ([string]$Manifest.tag -ceq $Tag) 'release manifest tag does not match the release tag.'
    Assert ([string]$Manifest.version -ceq $Version) 'release manifest version does not match the release version.'
    Assert ([string]$Manifest.platform -ceq 'windows') 'release manifest platform is not windows.'
    Assert ([string]$Manifest.architecture -ceq 'x64') 'release manifest architecture is not x64.'
    Assert (-not [string]::IsNullOrWhiteSpace([string]$Manifest.buildProvenanceId)) 'release manifest provenance is missing.'
    Assert ([string]$Manifest.publisher.label -ceq 'GB-int/WORZ') 'release manifest publisher label is invalid.'
    Assert ([string]$Manifest.publisher.subject -ceq $ExpectedPublisherSubject) 'release manifest publisher subject does not match the bootstrap pin.'
    Assert ((Get-NormalizedThumbprint ([string]$Manifest.publisher.thumbprint)) -ceq $ExpectedPublisherThumbprint) 'release manifest publisher thumbprint does not match the bootstrap pin.'

    $manifestAssets = @($Manifest.expectedReleaseAssets | ForEach-Object { [string]$_ })
    $difference = @(Compare-Object -ReferenceObject @($ExpectedAssets | Sort-Object) -DifferenceObject @($manifestAssets | Sort-Object))
    Assert ($difference.Count -eq 0) 'signed manifest asset allowlist does not match the bootstrap allowlist.'
    $expectedArtifactNames = @($ExpectedAssets | Where-Object { $_ -notin @('release-manifest.json', 'release-manifest.p7s') })
    $artifactNames = @($Manifest.artifacts | ForEach-Object { [string]$_.file })
    Assert (($artifactNames | Select-Object -Unique).Count -eq $artifactNames.Count) 'signed manifest contains duplicate artifact records.'
    $artifactDifference = @(Compare-Object -ReferenceObject @($expectedArtifactNames | Sort-Object) -DifferenceObject @($artifactNames | Sort-Object))
    Assert ($artifactDifference.Count -eq 0) 'signed manifest artifact records do not match the non-circular artifact allowlist.'
    foreach ($record in @($Manifest.artifacts)) {
        $name = [string]$record.file
        $hash = ([string]$record.sha256).ToUpperInvariant()
        Assert ($hash -match '^[0-9A-F]{64}$') "signed manifest artifact SHA-256 is invalid: $name"
        Assert ([int64]$record.sizeBytes -gt 0) "signed manifest artifact size is invalid: $name"
        Assert ($AssetMap.ContainsKey($name)) "signed manifest artifact is absent from GitHub release metadata: $name"
        Assert ([int64]$record.sizeBytes -eq [int64]$AssetMap[$name].size) "signed manifest artifact size differs from GitHub release metadata: $name"
    }

    Assert ([string]$Manifest.installedApplication.fileName -ceq 'WORZ.exe') 'installed application file name is invalid.'
    Assert ([string]$Manifest.installedApplication.releaseVersion -ceq $Version) 'installed application release version is invalid.'
    Assert (([string]$Manifest.installedApplication.sha256).ToUpperInvariant() -match '^[0-9A-F]{64}$') 'installed application SHA-256 is invalid.'
    Assert ([int64]$Manifest.installedApplication.sizeBytes -gt 0) 'installed application size is invalid.'
    Assert (-not [string]::IsNullOrWhiteSpace([string]$Manifest.installedApplication.productName)) 'installed application product name is missing.'
    Assert (-not [string]::IsNullOrWhiteSpace([string]$Manifest.installedApplication.productVersion)) 'installed application product version is missing.'
}

function Assert-WorzLicenseManifest($Manifest, $LicenseEvidence) {
    $licenseRecord = Assert-ArtifactEvidence -Manifest $Manifest -FileName 'LICENSE' -DownloadedEvidence $LicenseEvidence
    Assert ([string]$Manifest.license.id -ceq 'WORZ-Alpha-Evaluation-License-1.0') 'signed license identifier is invalid.'
    Assert ([string]$Manifest.license.version -ceq '1.0') 'signed license version is invalid.'
    Assert ([string]$Manifest.license.file -ceq 'LICENSE') 'signed license file name is invalid.'
    Assert (([string]$Manifest.license.sha256).ToUpperInvariant() -ceq ([string]$licenseRecord.sha256).ToUpperInvariant()) 'signed license hash does not match artifact evidence.'
}

function Assert-WorzChecksums($Manifest, [string]$ChecksumsPath) {
    $checksumRecords = @{}
    foreach ($line in @(Get-Content -LiteralPath $ChecksumsPath)) {
        $match = [regex]::Match($line, '^([0-9A-Fa-f]{64})\s{2}([^\\/]+)$')
        Assert ($match.Success) 'SHA256SUMS.txt contains an invalid line.'
        $name = $match.Groups[2].Value
        Assert (-not $checksumRecords.ContainsKey($name)) "SHA256SUMS.txt contains a duplicate entry: $name"
        $checksumRecords[$name] = $match.Groups[1].Value.ToUpperInvariant()
    }
    $expectedNames = @($Manifest.artifacts | ForEach-Object { [string]$_.file } | Where-Object { $_ -ne 'SHA256SUMS.txt' })
    $difference = @(Compare-Object -ReferenceObject @($expectedNames | Sort-Object) -DifferenceObject @($checksumRecords.Keys | Sort-Object))
    Assert ($difference.Count -eq 0) 'SHA256SUMS.txt does not exactly match signed artifact records.'
    foreach ($name in $expectedNames) {
        $record = @($Manifest.artifacts | Where-Object { [string]$_.file -ceq $name })[0]
        Assert ($checksumRecords[$name] -ceq ([string]$record.sha256).ToUpperInvariant()) "SHA256SUMS.txt differs from signed manifest: $name"
    }
}

function Assert-WorzInstalledApplication($Manifest, [string]$ExecutablePath) {
    $expected = $Manifest.installedApplication
    $evidence = Get-FileEvidence -Path $ExecutablePath
    Assert ([int64]$expected.sizeBytes -eq [int64]$evidence.SizeBytes) 'installed WORZ.exe size differs from the signed package evidence.'
    Assert (([string]$expected.sha256).ToUpperInvariant() -ceq [string]$evidence.Sha256) 'installed WORZ.exe SHA-256 differs from the signed package evidence.'
    $versionInfo = (Get-Item -LiteralPath $ExecutablePath).VersionInfo
    Assert ([string]$versionInfo.ProductName -ceq [string]$expected.productName) 'installed WORZ.exe ProductName differs from the signed package evidence.'
    Assert ([string]$versionInfo.ProductVersion -ceq [string]$expected.productVersion) 'installed WORZ.exe ProductVersion differs from the signed package evidence.'
}

function Get-LatestWorzAlphaRelease($Headers) {
    $releases = Invoke-RestMethod -Method Get -Uri ($ApiRoot + '/releases?per_page=100') -Headers $Headers
    $release = @($releases | Where-Object { $_.prerelease -and -not $_.draft } |
        Sort-Object { [DateTime]$_.published_at } -Descending | Select-Object -First 1)
    Assert ($release.Count -eq 1) 'the latest published prerelease was not found.'
    return $release[0]
}

function Get-WorzExpectedReleaseAssets([string]$Version) {
    return @(
        "WORZ-$Version-windows-x64-setup.exe",
        "WORZ-$Version-sbom.cdx.json",
        'THIRD_PARTY_NOTICES.md',
        'LICENSE',
        'install.ps1',
        'SHA256SUMS.txt',
        'release-manifest.json',
        'release-manifest.p7s'
    )
}

function Get-WorzReleaseAssetSizeLimit([string]$Name) {
    if ($Name -like '*-windows-x64-setup.exe') { return [int64]536870912 }
    if ($Name -like '*-sbom.cdx.json') { return [int64]10485760 }
    if ($Name -eq 'release-manifest.p7s') { return [int64]1048576 }
    return [int64]2097152
}

function Get-WorzReleaseAssetMap($Release, [string[]]$ExpectedNames) {
    $releaseAssets = @($Release.assets)
    $actualNames = @($releaseAssets | ForEach-Object { [string]$_.name })
    Assert (($actualNames | Select-Object -Unique).Count -eq $actualNames.Count) 'release contains duplicate asset names.'
    $difference = @(Compare-Object -ReferenceObject @($ExpectedNames | Sort-Object) -DifferenceObject @($actualNames | Sort-Object))
    Assert ($difference.Count -eq 0) 'release asset set does not exactly match the signed public allowlist.'
    $assetMap = @{}
    foreach ($asset in $releaseAssets) {
        $name = [string]$asset.name
        $size = [int64]$asset.size
        Assert ($size -gt 0 -and $size -le (Get-WorzReleaseAssetSizeLimit -Name $name)) "release asset size is outside its safety limit: $name"
        $assetMap[$name] = $asset
    }
    return $assetMap
}

function Receive-WorzReleaseAsset($AssetMap, [string]$Tag, [string]$Name, [string]$Destination, $Headers) {
    Assert ($AssetMap.ContainsKey($Name)) "release asset is missing: $Name"
    $declaredSize = [int64]$AssetMap[$Name].size
    Assert ($declaredSize -gt 0 -and $declaredSize -le (Get-WorzReleaseAssetSizeLimit -Name $Name)) "release asset size is outside its safety limit: $Name"
    Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri "$DownloadRoot/$Tag/$Name" -OutFile $Destination -TimeoutSec 120 -MaximumRedirection 5
    $evidence = Get-FileEvidence -Path $Destination
    Assert ([int64]$AssetMap[$Name].size -eq [int64]$evidence.SizeBytes) "downloaded size does not match GitHub release metadata for $Name."
    return $evidence
}

function Save-InstallReceipt($Receipt) {
    Assert (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) 'LOCALAPPDATA is unavailable for the install receipt.'
    $receiptDirectory = Join-Path $env:LOCALAPPDATA 'WORZ'
    New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $receiptDirectory 'install-receipt.json'),
        ($Receipt | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-WorzSignedInstaller([string]$InstallerPath, [bool]$SilentMode) {
    $arguments = if ($SilentMode) { @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-') } else { @() }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = if ($SilentMode) {
        Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
    } else {
        Start-Process -FilePath $InstallerPath -Wait -PassThru
    }
    $timer.Stop()
    Assert ($process.ExitCode -in @(0, 1641, 3010)) "installer exited with code $($process.ExitCode)."
    return [pscustomobject]@{
        Arguments = $arguments
        ExitCode = $process.ExitCode
        DurationMs = [int]$timer.ElapsedMilliseconds
    }
}

function Get-WorzInstalledExecutable {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\WORZ\WORZ.exe'),
        (Join-Path $env:ProgramFiles 'WORZ\WORZ.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    $executable = $candidates | Select-Object -First 1
    Assert (-not [string]::IsNullOrWhiteSpace([string]$executable)) 'installed WORZ.exe was not found.'
    return [string]$executable
}

function Open-WorzAgentConnection([string]$ExecutablePath, [string]$Host, $Receipt) {
    if ($Host -eq 'none') { return }
    try {
        Start-Process -FilePath $ExecutablePath -ArgumentList @('--agent-connect', $Host) | Out-Null
        $Receipt.activation.launched = $true
        $Receipt.activation.status = 'confirmation_opened'
        Save-InstallReceipt $Receipt
    } catch {
        $Receipt.activation.status = 'launch_failed'
        Save-InstallReceipt $Receipt
        throw
    }
}

function New-WorzBootstrapTempRoot {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('worz-alpha-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-WorzBootstrapTempRoot([string]$Path) {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($Path)
    $leaf = [IO.Path]::GetFileName($resolved)
    $item = if (Test-Path -LiteralPath $resolved) { Get-Item -LiteralPath $resolved -Force } else { $null }
    if ($item -and $item.PSIsContainer -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        [IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -eq $tempBase -and $leaf -match '^worz-alpha-[0-9a-f]{32}$') {
        $unsafeDescendants = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object {
            $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        })
        Assert ($unsafeDescendants.Count -eq 0) 'temporary bootstrap directory contains a reparse point; recursive cleanup refused.'
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Invoke-WorzPublicBootstrap {
    Assert ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath -PathType Leaf)) 'the signed bootstrap path is unavailable.'
    Assert ($ExpectedPublisherSubject -notmatch '^__WORZ_[A-Z_]+__$') 'this is an unsigned source template, not a public bootstrap.'
    Assert ($ExpectedPublisherThumbprint -match '^[0-9A-F]{40}$') 'the public bootstrap publisher thumbprint pin is invalid.'
    Assert-SamePublisher -Identity (Get-ValidAuthenticodeIdentity -Path $PSCommandPath -Label 'Public bootstrap') -Label 'Public bootstrap'
    Assert ($env:OS -eq 'Windows_NT') 'only Windows is supported.'
    Assert ([Environment]::Is64BitOperatingSystem) 'Windows x64 is required.'
    Assert ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'only the AMD64 process architecture is supported.'
    if ($Silent -and -not $AcceptLicense) { Fail '-Silent requires explicit -AcceptLicense.' }

    $tempRoot = New-WorzBootstrapTempRoot
    try {
        $headers = @{
            'User-Agent' = 'WORZ-alpha-installer'
            Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
        }
        $release = Get-LatestWorzAlphaRelease -Headers $headers
        $tag = [string]$release.tag_name
        Assert ($tag -match '^v\d+\.\d+\.\d+-alpha\.\d+$') "invalid prerelease tag: $tag"
        $version = $tag.Substring(1)
        $installerName = "WORZ-$version-windows-x64-setup.exe"
        $expectedAssets = Get-WorzExpectedReleaseAssets -Version $version
        $assetMap = Get-WorzReleaseAssetMap -Release $release -ExpectedNames $expectedAssets
        $downloadEvidence = @{}

        foreach ($name in @('release-manifest.json', 'release-manifest.p7s')) {
            $destination = Join-Path $tempRoot $name
            $downloadEvidence[$name] = Receive-WorzReleaseAsset -AssetMap $assetMap -Tag $tag -Name $name -Destination $destination -Headers $headers
        }
        $manifestPath = Join-Path $tempRoot 'release-manifest.json'
        $manifestSignaturePath = Join-Path $tempRoot 'release-manifest.p7s'
        Assert-SamePublisher -Identity (Get-DetachedManifestSigner -ManifestPath $manifestPath -SignaturePath $manifestSignaturePath) -Label 'Release manifest'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-WorzReleaseManifest -Manifest $manifest -Tag $tag -Version $version -ExpectedAssets $expectedAssets -AssetMap $assetMap
        [void](Assert-ArtifactEvidence -Manifest $manifest -FileName 'install.ps1' -DownloadedEvidence (Get-FileEvidence -Path $PSCommandPath))

        foreach ($name in @('LICENSE', 'SHA256SUMS.txt', $installerName)) {
            $destination = Join-Path $tempRoot $name
            $downloadEvidence[$name] = Receive-WorzReleaseAsset -AssetMap $assetMap -Tag $tag -Name $name -Destination $destination -Headers $headers
            [void](Assert-ArtifactEvidence -Manifest $manifest -FileName $name -DownloadedEvidence $downloadEvidence[$name])
        }
        Assert-WorzLicenseManifest -Manifest $manifest -LicenseEvidence $downloadEvidence['LICENSE']
        Assert-WorzChecksums -Manifest $manifest -ChecksumsPath (Join-Path $tempRoot 'SHA256SUMS.txt')

        $installerPath = Join-Path $tempRoot $installerName
        Assert-SamePublisher -Identity (Get-ValidAuthenticodeIdentity -Path $installerPath -Label 'Installer') -Label 'Installer'
        $installResult = Invoke-WorzSignedInstaller -InstallerPath $installerPath -SilentMode $Silent
        $worzExecutable = Get-WorzInstalledExecutable
        Assert-WorzInstalledApplication -Manifest $manifest -ExecutablePath $worzExecutable
        Assert-SamePublisher -Identity (Get-ValidAuthenticodeIdentity -Path $worzExecutable -Label 'Installed WORZ.exe') -Label 'Installed WORZ.exe'

        $receipt = [ordered]@{
            product = 'WORZ'
            version = $version
            tag = $tag
            publisher = [ordered]@{
                label = 'GB-int/WORZ'
                subject = $ExpectedPublisherSubject
                thumbprint = $ExpectedPublisherThumbprint
            }
            supplyChain = [ordered]@{
                manifestSha256 = $downloadEvidence['release-manifest.json'].Sha256
                manifestSignatureSha256 = $downloadEvidence['release-manifest.p7s'].Sha256
                installerSha256 = $downloadEvidence[$installerName].Sha256
            }
            license = [ordered]@{
                id = [string]$manifest.license.id
                version = [string]$manifest.license.version
                sha256 = $downloadEvidence['LICENSE'].Sha256
                acceptance = $(if ($Silent) { 'explicit_silent_flag' } else { 'installer_ui' })
            }
            install = [ordered]@{
                command = $installerName
                arguments = $installResult.Arguments
                exitCode = $installResult.ExitCode
                durationMs = $installResult.DurationMs
                status = 'installed_and_publisher_verified'
            }
            activation = [ordered]@{
                requestedHost = $Connect
                launched = $false
                status = $(if ($Connect -eq 'none') { 'not_requested' } else { 'pending' })
            }
            timestampUtc = [DateTime]::UtcNow.ToString('o')
        }
        Save-InstallReceipt $receipt
        Open-WorzAgentConnection -ExecutablePath $worzExecutable -Host $Connect -Receipt $receipt
        Write-Host "WORZ $version installed. Agent connection: $Connect."
    } finally {
        Remove-WorzBootstrapTempRoot -Path $tempRoot
    }
}

Invoke-WorzPublicBootstrap

# SIG # Begin signature block
# MIIHTgYJKoZIhvcNAQcCoIIHPzCCBzsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD1TF7CYzH4EizQ
# YidSGX6zFxtWQhNIN9ViHBCs7f0JL6CCBDAwggQsMIIClKADAgECAhATnEYQOxBl
# nEQlh/r+4hbDMA0GCSqGSIb3DQEBCwUAMC4xLDAqBgNVBAMMI1dPUlogTG9jYWwg
# RGV2ZWxvcG1lbnQgQ29kZSBTaWduaW5nMB4XDTI2MDgzMTE3NTI0MVoXDTI5MDgz
# MTE4MDI0MVowLjEsMCoGA1UEAwwjV09SWiBMb2NhbCBEZXZlbG9wbWVudCBDb2Rl
# IFNpZ25pbmcwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQDc8BRhI90E
# b1CbDxgcBZf/Fmy7ZsFPQq7W007s0fHyrvmtDWNs0FiBWjQts3TgEkTot5uWRgZW
# TuxB1EihdU37XGJ9M55v6ojJ5vxfVijn546Da3kVUQD3nskmmT60PqksM+bcogOh
# JqIQ8MD9SxPhnIb2i2aeaeICjEMPfGMJHuY+vpBKLDa9XPgpkSNFgzGY7qg8+ZXW
# 9x8hrLy+KAXoa/9zve5HaJxzI6gbXD+qBkatvvMYpFu95hxvkLw+XWz4qD1TCq+y
# U6vGSA7elF/mZ+85+d2i93XWnUXpX6fhh3J7cO8Pknq084g8hYMg3IJ9BHYBGIsV
# YDotVE0Z1Hor1uA9x8AT4hvnSPn8o/3B9qTMWjycX+RAkHEBFWRFFdPdTefZewXA
# WRRDUusrDOmZQbYiEkQzxEOgbB/SAzi1s5/qBf5+7dVmXV2CxL9wwHw3iIfzQZmi
# E5e5PwbAcdW3NGvUxnV/lEZKK51AYWJfKkNJGpUxtLCcVw2SSlVB9ikCAwEAAaNG
# MEQwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQW
# BBQJiFmtu/7aY94Nm0Ovcop0srhhajANBgkqhkiG9w0BAQsFAAOCAYEAUq7A758v
# kgmEteWPawhlku5cCUhPIVbxCV5eLCu72daD4Yo6QM3m+Tyg86ABJFRtOgaxSTv5
# xhnKfK8bWBudwLTSMTC2oDlO23BoUVg/tDcvT+Qs7ANNRIsOexl9L8VRu/2bByMJ
# ERLs8FVGSxpiotuQyHGhkB/VIQGyZ37n/wYZlQ1IThu1Y1p253SS0WPDOrwukiEh
# YBq8eA5dEiTENmEp0CC2Pi8Tfv3WbRtg/BbnTdUE3gszmahxb7qjEcoEluhc9Sch
# 6ZEBsx69jcBNG4yxl5Xpd0jB9C4jVZberHLKJ7ybsJ9eRE4Czi8aRGw0RtGJBzLo
# qDzwEPWrb8MsGnJmCKUFV9eRTc+2R31bsTvmkQ7bB4tD/jSlv4eOZcHjjr0lGuLZ
# WynEYjrEVc1dXOtJJ4C/obGfVV5hgd842g3KVC7gmQbzVl71ANogq6uwyTO9xCsp
# rOVmttHORtfO5jwdJiUwZQCjRL1lblfWLana+aNV29zm0G13nYd/ro10MYICdDCC
# AnACAQEwQjAuMSwwKgYDVQQDDCNXT1JaIExvY2FsIERldmVsb3BtZW50IENvZGUg
# U2lnbmluZwIQE5xGEDsQZZxEJYf6/uIWwzANBglghkgBZQMEAgEFAKCBhDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBT
# yB5zM4oU0C84ps2cT+2s3uXPZpUK5tNUZbq82iSLQzANBgkqhkiG9w0BAQEFAASC
# AYDDiFFY8bTvq7HVrUlVIUdzqvqDxV1/oy4vLP2Ld/TkGuj6exfDIYBePhcSk1xN
# dtYB3IcD1w0JLWMlQCxLn4BjOyCdGOkFHqLbdcQW3tDElsxmhykvB8U8oSDfIAzL
# DyUeycgXbYcLrbbeJ0rp8INqxhXT+17uZLnemTtumjVVgOtWgX0u3EzUAB4MIzu5
# 5QB1Qtz4pICwdOgQ1ttFZ4ndCst/LD/OGB2OziGAq1sbSQoWHgsZpx5cr3dZSTzQ
# t9I46T5YpSfiPER3TUYdhJomFnDp8NTKCEYLgGNOuEjBExxO50DFgJ3b23vDEXAD
# JBLaWmB2E/g6feYnzRFieO0h5RHzCpNHzZSR0GBnSe76Nfl8r4WB4Qdf7R4YlKud
# rJkbXLzOm/AoknDeq7yz+EyCqU1rFsrcgOkHaT8XwYL9Sbrv1b4JlrKNZqfK2SXa
# ir2eDDm1HvMawink4Z84SfXS1ZKzqN9Uzjf/zvK1nhAq0e8LfDAUctMQg4N+EDB2
# gAw=
# SIG # End signature block
