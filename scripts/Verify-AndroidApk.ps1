[CmdletBinding()]
param(
	[string]$Apk = ".build\android-source\android\app\build\outputs\apk\debug\app-arm64-v8a-debug.apk",
	[ValidateSet("arm64-v8a", "armeabi-v7a", "x86", "x86_64")]
	[string]$Abi = "arm64-v8a",
	[string]$AndroidSdk = ".tools\android\sdk"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$apkPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $Apk))
$sdkPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $AndroidSdk))
$aapt = Join-Path $sdkPath "build-tools\35.0.0\aapt2.exe"
$apkSigner = Join-Path $sdkPath "build-tools\35.0.0\apksigner.bat"
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { throw "APK not found: $apkPath" }
if (-not (Test-Path -LiteralPath $aapt -PathType Leaf)) { throw "aapt2 not found: $aapt" }

$badging = (& $aapt dump badging $apkPath) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "aapt2 could not inspect $apkPath" }
foreach ($required in @(
	"package: name='dev.theocraft.android'",
	"application-label:'Theocraft'",
	"uses-permission: name='android.permission.INTERNET'",
	"native-code: '$Abi'"
)) {
	if (-not $badging.Contains($required)) { throw "APK manifest check failed: missing $required" }
}
foreach ($label in (($badging -split "`n") | Where-Object { $_ -like "application-label*" })) {
	if (-not $label.EndsWith("'Theocraft'")) { throw "APK contains a non-Theocraft application label: $label" }
}

& $apkSigner verify $apkPath
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed" }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$outer = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
	if (-not $outer.GetEntry("lib/$Abi/libluanti.so")) { throw "APK does not contain libluanti.so for $Abi" }
	$assetsEntry = $outer.GetEntry("assets/assets.zip")
	if (-not $assetsEntry) { throw "APK does not contain assets/assets.zip" }
	$memory = [System.IO.MemoryStream]::new()
	$assetStream = $assetsEntry.Open()
	try { $assetStream.CopyTo($memory) } finally { $assetStream.Dispose() }
	$memory.Position = 0
	$assets = [System.IO.Compression.ZipArchive]::new($memory, [System.IO.Compression.ZipArchiveMode]::Read)
	try {
		foreach ($required in @(
			"games/theocraft/game.conf",
			"games/theocraft/mods/theocraft_villagers/init.lua",
			"games/theocraft/mods/theocraft_import/init.lua"
		)) {
			if (-not $assets.GetEntry($required)) { throw "Bundled game asset is missing: $required" }
		}
	} finally {
		$assets.Dispose()
		$memory.Dispose()
	}
} finally {
	$outer.Dispose()
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
Write-Output "Verified Theocraft $Abi APK: $apkPath"
Write-Output "SHA-256: $hash"
