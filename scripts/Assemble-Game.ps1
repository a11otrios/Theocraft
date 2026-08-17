[CmdletBinding()]
param(
	[string]$OutputDirectory = ".build\game"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$voxelibreSource = Join-Path $repositoryRoot "vendor\voxelibre"
$theocraftMods = @("theocraft_villagers", "theocraft_import")
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
foreach ($modName in $theocraftMods) {
	$modSource = Join-Path $repositoryRoot "mods\$modName"
	$destinationMod = Join-Path $outputPath "mods\$modName"
	Copy-Item -LiteralPath $modSource -Destination $destinationMod -Recurse -Force
}

$gameConf = @"
title = Theocraft
description = A mobile voxel survival game with conversational, instruction-following villagers.
disallowed_mapgens = v6
version = 0.1.0
"@
Set-Content -LiteralPath (Join-Path $outputPath "game.conf") -Value $gameConf -Encoding UTF8

Write-Output "Assembled Theocraft game at $outputPath"
