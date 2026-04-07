<#
Usage:
  .\install.ps1            → Install the PairSpaces CLI
  .\install.ps1 -Uninstall → Uninstall the PairSpaces CLI
#>

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================

$name       = "pair"
$binary     = "$name.exe"
$githubRepo = "pairspaces/install"
$releasesApi = "https://api.github.com/repos/$githubRepo/releases"
$installDir = Join-Path $env:LOCALAPPDATA $name
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

function Get-LatestRelease {
    Info "Fetching latest release from $releasesApi/latest"
    try {
        return Invoke-RestMethod -Uri "$releasesApi/latest"
    } catch {
        Show-Error "Failed to fetch latest release"
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
    # Open HKCU:\Environment and get the raw, non-expanded Path
    $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if (-not $reg) { Show-Error "Could not open HKCU:\Environment for write." }

    $rawPath = $reg.GetValue(
        "Path", "",
        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )

    $segments = @()
    if ($rawPath) {
        $segments = $rawPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' }
    }

    $expandedInstall = [Environment]::ExpandEnvironmentVariables($installDir).TrimEnd('\')
    # Avoid duplicates by comparing expanded values of each segment
    $alreadyPresent = $false
    foreach ($seg in $segments) {
        $expandedSeg = [Environment]::ExpandEnvironmentVariables($seg).TrimEnd('\')
        if ([string]::Compare($expandedSeg, $expandedInstall, $true) -eq 0) {
            $alreadyPresent = $true
            break
        }
    }

    if (-not $alreadyPresent) {
        Show-Title "Adding to PATH" $installDir
        $newRaw = ($segments + $installDir) -join ';'
        # Write back as REG_EXPAND_SZ to preserve any %VARS% that may be present
        $reg.SetValue("Path", $newRaw, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        Refresh-Environment
        Write-Host (" You may need to restart your terminal to use '${binary}'") -ForegroundColor Yellow
    }

    $reg.Close()
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

    # Remove from PATH (preserves REG_EXPAND_SZ and respects %VARS%)
    try {
        $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
        if ($reg) {
            $rawPath = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

            if ($rawPath) {
                $expandedInstall = [Environment]::ExpandEnvironmentVariables($installDir).TrimEnd('\')

                $newSegs = @()
                foreach ($seg in ($rawPath -split ';')) {
                    if (-not $seg) { continue }
                    $expandedSeg = [Environment]::ExpandEnvironmentVariables($seg).TrimEnd('\')
                    if ([string]::Compare($expandedSeg, $expandedInstall, $true) -ne 0) {
                        $newSegs += $seg
                    }
                }

                $reg.SetValue("Path", ($newSegs -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
                Info "Removed $installDir from user PATH"
                Refresh-Environment
                Write-Host (" You may need to restart your shell for changes to take effect.") -ForegroundColor Yellow
            }
        } else {
            Info "Could not open HKCU:\Environment to remove from PATH"
        }
        $reg.Close()
    } catch {
        Info "Failed to update PATH during uninstall: $($_.Exception.Message)"
    }

    # Remove config directory
    $configDir = Join-Path $env:LOCALAPPDATA "pair"
    if (Test-Path $configDir) {
        Remove-Item -Path $configDir -Recurse -Force -ErrorAction SilentlyContinue
        Info "Removed config directory $configDir"
    }

    Show-Title "Uninstallation Complete"
}

# =============================================================================
# Refresh Environment
# =============================================================================

function Refresh-Environment {
    # Broadcast WM_SETTINGCHANGE "Environment" so new processes see updates immediately
    $cs = @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
  public const int HWND_BROADCAST = 0xffff;
  public const int WM_SETTINGCHANGE = 0x1A;
  public const int SMTO_ABORTIFHUNG = 0x0002;

  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
      IntPtr hWnd, int Msg, IntPtr wParam, string lParam,
      int fuFlags, int uTimeout, out IntPtr lpdwResult);
}
"@
    Add-Type -TypeDefinition $cs -ErrorAction SilentlyContinue | Out-Null
    [IntPtr]$out = [IntPtr]::Zero
    [void][NativeMethods]::SendMessageTimeout(
        [IntPtr]0xffff, 0x1A, [IntPtr]::Zero, "Environment",
        0x0002, 5000, [ref]$out)
}

# =============================================================================
# Main
# =============================================================================

function Main {
    param (
        [switch]$Uninstall
    )

    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        if ($Uninstall) {
            Uninstall-App
            return
        }

        Show-Title "Downloading PairSpaces CLI"

        $arch    = Get-Arch
        $release = Get-LatestRelease
        $version = $release.tag_name                    # e.g. "v1.2.3"
        $versionStripped = $version -replace '^v', ''  # e.g. "1.2.3"
        $file    = "pair_${versionStripped}_windows_${arch}.exe"
        $url     = "https://github.com/$githubRepo/releases/download/$version/$file"

        Ensure-InstallDir

        Download-Binary -url $url -outputPath $destBin

        Show-Title "Installing PairSpaces CLI" $destBin
        Make-Executable $destBin
        Ensure-InPath

        Show-Title "Installation Complete" "$binary installed to $installDir"
        Write-Host (" Restart your shell and run '${binary} help' to get started.") -ForegroundColor Green
    }
    finally {
        $ProgressPreference = $oldProgressPreference
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Main @args
}
