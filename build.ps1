﻿[cmdletbinding()]
param(
    [Parameter(ParameterSetName = 'publish')]
    [string]
    $GalleryKey,

    [Parameter(ParameterSetName = 'publish')]
    [switch]
    $Prerelease,

    [Parameter(ParameterSetName = 'release')]
    [Parameter(ParameterSetName = 'publish')]
    [switch]
    $Release,

    [Parameter(ParameterSetName = 'release')]
    [Parameter(ParameterSetName = 'publish')]
    [switch]
    $Draft

)

$moduleName = 'Thycotic.SecretServer'
$staging = "$env:TEMP\tss_staging\"

if (Test-Path $staging) {
    Remove-Item -Recurse -Force $staging
}
$imported = Import-Module .\src\Thycotic.SecretServer.psd1 -Force -PassThru

Import-Module Pester
$tests = Invoke-Pester -Path "$PSScriptRoot\tests" -Output Minimal -PassThru

if ($PSBoundParameters['Prerelease']) {
    $foundModule = Find-Module -Name $moduleName -AllowPrerelease:$Prerelease
} else {
    $foundModule = Find-Module -Name $moduleName
}

if ($foundModule.Version -ge $imported.Version) {
    Write-Warning "PowerShell Gallery version of $moduleName is more recent ($($foundModule.Version) >= $($imported.Version))"
}

if ($tests.FailedCount -eq 0) {
    $moduleTempPath = Join-Path $staging $moduleName
    Write-Host "Staging directory: $moduleTempPath"
    $imported | Split-Path | Copy-Item -Destination $moduleTempPath -Recurse

    Write-Host "Module Files:"
    Get-ChildItem $moduleTempPath -Recurse | Select-Object Directory, Name

    try {
        Write-Host "Publishing $moduleName [$($imported.Version)] to PowerShell Gallery"

        Publish-Module -Path $moduleTempPath -NuGetApiKey $gallerykey
        Write-Host "successfully published to PS Gallery"
    } catch {
        Write-Warning "Publish failed: $_"
    }

    if ($PSBoundParameters['Release']) {
        if ((gh config get prompt) -eq 'enabled') {
            Invoke-Expression "gh config set prompt disabled"
        }
        $moduleData = Import-PowerShellDataFile "$staging\$moduleName\$moduleName.psd1"
        $changeLog = [IO.Path]::Combine([string]$PSScriptRoot, 'release.md')
        Compress-Archive "$staging\$moduleName\*" -DestinationPath "$staging\$moduleName.zip" -CompressionLevel Fastest -Force
        $ghArgs = "release create `"v$($moduleData.ModuleVersion)`" `"$($staging)$($moduleName).zip#$($moduleName).zip`" --title `"Thycotic.SecretServer $($moduleData.ModuleVersion)`" --notes-file $changeLog"
        if ($PSBoundParameters['Prerelease']) {
            $ghArgs = $ghArgs + " --prerelease"
        }
        if ($PSBoundParameters['Draft']) {
            $ghArgs = $ghArgs + " --draft"
        }

        Write-Host "gh command to execute: $ghArgs" -ForegroundColor DarkYellow

        Invoke-Expression "gh $ghArgs"

        if ((gh config get prompt) -eq 'disabled') {
            Invoke-Expression "gh config set prompt enabled"
        }
    }

    Remove-Item -Recurse -Force $staging
} else {
    Write-Host "Tests failures detected; cancelling and cleaning up"
}