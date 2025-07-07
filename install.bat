@echo off
title PairSpaces CLI Installer

echo ===================================================
echo   PairSpaces. Work together and change the world.      
echo ===================================================
echo.
echo This script manages the PairSpaces CLI on Windows.
echo Please choose an option below:
echo.

echo [1] Install PairSpaces CLI
echo [2] Uninstall PairSpaces CLI
echo.

set /p choice=Enter 1 or 2, then press [Enter]: 

if "%choice%"=="1" goto install
if "%choice%"=="2" goto uninstall
echo.
echo That's not an option. Exiting...
goto end

:install
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$installerUrl='https://raw.githubusercontent.com/pairspaces/install/main/install.ps1'; $installerPath=$env:TEMP + '\install.ps1'; Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath; & $installerPath"
goto end

:uninstall
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "$installerUrl='https://raw.githubusercontent.com/pairspaces/install/main/install.ps1'; $installerPath=$env:TEMP + '\install.ps1'; Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath; & $installerPath -Uninstall"
goto end

:end
echo.
echo Press any key to exit.
pause >nul