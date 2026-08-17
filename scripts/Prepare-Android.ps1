[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$engineSource = Join-Path $repositoryRoot "vendor\luanti"
$stagingRoot = Join-Path $repositoryRoot ".build\android-source"
$gameStaging = Join-Path $repositoryRoot ".build\game"

if (Test-Path -LiteralPath $stagingRoot) {
	throw "Android staging already exists at $stagingRoot. Remove that exact .build directory before rebuilding."
}
if (-not (Test-Path -LiteralPath (Join-Path $engineSource "android\gradlew"))) {
	throw "Luanti submodule is missing. Run git submodule update --init --depth 1."
}
if (-not (Test-Path -LiteralPath $gameStaging)) {
	& (Join-Path $PSScriptRoot "Assemble-Game.ps1")
}

New-Item -ItemType Directory -Path $stagingRoot | Out-Null
& robocopy.exe $engineSource $stagingRoot /E /XD .git build .gradle /NFL /NDL /NJH /NJS
$robocopyExitCode = $LASTEXITCODE
if ($robocopyExitCode -ge 8) {
	throw "Failed to stage Luanti source (robocopy exit $robocopyExitCode)."
}

$gamesDirectory = Join-Path $stagingRoot "games"
New-Item -ItemType Directory -Path $gamesDirectory -Force | Out-Null
Copy-Item -LiteralPath $gameStaging -Destination (Join-Path $gamesDirectory "theocraft") -Recurse -Force

Push-Location $repositoryRoot
try {
	git apply --unidiff-zero --directory=.build/android-source (Join-Path $repositoryRoot "patches\luanti-5.16.1-theocraft.patch")
	if ($LASTEXITCODE -ne 0) { throw "The Luanti Android patch did not apply cleanly." }
} finally {
	Pop-Location
}

Write-Output "Prepared branded Android source at $stagingRoot\android"
