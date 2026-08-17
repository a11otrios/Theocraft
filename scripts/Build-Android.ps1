[CmdletBinding()]
param(
	[ValidateSet("Debug", "Release")]
	[string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidRoot = Join-Path $repositoryRoot ".build\android-source\android"
if (-not (Test-Path -LiteralPath $androidRoot)) {
	& (Join-Path $PSScriptRoot "Prepare-Android.ps1")
}

$task = if ($Configuration -eq "Release") { "assembleRelease" } else { "assembleDebug" }
Push-Location $androidRoot
try {
	& .\gradlew.bat $task
	if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
} finally {
	Pop-Location
}

Write-Output "Android build completed. APKs are under $androidRoot\app\build\outputs\apk."
