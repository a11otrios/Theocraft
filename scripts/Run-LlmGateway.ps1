<#
.SYNOPSIS
    Run the local Theocraft -> Ollama villager gateway.

.DESCRIPTION
    Verifies Ollama is installed and reachable, pulls the requested model if it
    is not present, prints the LAN address to use from an Android phone, then
    launches tools/llm_gateway/serve.py.

.EXAMPLE
    .\scripts\Run-LlmGateway.ps1
    .\scripts\Run-LlmGateway.ps1 -Model qwen2.5:1.5b -Port 8713 -Token secret123
#>
[CmdletBinding()]
param(
    [string]$Model = "qwen2.5:3b",
    [int]$Port = 8713,
    [string]$Token = "",
    [string]$KeepAlive = "30m",
    # Force CPU inference. Use this if Ollama's GPU/CUDA backend crashes
    # (e.g. "llama-server process has terminated ... CUDA error").
    [switch]$CpuOnly,
    # Villager text-to-speech engine. "auto" uses Piper if it's installed under
    # .tools\piper, otherwise the Windows built-in voices (SAPI); "chatterbox" is
    # the neural voice (needs the chatterbox-tts pip package; GPU recommended);
    # "none" disables.
    [ValidateSet("auto", "chatterbox", "piper", "sapi", "none")]
    [string]$Voice = "auto",
    # Optional folder of reference voice clips for -Voice chatterbox (files named
    # starting "male"/"female"). Defaults to .tools\chatterbox\voices if present.
    [string]$VoiceDir = ""
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$serve = Join-Path $repositoryRoot "tools\llm_gateway\serve.py"

# Locate ollama.exe (PATH first, then the default winget install location).
$ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollama) {
    $default = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
    if (Test-Path -LiteralPath $default) { $ollama = $default }
}
if (-not $ollama) {
    throw "Ollama not found. Install it (winget install --id Ollama.Ollama) and re-run."
}

# Ensure the Ollama service answers before doing anything else.
try {
    Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/version" -TimeoutSec 5 | Out-Null
} catch {
    throw "Ollama service is not responding on 127.0.0.1:11434. Start Ollama and re-run."
}

# Pull the model if it is not already available locally.
$installed = (& $ollama list) 2>$null
if ($installed -notmatch [regex]::Escape($Model)) {
    Write-Host "Pulling model $Model (first time only)..." -ForegroundColor Cyan
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Failed to pull model $Model." }
}

# Find a LAN IPv4 address to show for the phone.
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $lanIp) { $lanIp = "<this-pc-lan-ip>" }

Write-Host ""
Write-Host "Theocraft villager gateway" -ForegroundColor Green
Write-Host "  Desktop endpoint : http://127.0.0.1:$Port/"
Write-Host "  Phone endpoint   : http://${lanIp}:$Port/   (same Wi-Fi; allow the port through the firewall)"
Write-Host "  Model            : $Model"
if ($Token) { Write-Host "  Gateway token    : required (set the same token in the game)" }
Write-Host ""

# Hand configuration to serve.py via environment and launch it.
$env:GATEWAY_PORT = "$Port"
$env:OLLAMA_MODEL = $Model
$env:OLLAMA_KEEP_ALIVE = $KeepAlive
$env:THEOCRAFT_GATEWAY_TOKEN = $Token
if ($CpuOnly) {
    $env:OLLAMA_NUM_GPU = "0"
    Write-Host "  Inference        : CPU only" -ForegroundColor Yellow
}

# Villager voices (text-to-speech). Resolve "auto" to Piper when it is installed,
# otherwise the Windows built-in voices.
$piperExe = Join-Path $repositoryRoot ".tools\piper\piper\piper.exe"
$piperVoices = Join-Path $repositoryRoot ".tools\piper\voices"
$piperReady = (Test-Path -LiteralPath $piperExe) -and (Test-Path -LiteralPath $piperVoices)
$engine = $Voice
if ($engine -eq "auto") { $engine = if ($piperReady) { "piper" } else { "sapi" } }

if ($engine -eq "none") {
    $env:TTS_ENABLED = ""
    Write-Host "  Villager voices  : off" -ForegroundColor Yellow
} else {
    $env:TTS_ENABLED = "1"
    $env:TTS_ENGINE = $engine
    if ($engine -eq "piper") {
        if (-not $piperReady) { throw "Piper not found under .tools\piper. Run with -Voice sapi, or install Piper." }
        $env:PIPER_BIN = $piperExe
        $env:PIPER_VOICE_DIR = $piperVoices
    }
    if ($engine -eq "chatterbox") {
        # Chatterbox lives in its own venv (isolated from the project's dev tools,
        # which need conflicting numpy/antlr versions). Require it.
        $ttsPython = Join-Path $repositoryRoot ".tools\tts-venv\Scripts\python.exe"
        if (-not (Test-Path -LiteralPath $ttsPython)) {
            throw "Chatterbox venv not found at .tools\tts-venv. Create it: python -m venv .tools\tts-venv; .\.tools\tts-venv\Scripts\python -m pip install chatterbox-tts soundfile"
        }
        # Reference voice clips: explicit -VoiceDir, else the default convention.
        if (-not $VoiceDir) {
            $defaultVoiceDir = Join-Path $repositoryRoot ".tools\chatterbox\voices"
            if (Test-Path -LiteralPath $defaultVoiceDir) { $VoiceDir = $defaultVoiceDir }
        }
        if ($VoiceDir) {
            $env:CHATTERBOX_VOICE_DIR = $VoiceDir
            Write-Host "  Voice clips      : $VoiceDir" -ForegroundColor Green
        } else {
            Write-Host "  Voice clips      : (none - using Chatterbox's built-in voice)" -ForegroundColor Yellow
        }
    }
    Write-Host "  Villager voices  : $engine" -ForegroundColor Green
}

# Chatterbox must run under its dedicated venv; everything else uses system Python.
if ($engine -eq "chatterbox") {
    $python = Join-Path $repositoryRoot ".tools\tts-venv\Scripts\python.exe"
} else {
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
}
if (-not $python) { throw "Python not found on PATH." }

& $python $serve
