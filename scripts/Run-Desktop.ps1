[CmdletBinding()]
param(
	[string]$EnginePath = ".tools\luanti-5.16.1-win64\luanti-5.16.1-win64\bin\luanti.exe",
	[string]$WorldName = "mvp-smoke",
	[string]$PlayerName = "TheocraftTester"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$engine = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $EnginePath))
$assembledGame = Join-Path $repositoryRoot ".build\game"
$profile = Join-Path $repositoryRoot ".tools\desktop-test"
$gameDirectory = Join-Path $profile "games\theocraft"
$worldDirectory = Join-Path $profile "worlds\$WorldName"
$configuration = Join-Path $profile "minetest.conf"
$log = Join-Path $profile "debug.txt"

if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
	throw "Luanti executable not found at $engine. Download the pinned 5.16.1 Windows archive or pass -EnginePath."
}
if (-not (Test-Path -LiteralPath (Join-Path $assembledGame "game.conf"))) {
	& (Join-Path $PSScriptRoot "Assemble-Game.ps1")
}

New-Item -ItemType Directory -Path (Split-Path $gameDirectory), (Split-Path $worldDirectory) -Force | Out-Null
& robocopy.exe $assembledGame $gameDirectory /E /XD .git .gitea /NFL /NDL /NJH /NJS
$robocopyExitCode = $LASTEXITCODE
if ($robocopyExitCode -ge 8) {
	throw "Failed to stage Theocraft for desktop testing (robocopy exit $robocopyExitCode)."
}
if (-not (Test-Path -LiteralPath $configuration)) {
	@"
secure.http_mods = theocraft_villagers
enable_remote_media_server = false
server_announce = false

# Talk to the local Ollama bridge (start it with scripts\Run-LlmGateway.ps1).
theocraft_llm_enabled = true
theocraft_llm_endpoint = http://127.0.0.1:8713/
theocraft_llm_model = qwen2.5:3b
theocraft_llm_allow_insecure_http = true
theocraft_llm_timeout_seconds = 30
"@ | Set-Content -LiteralPath $configuration -Encoding UTF8
}

$env:LUANTI_USER_PATH = $profile
$env:LUANTI_GAME_PATH = Split-Path $gameDirectory
Write-Output "Launching Theocraft desktop test world at $worldDirectory"
& $engine --go --gameid theocraft --world $worldDirectory --name $PlayerName --config $configuration --logfile $log
