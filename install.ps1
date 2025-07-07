<#
Usage:
  .\install.ps1            → Install the Pair CLI
  .\install.ps1 -Uninstall → Uninstall the Pair CLI
#>

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================

$name       = "pair"
$binary     = "$name.exe"
$envName    = "latest"
$baseUrl    = "https://downloads.pairspaces.com/$envName"
$installDir = "$env:USERPROFILE\AppData\Local\$name"
$destBin    = "$installDir\$binary"

# =============================================================================
# UI Helpers
# =============================================================================

function Show-Title {
    param([string]$title, [string]$subtitle = "")
    Write-Host ""
    Write-Host ($title) -ForegroundColor Cyan
    if ($subtitle) { Write-Host (" $subtitle") }
}

function Show-Error {
    param([string]$message)
    Write-Host ("[Error] $message") -ForegroundColor Red
    exit 1
}

function Info {
    param([string]$message)
    Write-Host (" $message") -ForegroundColor Gray
}

# =============================================================================
# System Detection
# =============================================================================

function Get-Arch {
    $type = (Get-ComputerInfo).CsSystemType.ToLower()
    if ($type.StartsWith("x64")) { return "amd64" }
    elseif ($type.StartsWith("arm64")) { return "arm64" }
    else { Show-Error "Unsupported architecture: $type" }
}

function Get-Version {
    $versionUrl = "$baseUrl/latest.txt"
    Info "Fetching latest version from $versionUrl"
    try {
        return (Invoke-RestMethod -Uri $versionUrl).Trim()
    } catch {
        Show-Error "Failed to fetch latest.txt from $versionUrl"
    }
}

# =============================================================================
# Download & Install
# =============================================================================

function Ensure-InstallDir {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir | Out-Null
    }
}

function Download-Binary {
    param([string]$url, [string]$outputPath)
    try {
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    } catch {
        Show-Error "Download failed: $url"
    }
}

function Make-Executable {
    param([string]$file)
    icacls $file /grant Everyone:RX > $null
}

function Ensure-InPath {
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($currentPath.Split(';') -contains $installDir)) {
        Show-Title "Adding to PATH" $installDir
        $currentPath = $currentPath.TrimEnd(';')
        $newPath = "$currentPath;$installDir"
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host (" You may need to restart your terminal to use '${binary}'") -ForegroundColor Yellow
    }
}

# =============================================================================
# Uninstall
# =============================================================================

function Uninstall-App {
    Show-Title "Uninstalling PairSpaces CLI"

    # Remove installed binary
    if (Test-Path $destBin) {
        Remove-Item $destBin -Force
        Info "Removed $destBin"
    }

    # Remove install directory
    if (Test-Path $installDir) {
        Remove-Item $installDir -Recurse -Force
        Info "Removed directory $installDir"
    }

    # Remove from PATH
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath.Split(';') -contains $installDir) {
        $newPath = ($currentPath.Split(';') | Where-Object { $_ -ne $installDir }) -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Info "Removed $installDir from user PATH"
        Write-Host (" You may need to restart your shell for changes to take effect.") -ForegroundColor Yellow
    }

    # Remove directory
    $configDir = Join-Path $env:LOCALAPPDATA "pair"
    if (Test-Path $configDir) {
        Remove-Item -Path $configDir -Recurse -Force -ErrorAction SilentlyContinue
        Info "Removed config directory $configDir"
    }

    Show-Title "Uninstallation Complete"
    exit 0
}

# =============================================================================
# Main
# =============================================================================

function Main {
    param (
        [switch]$Uninstall
    )

    if ($Uninstall) {
        Uninstall-App
    }

    Show-Title "Downloading PairSpaces CLI"

    $arch    = Get-Arch
    $version = Get-Version
    $file    = "$name" + "_$version.exe"
    $url     = "$baseUrl/windows/$arch/$file"

    Ensure-InstallDir

    $downloadPath = "$installDir\$binary"
    Download-Binary -url $url -outputPath $downloadPath

    Show-Title "Installing PairSpaces CLI" $url
    Make-Executable $downloadPath
    Ensure-InPath

    Show-Title "Installation Complete" "$binary installed to $installDir"
    Write-Host (" Restart your shell and run '${binary} help' to get started.") -ForegroundColor Green
}

Main @args