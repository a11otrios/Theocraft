[CmdletBinding()]
param(
	[switch]$Refresh
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$engineSource = Join-Path $repositoryRoot "vendor\luanti"
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ".build"))
$stagingRoot = Join-Path $repositoryRoot ".build\android-source"
$gameStaging = Join-Path $repositoryRoot ".build\game"
$theocraftMods = @("theocraft_villagers", "theocraft_halloween", "theocraft_circus", "theocraft_import")

function Remove-GeneratedDirectory {
	param([string]$TargetPath, [string]$BuildRoot)
	$resolved = [System.IO.Path]::GetFullPath($TargetPath)
	$prefix = $BuildRoot + [System.IO.Path]::DirectorySeparatorChar
	if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Refusing to remove ${resolved}: it is outside the generated $BuildRoot directory."
	}
	if ($resolved.TrimEnd([System.IO.Path]::DirectorySeparatorChar) -eq $BuildRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar)) {
		throw "Refusing to remove the build root itself ($BuildRoot)."
	}
	if (Test-Path -LiteralPath $resolved) {
		Remove-Item -LiteralPath $resolved -Recurse -Force
	}
}

# True when any Theocraft mod source is newer than the assembled game marker,
# meaning the staging would silently reuse stale mods without a rebuild.
function Test-TheocraftSourcesNewer {
	param([string]$MarkerPath)
	if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) { return $true }
	$markerTime = (Get-Item -LiteralPath $MarkerPath).LastWriteTimeUtc
	foreach ($modName in $theocraftMods) {
		$modDir = Join-Path $repositoryRoot "mods\$modName"
		$newest = Get-ChildItem -LiteralPath $modDir -Recurse -File -ErrorAction SilentlyContinue |
			Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
		if ($newest -and $newest.LastWriteTimeUtc -gt $markerTime) { return $true }
	}
	return $false
}

# Mirror the assembled Theocraft game content into the Android staging copy so
# a normal build never packages stale mods. Limited to the Theocraft game
# directory; patched engine files elsewhere in staging are never touched.
function Sync-TheocraftGameStaging {
	$destination = Join-Path $stagingRoot "games\theocraft"
	foreach ($modName in $theocraftMods) {
		& robocopy.exe (Join-Path $gameStaging "mods\$modName") (Join-Path $destination "mods\$modName") /MIR /NFL /NDL /NJH /NJS
		if ($LASTEXITCODE -ge 8) { throw "Failed to sync $modName into Android staging (robocopy exit $LASTEXITCODE)." }
	}
	Copy-Item -LiteralPath (Join-Path $gameStaging "settingtypes.txt") -Destination (Join-Path $destination "settingtypes.txt") -Force
	Copy-Item -LiteralPath (Join-Path $gameStaging "game.conf") -Destination (Join-Path $destination "game.conf") -Force
	Write-Output "Synchronized current Theocraft game content into Android staging."
}

if (-not (Test-Path -LiteralPath (Join-Path $engineSource "android\gradlew"))) {
	throw "Luanti submodule is missing. Run git submodule update --init --depth 1."
}

$freshStaging = $false
if (Test-Path -LiteralPath $stagingRoot) {
	if ($Refresh) {
		Write-Output "Removing stale Android staging at $stagingRoot"
		Remove-GeneratedDirectory $stagingRoot $buildRoot
		$freshStaging = $true
	}
} else {
	$freshStaging = $true
}

if (-not (Test-Path -LiteralPath $gameStaging)) {
	& (Join-Path $PSScriptRoot "Assemble-Game.ps1")
} elseif ($Refresh -or (Test-TheocraftSourcesNewer (Join-Path $gameStaging "game.conf"))) {
	if ($Refresh) {
		Write-Output "Re-assembling the game from current sources."
	} else {
		Write-Output "Theocraft mod sources changed since the last assembly; re-assembling the game from current sources."
	}
	& (Join-Path $PSScriptRoot "Assemble-Game.ps1") -Refresh
}

if ($freshStaging) {
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
} else {
	Sync-TheocraftGameStaging
}
