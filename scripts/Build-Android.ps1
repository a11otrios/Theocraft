[CmdletBinding()]
param(
	[ValidateSet("Debug", "Release")]
	[string]$Configuration = "Debug",
	[string]$JavaHome = ".tools\android\jdk\jdk-17.0.20+8",
	[string]$AndroidSdk = ".tools\android\sdk"
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
if (-not (Test-Path -LiteralPath $androidRoot)) {
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
