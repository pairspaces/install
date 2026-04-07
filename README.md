# PairSpaces CLI Installer

The PairSpaces CLI lets you interact with [PairSpaces](https://pairspaces.com) from your terminal. This guide shows how to install or uninstall the PairSpaces CLI for **macOS**, **Linux**, and **Windows**.

## Installation

### macOS / Linux / Windows (WSL)

```bash
curl -fsSL https://get.pairspaces.io/install.sh | bash
```

#### Optional flags:
- `-u`: Install to your user bin directory (`~/.local/bin` on Linux, `~/bin` on macOS)
- `-d <dir>`: Install to a specific directory

```bash
curl -fsSL https://get.pairspaces.io/install.sh | bash -s -- -u
```

### Windows (PowerShell)

```powershell
irm https://get.pairspaces.io/install.ps1 | iex
```

## Uninstalling PairSpaces CLI

### macOS / Linux / Windows (WSL)

```bash
curl -fsSL https://get.pairspaces.io/install.sh | bash -s -- --uninstall
```

### Windows (PowerShell)

```powershell
> $script = Invoke-RestMethod https://get.pairspaces.io/install.ps1
> & ([scriptblock]::Create($script)) -Uninstall
```

## Testing Installation

```bash
pair help
```

## Tests

### Linux, macOS

We use [Bats](https://bats-core.readthedocs.io/en/stable/) to test the installation script:

```sh
bats tests/install.bats
```

### Windows

We use [Pester](https://pester.dev/) to test the installation script. To ensure tests use Pester v5, configure your `$PROFILE`:

```powershell
# Clean out legacy module roots (prevents Pester 3.4 autoload)
$paths = $env:PSModulePath -split ';' | Where-Object {
    $_ -notlike '*WindowsPowerShell*' -and $_ -notlike '*v1.0*'
}
$env:PSModulePath = ($paths -join ';')

# Force Pester 5
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module "$HOME\Documents\PowerShell\Modules\Pester\5.7.1\Pester.psd1" -Force
```

```powershell
Invoke-Pester -CI
```

## Requirements

- **macOS/Linux:** `curl`, `bash`
- **Windows:** PowerShell 5.0+

## Support

Need help? Email support [at] pairspaces [dot] com.
