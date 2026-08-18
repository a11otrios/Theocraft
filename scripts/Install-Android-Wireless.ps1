<#
.SYNOPSIS
    Install Theocraft on a phone over Wi-Fi (wireless ADB), no USB cable.

.DESCRIPTION
    Pairs and connects to a phone using Android 11+ Wireless debugging, then
    hands off to Install-Android.ps1 to install the already-built debug APK.

    On the phone: Settings -> Developer options -> Wireless debugging (turn on),
    then tap "Pair device with pairing code". That screen shows:
      * a pairing address  IP:PORT   and a 6-digit code   (use for -Pair / -Code)
    The main Wireless debugging screen shows a second, different port:
      * a connect address  IP:PORT             (use for -Connect)

.EXAMPLE
    .\scripts\Install-Android-Wireless.ps1 -Pair 192.168.1.50:37123 -Code 481920 -Connect 192.168.1.50:41567
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Pair,     # IP:PORT from the pairing-code dialog
    [Parameter(Mandatory = $true)][string]$Code,     # 6-digit pairing code
    [Parameter(Mandatory = $true)][string]$Connect,  # IP:PORT from the main Wireless debugging screen
    [string]$AndroidSdk = ".tools\android\sdk"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$adb = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot (Join-Path $AndroidSdk "platform-tools\adb.exe")))
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw "ADB not found at $adb. Run scripts\Setup-AndroidToolchain.ps1 first or pass -AndroidSdk."
}

Write-Host "Pairing with $Pair ..." -ForegroundColor Cyan
& $adb pair $Pair $Code
if ($LASTEXITCODE -ne 0) { throw "adb pair failed. Re-open the pairing dialog (the code/port change each time) and retry." }

Write-Host "Connecting to $Connect ..." -ForegroundColor Cyan
& $adb connect $Connect
if ($LASTEXITCODE -ne 0) { throw "adb connect failed. Check the connect address on the Wireless debugging screen." }

# Confirm the wireless device is authorized before installing.
Start-Sleep -Seconds 1
$devices = @(& $adb devices) -join "`n"
if ($devices -notmatch [regex]::Escape($Connect)) {
    Write-Warning "Device $Connect not listed yet. Current adb devices:`n$devices"
}

Write-Host "Installing Theocraft over Wi-Fi..." -ForegroundColor Green
& (Join-Path $PSScriptRoot "Install-Android.ps1") -Serial $Connect -AndroidSdk $AndroidSdk
