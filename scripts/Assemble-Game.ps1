[CmdletBinding()]
param(
	[string]$OutputDirectory = ".build\game"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$voxelibreSource = Join-Path $repositoryRoot "vendor\voxelibre"
$theocraftMods = @("theocraft_villagers", "theocraft_halloween", "theocraft_import")
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputDirectory))
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ".build"))

if (-not $outputPath.StartsWith($buildRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "OutputDirectory must resolve inside $buildRoot"
}
if (Test-Path -LiteralPath $outputPath) {
	throw "Generated game already exists at $outputPath. Remove that exact .build directory before rebuilding."
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
$settingSources = @(
	Join-Path $repositoryRoot "mods\theocraft_villagers\settingtypes.txt"
	Join-Path $repositoryRoot "mods\theocraft_halloween\settingtypes.txt"
)
$settingSections = @($settingSources | ForEach-Object { (Get-Content -LiteralPath $_ -Raw).Trim() })
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
