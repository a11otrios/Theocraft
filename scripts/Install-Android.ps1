[CmdletBinding()]
param(
	[string]$Serial,
	[string]$AndroidSdk = ".tools\android\sdk"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sdkPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $AndroidSdk))
$adb = Join-Path $sdkPath "platform-tools\adb.exe"
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
	throw "ADB was not found at $adb. Run scripts\Setup-AndroidToolchain.ps1 first or pass -AndroidSdk."
}

$deviceRows = @(& $adb devices) |
	Select-Object -Skip 1 |
	Where-Object { $_ -match '^\S+\s+\S+' } |
	ForEach-Object {
		$columns = $_ -split '\s+', 3
		[pscustomobject]@{ Serial = $columns[0]; State = $columns[1] }
	}
if ($LASTEXITCODE -ne 0) { throw "ADB could not list connected devices." }

if ($Serial) {
	$device = $deviceRows | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
	if (-not $device) { throw "Android device '$Serial' is not connected." }
	if ($device.State -ne "device") {
		throw "Android device '$Serial' is $($device.State). Unlock the phone and approve the USB debugging prompt."
	}
} else {
	$authorized = @($deviceRows | Where-Object { $_.State -eq "device" })
	if ($authorized.Count -eq 0) {
		if ($deviceRows | Where-Object { $_.State -eq "unauthorized" }) {
			throw "The phone is connected but not authorized. Unlock it and approve the USB debugging prompt, then run this command again."
		}
		throw "No Android phone was detected. Enable USB debugging, connect an unlocked phone by USB, and select File transfer."
	}
	if ($authorized.Count -gt 1) {
		$serials = ($authorized.Serial -join ", ")
		throw "More than one Android device is connected ($serials). Pass -Serial with the device to install on."
	}
	$device = $authorized[0]
}

$abi = ((& $adb -s $device.Serial shell getprop ro.product.cpu.abi) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or -not $abi) { throw "Could not determine the phone's CPU architecture." }
if ($abi -notin @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")) {
	throw "The connected phone reports unsupported CPU architecture '$abi'."
}

$apkRelative = ".build\android-source\android\app\build\outputs\apk\debug\app-$abi-debug.apk"
$apkPath = Join-Path $repositoryRoot $apkRelative
& (Join-Path $PSScriptRoot "Verify-AndroidApk.ps1") -Apk $apkRelative -Abi $abi -AndroidSdk $AndroidSdk
if ($LASTEXITCODE -ne 0) { throw "APK verification failed." }

Write-Output "Installing Theocraft on $($device.Serial) ($abi)..."
& $adb -s $device.Serial install -r $apkPath
if ($LASTEXITCODE -ne 0) { throw "ADB installation failed with exit code $LASTEXITCODE." }
Write-Output "Theocraft is installed. Open it from the phone's app drawer."
