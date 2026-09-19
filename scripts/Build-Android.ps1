[CmdletBinding()]
param(
	[ValidateSet("Debug", "Release")]
	[string]$Configuration = "Debug",
	[string]$JavaHome = ".tools\android\jdk\jdk-17.0.20+8",
	[string]$AndroidSdk = ".tools\android\sdk",
	[switch]$Clean
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidRoot = Join-Path $repositoryRoot ".build\android-source\android"
$javaHomePath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $JavaHome))
$androidSdkPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $AndroidSdk))
if (-not (Test-Path -LiteralPath (Join-Path $javaHomePath "bin\java.exe") -PathType Leaf)) {
	throw "JDK 17 was not found at $javaHomePath. Run scripts\Setup-AndroidToolchain.ps1 first or pass -JavaHome."
}
if (-not (Test-Path -LiteralPath (Join-Path $androidSdkPath "platforms\android-35") -PathType Container)) {
	throw "Android SDK platform 35 was not found at $androidSdkPath. Run scripts\Setup-AndroidToolchain.ps1 first or pass -AndroidSdk."
}
# Always go through Prepare: with existing staging it re-assembles the game
# when mod sources changed and re-syncs every current Theocraft mod into the
# staging tree, so Gradle can never silently package stale game files.
# -Clean wipes the generated staging first for a from-scratch rebuild.
if ($Clean) {
	& (Join-Path $PSScriptRoot "Prepare-Android.ps1") -Refresh
} else {
	& (Join-Path $PSScriptRoot "Prepare-Android.ps1")
}

$env:JAVA_HOME = $javaHomePath
$env:ANDROID_HOME = $androidSdkPath
$env:ANDROID_SDK_ROOT = $androidSdkPath
$env:ANDROID_USER_HOME = Join-Path $repositoryRoot ".tools\android\user"
$env:GRADLE_USER_HOME = Join-Path $repositoryRoot ".tools\android\gradle"
$env:PATH = (Join-Path $javaHomePath "bin") + ";" + (Join-Path $androidSdkPath "platform-tools") + ";" + $env:PATH
New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME, $env:GRADLE_USER_HOME -Force | Out-Null
$sdkProperty = $androidSdkPath.Replace("\", "/")
Set-Content -LiteralPath (Join-Path $androidRoot "local.properties") -Value "sdk.dir=$sdkProperty" -Encoding ASCII

# Bump the Android build number on every build so each APK gets a new versionCode.
# The launcher (MainActivity.checkAppVersion) only re-unpacks the bundled game
# files when the versionCode changes; re-unpacking preserves worlds. Without this,
# our static version made reinstalls look identical, so a phone kept running the
# OLD unpacked mods and new /commands appeared as "invalid command".
$buildNumberFile = Join-Path $repositoryRoot ".tools\android\build-number.txt"
$buildNumber = 0
if (Test-Path -LiteralPath $buildNumberFile) {
	[int]::TryParse((Get-Content -LiteralPath $buildNumberFile -Raw).Trim(), [ref]$buildNumber) | Out-Null
}
$buildNumber = $buildNumber + 1
Set-Content -LiteralPath $buildNumberFile -Value $buildNumber -Encoding ASCII
$topGradle = Join-Path $androidRoot "build.gradle"
$gradleText = Get-Content -LiteralPath $topGradle -Raw
$gradleText = $gradleText -replace 'versionBuild",\s*\d+', "versionBuild"", $buildNumber"
# UTF-8 WITHOUT a BOM: Set-Content -Encoding UTF8 on PS 5.1 prepends a BOM that
# Gradle rejects ("Unexpected character '?'" on line 1).
[System.IO.File]::WriteAllText($topGradle, $gradleText, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Android build number: $buildNumber (new versionCode -> phone re-unpacks on next launch, keeping worlds)"

$task = if ($Configuration -eq "Release") { "assembleRelease" } else { "assembleDebug" }
$gradleWrapper = Join-Path $androidRoot "gradle\wrapper\gradle-wrapper.jar"
$java = Join-Path $javaHomePath "bin\java.exe"
Push-Location $androidRoot
try {
	& $java -classpath $gradleWrapper org.gradle.wrapper.GradleWrapperMain $task -PtheocraftEnglishOnly=true
	if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE" }
} finally {
	Pop-Location
}

Write-Output "Android build completed. APKs are under $androidRoot\app\build\outputs\apk."
