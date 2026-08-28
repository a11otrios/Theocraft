<#
.SYNOPSIS
    Build the Chatterbox villager voice pack from installed Piper voices.

.DESCRIPTION
    Chatterbox clones a voice from a short reference clip. This script turns each
    Piper voice model under .tools\piper\voices into a gender-named reference clip
    under .tools\chatterbox\voices, so villagers get distinct, accented voices.

    Add more variety by downloading more Piper voice models (rhasspy/piper-voices)
    into .tools\piper\voices and registering them in $VoiceRegistry below, then
    re-running this script. Run the gateway with -Voice chatterbox to use them.

.EXAMPLE
    .\scripts\Build-ChatterboxVoices.ps1
#>
[CmdletBinding()]
param(
    # Sentence spoken into each reference clip (varied phonemes, ~8-12s of speech).
    [string]$Text = "Hello there, traveller. It is a fine day for a bit of honest work around the village. Mind how you go, and watch out for the goats near the well."
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$piper = Join-Path $repositoryRoot ".tools\piper\piper\piper.exe"
$voiceDir = Join-Path $repositoryRoot ".tools\piper\voices"
$outDir = Join-Path $repositoryRoot ".tools\chatterbox\voices"

if (-not (Test-Path -LiteralPath $piper)) {
    throw "Piper not found at $piper. Install Piper + voices under .tools\piper first."
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Piper voice stem -> output clip name. The name MUST start with "male"/"female"
# so the gateway matches each villager to a clip of its gender. Add rows here as
# you download more Piper voices for more accents.
$VoiceRegistry = @(
    @{ Stem = "en_US-ryan-medium";                  Out = "male_us_ryan" }
    @{ Stem = "en_US-amy-medium";                   Out = "female_us_amy" }
    @{ Stem = "en_GB-alan-medium";                  Out = "male_gb_alan" }
    @{ Stem = "en_GB-jenny_dioco-medium";           Out = "female_gb_jenny" }
    @{ Stem = "en_GB-alba-medium";                  Out = "female_gb_scottish_alba" }
    @{ Stem = "en_GB-northern_english_male-medium"; Out = "male_gb_northern" }
    @{ Stem = "en_US-lessac-medium";                Out = "female_us_lessac" }
    @{ Stem = "en_US-hfc_female-medium";            Out = "female_us_hfc" }
    @{ Stem = "en_US-joe-medium";                   Out = "male_us_joe" }
    @{ Stem = "en_US-kristin-medium";               Out = "female_us_kristin" }
    # --- add more Piper .onnx models here for more accents/voices ---
)

$made = 0
foreach ($v in $VoiceRegistry) {
    $model = Join-Path $voiceDir ($v.Stem + ".onnx")
    if (-not (Test-Path -LiteralPath $model)) {
        Write-Host "  skip $($v.Out) (no model: $($v.Stem).onnx)" -ForegroundColor DarkGray
        continue
    }
    $outWav = Join-Path $outDir ($v.Out + ".wav")
    # Piper logs to stderr; in PowerShell 5.1 that trips NativeCommandError under
    # ErrorActionPreference=Stop, so run this one call with errors non-fatal and
    # check the real exit code instead.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $Text | & $piper --model $model --output_file $outWav 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $outWav)) {
        Write-Warning "  piper failed for $($v.Stem) (exit $code)"
        continue
    }
    Write-Host "  $($v.Out).wav  <- $($v.Stem)" -ForegroundColor Green
    $made++
}

Write-Host ""
Write-Host "Built $made voice clip(s) in $outDir" -ForegroundColor Cyan
if ($made -eq 0) { Write-Warning "No clips built - no matching Piper voice models found." }
