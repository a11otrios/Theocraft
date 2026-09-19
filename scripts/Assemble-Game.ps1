[CmdletBinding()]
param(
	[string]$OutputDirectory = ".build\game",
	[switch]$Refresh
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$voxelibreSource = Join-Path $repositoryRoot "vendor\voxelibre"
$theocraftMods = @("theocraft_villagers", "theocraft_halloween", "theocraft_circus", "theocraft_import")
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputDirectory))
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ".build"))

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

if (-not $outputPath.StartsWith($buildRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "OutputDirectory must resolve inside $buildRoot"
}
if (Test-Path -LiteralPath $outputPath) {
	if ($Refresh) {
		Write-Output "Removing stale generated game at $outputPath"
		Remove-GeneratedDirectory $outputPath $buildRoot
	} else {
		throw "Generated game already exists at $outputPath. Remove that exact .build directory before rebuilding, or re-run with -Refresh."
	}
}
if (-not (Test-Path -LiteralPath (Join-Path $voxelibreSource "game.conf"))) {
	throw "VoxeLibre submodule is missing. Run git submodule update --init --depth 1."
}

New-Item -ItemType Directory -Path $outputPath | Out-Null
& robocopy.exe $voxelibreSource $outputPath /E /XD .git .gitea /NFL /NDL /NJH /NJS
$robocopyExitCode = $LASTEXITCODE
if ($robocopyExitCode -ge 8) {
	throw "Failed to stage VoxeLibre (robocopy exit $robocopyExitCode)."
}

# Upstream vl_hudbars calls mcl_gamemode.register_on_gamemode_change but only
# declares "depends = mcl_util". On some mod load orders (observed on Android)
# mcl_gamemode loads after vl_hudbars, so the global is nil and the game fails
# to start with "attempt to index global 'mcl_gamemode'". Force the dependency.
$hudbarsConf = Join-Path $outputPath "mods\HUD\vl_hudbars\mod.conf"
if (Test-Path -LiteralPath $hudbarsConf) {
	$hudbarsText = Get-Content -LiteralPath $hudbarsConf -Raw
	if ($hudbarsText -notmatch "mcl_gamemode") {
		$hudbarsText = $hudbarsText -replace "(?m)^(depends\s*=.*)$", '$1, mcl_gamemode'
		Set-Content -LiteralPath $hudbarsConf -Value $hudbarsText -Encoding UTF8
	}
}

foreach ($modName in $theocraftMods) {
	$modSource = Join-Path $repositoryRoot "mods\$modName"
	$destinationMod = Join-Path $outputPath "mods\$modName"
	Copy-Item -LiteralPath $modSource -Destination $destinationMod -Recurse -Force
}

# Luanti's main-menu Advanced Settings parser reads a bundled game's root
# settingtypes.txt, but does not scan mods that live inside that game. Merge the
# Theocraft mod settings there so every bundled feature is discoverable.
# The upstream VoxeLibre catalogue must come first and stay intact: without it
# the game would lose all of its own documented settings.
$voxelibreSettings = Join-Path $voxelibreSource "settingtypes.txt"
if (-not (Test-Path -LiteralPath $voxelibreSettings -PathType Leaf)) {
	throw "VoxeLibre settingtypes.txt is missing at $voxelibreSettings. Run git submodule update --init --depth 1."
}
$settingSources = @(
	Join-Path $repositoryRoot "mods\theocraft_villagers\settingtypes.txt"
	Join-Path $repositoryRoot "mods\theocraft_halloween\settingtypes.txt"
	Join-Path $repositoryRoot "mods\theocraft_circus\settingtypes.txt"
)
$baseText = (Get-Content -LiteralPath $voxelibreSettings -Raw).Trim()
$settingSections = @($baseText)
foreach ($source in $settingSources) {
	$section = (Get-Content -LiteralPath $source -Raw).Trim()
	$header = ($section -split "`r?`n")[0]
	if ($baseText.Contains($header) -or ($settingSections -join "`n").Contains($header)) {
		Write-Warning "Skipping duplicate settings section from $source ($header)"
		continue
	}
	$settingSections += $section
}
$settingText = ($settingSections -join ([Environment]::NewLine + [Environment]::NewLine)) + [Environment]::NewLine
[System.IO.File]::WriteAllText(
	(Join-Path $outputPath "settingtypes.txt"),
	$settingText,
	(New-Object System.Text.UTF8Encoding($false)))

$gameConf = @"
title = Theocraft
description = A mobile voxel survival game with conversational, instruction-following villagers.
disallowed_mapgens = v6
version = 0.1.0
"@
Set-Content -LiteralPath (Join-Path $outputPath "game.conf") -Value $gameConf -Encoding UTF8

Write-Output "Assembled Theocraft game at $outputPath"
