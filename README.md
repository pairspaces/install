# PairSpaces CLI Installer

The PairSpaces CLI lets you interact with [PairSpaces](https://pairspaces.com) from your terminal. This guide shows how to install or uninstall the PairSpaces CLI for **macOS**, **Linux**, and **Windows**.

## Installation

### macOS / Linux

Run this command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/pairspaces/install/main/install.sh | bash
```

You may need `sudo` to install into `/usr/local/bin`.

#### Optional flags:
- `-u`: Install to your user bin directory (`~/.local/bin` on Linux, `~/bin` on macOS)
- `-d <dir>`: Install to a specific directory

```bash
curl -fsSL https://raw.githubusercontent.com/pairspaces/install/main/install.sh | bash -s -- -u
```

### Windows (PowerShell)

Run these PowerShell commands:

```powershell
$installerUrl = "https://raw.githubusercontent.com/pairspaces/install/main/install.bat"
$installerPath = "$env:USERPROFILE\Downloads\install_pair.bat"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
& $installerPath
```

Alternatively, run these Powershell commands:

```
cd "$env:USERPROFILE\Downloads"
curl https://raw.githubusercontent.com/pairspaces/install/main/install.bat -o install_pair.bat
.\install_pair.bat
```

Choose the `Install` option. The script installs the CLI to `%USERPROFILE%\AppData\Local\pair\pair.exe` and adds that directory to your user `PATH`.

## Uninstalling PairSpaces CLI

### macOS / Linux

Run the same `install.sh` script with the `uninstall` flag:

```bash
curl -fsSL https://raw.githubusercontent.com/pairspaces/install/main/install.sh | bash -s -- --uninstall
```

This will remove the installed binary from the target directory and delete config files in `~/.config/pair/`.

### Windows

Whether you downloaded `install_pair.bat` using `Invoke-WebRequest` or using cURL, run the `install_pair.bat` script and choose `Uninstall`.

This will remove the installed binary, remove the install directory from your `PATH`, and delete `%LOCALAPPDATA%\pair` and its contents.

## Testing Installation

```bash
pair help
```

You should see the CLI's usage output:

```
PairSpaces is for teams that work together. Learn more at https://pairspaces.com.

Usage:
  pair [command]

...
```

## Requirements

- **macOS/Linux:** `curl`, `bash`
- **Windows:** PowerShell 5.0+

## Support

Need help? Email support [at] pairspaces [dot] com.