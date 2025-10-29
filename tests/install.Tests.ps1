#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
if (-not (Get-Module Pester)) { Import-Module Pester -MinimumVersion 5 -Force }
if ((Get-Module Pester).Version.Major -lt 5) {
  throw "This test suite requires Pester 5+. Loaded: $((Get-Module Pester).Version) at $((Get-Module Pester).Path)"
}

function Split-Segments($raw) { ($raw -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ } }

# ================= SAFE TESTS (mocked; no system changes) =================
Describe "PairSpaces installer - safe tests (mocked)" -Tag 'safe' {
  $script:oldLocal = $null

  BeforeAll {
    $script:oldLocal = $env:LOCALAPPDATA
  }

  BeforeEach {
    # Force installer to pick a temp installDir by changing LOCALAPPDATA,
    # then dot-source AFTER changing the env var so $installDir is non-null.
    $tmpRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ("Temp\pair_safe_root_{0}" -f (Get-Random))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $env:LOCALAPPDATA = $tmpRoot

    $here = Split-Path -Path $PSCommandPath -Parent; if (-not $here) { $here = $PSScriptRoot }
    $installer = Join-Path $here '..\install.ps1'
    if (-not (Test-Path -LiteralPath $installer)) { throw "Missing installer at: $installer" }
    . $installer

    foreach ($fn in 'Ensure-InstallDir','Make-Executable','Ensure-InPath','Get-Version','Get-Arch','Download-Binary') {
      if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        throw "Failed to load install.ps1: function '$fn' not found."
      }
    }

    # Shadow external EXE so Pester can mock it
    if (-not (Get-Command icacls -CommandType Function -ErrorAction SilentlyContinue)) {
      function icacls { param([Parameter(ValueFromRemainingArguments=$true)] $args) }
    }

    # Mocks
    Mock Invoke-RestMethod { "1.2.3" }
    Mock Invoke-WebRequest { } -Verifiable
    Mock New-Item { } -Verifiable
    Mock Remove-Item { } -Verifiable
    Mock Ensure-InPath { }           # avoid PATH writes
    Mock icacls { } -Verifiable
    Mock Show-Title { }
  }

  AfterEach {
    $env:LOCALAPPDATA = $script:oldLocal
  }

  It "Get-Arch returns a known value (amd64 or arm64)" {
    Get-Arch | Should -BeIn @('amd64','arm64')
  }

  It "Get-Version uses Invoke-RestMethod and trims result" {
    Get-Version | Should -BeExactly '1.2.3'
    Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -Exactly
  }

  It "Download-Binary calls Invoke-WebRequest with expected parameters" {
    Download-Binary -url 'https://example/download.exe' -outputPath "$env:TEMP\pair.exe"
    Assert-MockCalled Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -like '*download.exe' }
  }

  It "Ensure-InstallDir calls New-Item when directory is missing (mocked Test-Path)" {
    Mock Test-Path { $false }
    Ensure-InstallDir
    Assert-MockCalled New-Item -Times 1
  }

  It "Make-Executable calls icacls (mocked)" {
    Make-Executable "$env:TEMP\pair.exe"
    Assert-MockCalled icacls -Times 1
  }

  It "Main flow downloads the correct filename and calls Ensure-InPath" {
    Mock Invoke-RestMethod { "0.9.0" }
    Main
    Assert-MockCalled Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -match '/windows/(amd64|arm64)/pair_0\.9\.0\.exe$' }
    Assert-MockCalled Ensure-InPath -Times 1
    Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -Exactly
  }
}

# ================= URL FORMATION (strict) =================
Describe "Download URL formation from Get-Arch & Get-Version" -Tag 'safe','url' {
  $script:oldLocal = $null

  BeforeAll { $script:oldLocal = $env:LOCALAPPDATA }

  BeforeEach {
    $tmpRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ("Temp\pair_urlroot_{0}" -f (Get-Random))
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $env:LOCALAPPDATA = $tmpRoot

    # Dot-source AFTER env change so $installDir = Join-Path $env:LOCALAPPDATA 'pair'
    $here = Split-Path -Path $PSCommandPath -Parent; if (-not $here) { $here = $PSScriptRoot }
    $installer = Join-Path $here '..\install.ps1'
    . $installer

    $script:CapturedCalls = @()
    Mock Invoke-WebRequest {
      param($Uri, $OutFile, $UseBasicParsing)
      $script:CapturedCalls += [pscustomobject]@{ Uri = $Uri; OutFile = $OutFile }
    }
    Mock Ensure-InPath { }
    if (-not (Get-Command icacls -CommandType Function -ErrorAction SilentlyContinue)) { function icacls { param([Parameter(ValueFromRemainingArguments=$true)] $args) } }
    Mock icacls { }
    Mock Show-Title { }
  }

  AfterEach { $env:LOCALAPPDATA = $script:oldLocal }

  $cases = @(
    @{ Arch = 'amd64'; Version = '9.9.9' },
    @{ Arch = 'arm64'; Version = '1.0.0' }
  )

  foreach ($case in $cases) {
    It "Builds URL for Arch=$($case.Arch) Version=$($case.Version)" {
      Mock Get-Arch    { $case.Arch }
      Mock Get-Version { $case.Version }

      Main

      $script:CapturedCalls.Count | Should -Be 1

      $expectedUrl = "$baseUrl/windows/$($case.Arch)/$($name)_$($case.Version).exe"
      $script:CapturedCalls[0].Uri | Should -BeExactly $expectedUrl

      # Compare normalized string paths; file need not exist
      $actual   = [System.IO.Path]::GetFullPath($script:CapturedCalls[0].OutFile)
      $expected = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $env:LOCALAPPDATA 'pair') 'pair.exe'))
      $actual | Should -BeExactly $expected
    }
  }
}

# ================= Destructive tests (enable with RUN_DESTRUCTIVE_TESTS=1) =================
if ($env:RUN_DESTRUCTIVE_TESTS -eq '1') {
  Describe "PairSpaces installer - destructive Path tests (restore after)" -Tag 'destructive' {
    $script:orig        = $null
    $script:oldLocal    = $env:LOCALAPPDATA
    $script:tempRoot    = $null
    $script:expectedDir = $null

    BeforeAll {
      # Ensure LOCALAPPDATA is non-null before ANY dot-sourcing
      if (-not $env:LOCALAPPDATA -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
      }

      # Dot-source once so functions (e.g., Refresh-Environment) exist
      $here = Split-Path -Path $PSCommandPath -Parent; if (-not $here) { $here = $PSScriptRoot }
      $installer = Join-Path $here '..\install.ps1'
      if (-not (Test-Path -LiteralPath $installer)) { throw "Missing installer at: $installer" }
      . $installer

      # capture original PATH (raw+kind)
      $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
      try {
        $raw  = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $null; try { $kind = $reg.GetValueKind("Path") } catch { }
        $script:orig = [pscustomobject]@{ Raw = $raw; Kind = $kind }
      } finally { if ($reg) { $reg.Close() } }

      # seed a known PATH
      $seed = '%SystemRoot%\System32;C:\Tools'
      $regw = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
      try { $regw.SetValue("Path", $seed, [Microsoft.Win32.RegistryValueKind]::ExpandString) } finally { if ($regw) { $regw.Close() } }
      if (Get-Command Refresh-Environment -ErrorAction SilentlyContinue) { Refresh-Environment }

      # Now force installer to use a temp LOCALAPPDATA and re-dot-source
      $script:tempRoot    = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ("Temp\pair_root_{0}" -f (Get-Random))
      New-Item -ItemType Directory -Force -Path $script:tempRoot | Out-Null
      $env:LOCALAPPDATA   = $script:tempRoot
      $script:expectedDir = Join-Path $env:LOCALAPPDATA 'pair'

      . $installer  # re-dot-source so $installDir recomputes with new env

      # keep network/ACL safe
      Mock Invoke-RestMethod { "1.0.0" }
      Mock Invoke-WebRequest { }
      if (-not (Get-Command icacls -CommandType Function -ErrorAction SilentlyContinue)) { function icacls { param([Parameter(ValueFromRemainingArguments=$true)] $args) } }
      Mock icacls { }
      Mock Show-Title { }
    }

    AfterAll {
      # restore original PATH
      if ($null -ne $script:orig) {
        $kind = if ($script:orig.Kind) { $script:orig.Kind } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        $regw = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
        try { $regw.SetValue("Path", $script:orig.Raw, $kind) } finally { if ($regw) { $regw.Close() } }
        if (Get-Command Refresh-Environment -ErrorAction SilentlyContinue) { Refresh-Environment }
      }
      # restore env and cleanup
      $env:LOCALAPPDATA = $script:oldLocal
      if ($script:tempRoot -and (Test-Path -LiteralPath $script:tempRoot)) {
        Remove-Item -Recurse -Force $script:tempRoot -ErrorAction SilentlyContinue
      }
    }

    It "Ensure-InPath adds installDir once and preserves REG_EXPAND_SZ" {
      # sanity pre-check
      $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
      try { $beforeRaw = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { if ($reg) { $reg.Close() } }
      $beforeRaw | Should -Be '%SystemRoot%\System32;C:\Tools'

      Ensure-InPath

      $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
      try {
        $afterRaw = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind     = $reg.GetValueKind("Path")
      } finally { if ($reg) { $reg.Close() } }

      ($afterRaw -split ';') | Should -Contain $script:expectedDir
      $kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "Ensure-InPath is idempotent (no duplicates)" {
      Ensure-InPath; Ensure-InPath
      $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
      try { $afterRaw = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { if ($reg) { $reg.Close() } }
      (($afterRaw -split ';') | Where-Object { $_ -eq $script:expectedDir }).Count | Should -Be 1
    }

    It "Uninstall-App removes installDir from PATH and deletes directory" {
  # Ensure the installer uses exactly the path we assert against
  Set-Variable -Name installDir -Value $script:expectedDir -Scope Global

  # Prep a fake install dir & binary
  New-Item -ItemType Directory -Force -Path $script:expectedDir | Out-Null
  Set-Content -Path (Join-Path $script:expectedDir 'pair.exe') -Value 'fake' -Encoding ascii

  # Ensure it's present first (and in PATH)
  Ensure-InPath

  Uninstall-App

  # --- Retry up to ~5s for both: path removal & dir deletion ---
  $ok = $false
  $tries = 0
  do {
    $tries++

    $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
    try {
      $afterRaw = $reg.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally { if ($reg) { $reg.Close() } }

    $afterExpandedSegments = @()
    foreach ($seg in ($afterRaw -split ';')) {
      if ([string]::IsNullOrWhiteSpace($seg)) { continue }
      $afterExpandedSegments += [Environment]::ExpandEnvironmentVariables($seg).TrimEnd('\')
    }

    $inPath  = $afterExpandedSegments -contains $expandedExpected
    $dirGone = -not (Test-Path -LiteralPath $script:expectedDir)

    if (-not $inPath -and $dirGone) {
      $ok = $true
      break
    }

    Start-Sleep -Milliseconds 250
  } while ($tries -lt 20)

  $ok | Should -BeTrue -Because "PATH should not include the installer dir and the directory should be deleted after uninstall."
}
  }
} else {
  Write-Host "Skipping destructive Path tests. Set `$env:RUN_DESTRUCTIVE_TESTS = '1'` to enable." -ForegroundColor Yellow
}