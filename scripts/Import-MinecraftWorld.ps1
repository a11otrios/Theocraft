[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$Source,
	[Parameter(Mandatory = $true)]
	[string]$Destination,
	[string]$Mapping,
	[int]$MaxChunks,
	[switch]$Zip
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$arguments = @(
	(Join-Path $repositoryRoot "tools\world_import\import_world.py"),
	$Source,
	$Destination
)
if ($Mapping) { $arguments += @("--mapping", $Mapping) }
if ($MaxChunks -gt 0) { $arguments += @("--max-chunks", $MaxChunks) }
if ($Zip) { $arguments += "--zip" }

& python @arguments
if ($LASTEXITCODE -ne 0) { throw "Minecraft world import failed with exit code $LASTEXITCODE" }
