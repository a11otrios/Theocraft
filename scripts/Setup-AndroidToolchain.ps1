[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toolsRoot = Join-Path $repositoryRoot ".tools\android"
$downloads = Join-Path $repositoryRoot ".tools\downloads"
$jdkArchive = Join-Path $downloads "microsoft-jdk-17.0.20-windows-x64.zip"
$jdkChecksum = "E46FD292317C6BB0A8FE9DC63115021329F3A63CAEBA791C185F89F3666A68E5"
$commandToolsArchive = Join-Path $downloads "commandlinetools-win-15859902_latest.zip"
$commandToolsChecksum = "90AE805D20434428BFFCB699C290860F19BB5F66A67E6B330067E3DE801FB04A"
$javaHome = Join-Path $toolsRoot "jdk\jdk-17.0.20+8"
$commandTools = Join-Path $toolsRoot "cmdline\cmdline-tools\bin\sdkmanager.bat"
$sdkRoot = Join-Path $toolsRoot "sdk"

function Get-VerifiedArchive([string]$Uri, [string]$Destination, [string]$ExpectedChecksum) {
	if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
		Invoke-WebRequest -Uri $Uri -OutFile $Destination
	}
	$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
	if ($actual -ne $ExpectedChecksum) {
		throw "Checksum mismatch for $Destination (expected $ExpectedChecksum, got $actual)."
	}
}

New-Item -ItemType Directory -Path $downloads, $toolsRoot, $sdkRoot -Force | Out-Null
Get-VerifiedArchive `
	-Uri "https://aka.ms/download-jdk/microsoft-jdk-17.0.20-windows-x64.zip" `
	-Destination $jdkArchive `
	-ExpectedChecksum $jdkChecksum
Get-VerifiedArchive `
	-Uri "https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip" `
	-Destination $commandToolsArchive `
	-ExpectedChecksum $commandToolsChecksum

if (-not (Test-Path -LiteralPath (Join-Path $javaHome "bin\java.exe") -PathType Leaf)) {
	New-Item -ItemType Directory -Path (Join-Path $toolsRoot "jdk") -Force | Out-Null
	Expand-Archive -LiteralPath $jdkArchive -DestinationPath (Join-Path $toolsRoot "jdk")
}
if (-not (Test-Path -LiteralPath $commandTools -PathType Leaf)) {
	New-Item -ItemType Directory -Path (Join-Path $toolsRoot "cmdline") -Force | Out-Null
	Expand-Archive -LiteralPath $commandToolsArchive -DestinationPath (Join-Path $toolsRoot "cmdline")
}

$env:JAVA_HOME = $javaHome
$env:ANDROID_USER_HOME = Join-Path $toolsRoot "user"
New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME -Force | Out-Null
Write-Output "If this is the first setup, accept the standard Android SDK license when prompted."
& $commandTools --sdk_root=$sdkRoot --licenses
& $commandTools --sdk_root=$sdkRoot `
	"platform-tools" `
	"platforms;android-34" `
	"platforms;android-35" `
	"build-tools;35.0.0" `
	"ndk;29.0.14206865" `
	"cmake;3.22.1"
if ($LASTEXITCODE -ne 0) { throw "Android SDK package installation failed with exit code $LASTEXITCODE" }
Write-Output "Android toolchain installed under $toolsRoot"
