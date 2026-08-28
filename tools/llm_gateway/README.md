# Local Ollama villager gateway

A tiny, dependency-free bridge that lets Theocraft villagers talk to a **local**
LLM running under [Ollama](https://ollama.com), instead of a remote provider. It
implements the `version: 1` contract in [`docs/llm-gateway.md`](../../docs/llm-gateway.md)
on one side and calls Ollama's `/api/chat` on the other.

Nothing leaves your machine, there is no API key, and it works offline.

## 1. Install Ollama and a model

```powershell
winget install --id Ollama.Ollama -e
ollama pull qwen2.5:3b
```

**Model suggestion.** `qwen2.5:3b` (~2 GB) is the sweet spot for staying in
character while emitting clean actions. The model is just a config string, so you
can swap it any time:

| Model             | Size    | Notes                                             |
|-------------------|---------|---------------------------------------------------|
| `qwen2.5:3b`      | ~2 GB   | Recommended default.                              |
| `qwen2.5:1.5b`    | ~1 GB   | Smallest that still holds a conversation.         |
| `llama3.2:1b`     | ~1.3 GB | Fastest/tiniest; weakest at open chat.            |
| `falcon-mamba:7b` | ~4 GB   | Mamba/SSM, for curiosity. Long-context edge is wasted here (history is capped at ~20 turns). |

## 2. Run the bridge

```powershell
.\scripts\Run-LlmGateway.ps1
```

It checks Ollama, pulls the model if needed, prints the desktop and phone
endpoints, and starts serving on port **8713**. Leave it running while you play.

Direct alternative (no helper script):

```powershell
python .\tools\llm_gateway\serve.py
```

Sanity-check it with curl:

```bash
curl -s -X POST http://127.0.0.1:8713/ -H "Content-Type: application/json" \
  -d '{"version":1,"villager":{"name":"Ada","bio":"A farmer","profession":"farmer"},"player":{"name":"me"},"message":"Please follow me","history":[],"allowed_actions":[{"type":"none"},{"type":"follow"}]}'
# -> {"speech": "...", "action": {"type": "follow"}}
```

## 3. Point Theocraft at it

The bridge is plain HTTP, so you must allow the insecure gateway
(`theocraft_llm_allow_insecure_http = true`). Set these under the game's advanced
settings, or in the world's `minetest.conf`.

**Desktop (same PC):**

```
theocraft_llm_enabled = true
theocraft_llm_endpoint = http://127.0.0.1:8713/
theocraft_llm_model = qwen2.5:3b
theocraft_llm_allow_insecure_http = true
theocraft_llm_timeout_seconds = 30
```

`.\scripts\Run-Desktop.ps1` writes these automatically into a fresh test profile.

**Phone on the same Wi-Fi:** identical, but use the PC's LAN IP that the run
script prints, e.g.

```
theocraft_llm_endpoint = http://192.168.1.42:8713/
```

You also need the port open on the PC. One-time Windows Firewall rule (run as
admin, adjust the port if you changed it):

```powershell
New-NetFirewallRule -DisplayName "Theocraft villager gateway" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8713
```

Optionally set a shared token so a random device on your network can't drive your
villagers: pass `-Token secret123` to the run script **and** set
`theocraft_llm_access_token = secret123` in the game.

## 4. Villager voices (text-to-speech, optional)

The gateway can also speak each reply and return it as a clip the game plays out
of the villager. `Run-LlmGateway.ps1 -Voice auto` (the default) uses **Piper** if
it is installed, otherwise the **Windows built-in voices**.

Encoding the audio needs one small Python package (bundles libsndfile, no system
binary):

```powershell
python -m pip install soundfile
```

**Windows voices (SAPI) — zero setup.** Uses whatever voices Windows has
installed; each villager gets a stable voice + speaking rate. Limited to the
installed voices (often one or two). `.\scripts\Run-LlmGateway.ps1 -Voice sapi`.

**Piper — natural voices with genders and accents (recommended).** Download the
Windows build and a few voice models into `.tools\piper`:

```
.tools\piper\piper\piper.exe                       # from rhasspy/piper releases
.tools\piper\voices\en_US-ryan-medium.onnx (+.json)   # male, US
.tools\piper\voices\en_GB-alan-medium.onnx (+.json)   # male, GB
.tools\piper\voices\en_US-amy-medium.onnx (+.json)    # female, US
.tools\piper\voices\en_GB-jenny_dioco-medium.onnx (+.json) # female, GB
```

Voice models come from the `rhasspy/piper-voices` repository. `Run-LlmGateway.ps1`
auto-detects this layout; each villager is matched to a voice of its (name-derived)
gender, chosen stably by id, so a villager always sounds the same. Add more
`.onnx` voices and register them in `PIPER_VOICE_REGISTRY` in `serve.py`.

**Chatterbox — neural voices, the best-sounding option.** [Chatterbox](https://github.com/resemble-ai/chatterbox)
(Resemble AI) is an AI text-to-speech that sounds far more natural than Piper or
SAPI, and can clone a voice from a short reference clip. It needs the pip package
(pulls in `torch`) and works best on the GPU:

```powershell
python -m pip install chatterbox-tts
.\scripts\Run-LlmGateway.ps1 -Voice chatterbox
```

The first reply is slow (the model loads once), then it's cached. On a GPU each
line takes a second or two; on CPU it works but is several seconds per line.

Per-villager voices (optional): drop a few short reference clips into
`.tools\chatterbox\voices`, named starting `male` or `female`
(e.g. `male_ryan.wav`, `female_amy.wav`). Each villager is matched to a clip of
its (name-derived) gender, stable by id, and its voice is cloned from that clip.
With no clips, all villagers share Chatterbox's built-in voice (still nudged a
little per villager). Point at a different folder with `-VoiceDir <path>`.

**Building a voice pack from Piper.** If Piper is installed (see above),
`.\scripts\Build-ChatterboxVoices.ps1` turns each Piper voice into an accented
reference clip automatically (US/GB male/female out of the box). Download more
Piper voice models (Scottish, Northern English, more speakers) into
`.tools\piper\voices`, add them to the registry in that script, and re-run it for
more variety.

**Isolation (important).** Chatterbox pulls in `numpy`/`antlr` versions that
conflict with this repo's dev tools (`luaparser`). It therefore runs from its own
virtual environment at `.tools\tts-venv`, which `Run-LlmGateway.ps1 -Voice
chatterbox` uses automatically. Create it once with:

```powershell
python -m venv .tools\tts-venv
.\.tools\tts-venv\Scripts\python -m pip install chatterbox-tts soundfile
.\.tools\tts-venv\Scripts\python -m pip install --force-reinstall --no-deps `
  torch==2.6.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu124
.\.tools\tts-venv\Scripts\python -m pip install "setuptools<81"
```

Disable voices entirely with `-Voice none`.

## Troubleshooting

**Ollama crashes with a CUDA / GPU error** (e.g. `llama-server process has
terminated ... CUDA error`, or the bridge keeps returning 502). Ollama's GPU
backend is failing on this machine. Run on CPU instead — `qwen2.5:3b` answers a
villager in a few seconds on CPU:

```powershell
.\scripts\Run-LlmGateway.ps1 -CpuOnly
```

(Equivalently, set `OLLAMA_NUM_GPU=0` before starting `serve.py`.) A proper GPU
fix usually means updating the NVIDIA driver and/or Ollama.

## How it stays fast (KV-cache reuse)

Ollama/llama.cpp keeps the model's KV cache and reuses the longest common
**prefix** of back-to-back prompts while the model stays loaded (`keep_alive`,
default 30 min). The bridge builds an **append-only** prompt to make that cache
hit: the system message holds only the stable villager persona (no positions or
other per-turn data), conversation history is emitted verbatim in order, and only
the newest turn changes each request. So each reply only processes the new tokens,
not the whole conversation again.

The bridge itself is **stateless** — it stores no sessions and relies on Ollama's
slot cache, which survives bridge restarts. For several players/villagers talking
at once, raise Ollama's parallelism with the `OLLAMA_NUM_PARALLEL` environment
variable before starting Ollama.

## Safety

Every action the model picks is re-validated and clamped by the game
(`mods/theocraft_villagers/policy.lua`): unknown action types become `none`,
counts are clamped, ranges and protected areas are enforced, and arbitrary
node/command execution is rejected. If the bridge or Ollama is unavailable, slow,
or returns garbage, the game transparently falls back to its built-in offline
instruction interpreter.

## Configuration reference

All optional, via environment variables (the run script sets the common ones):

| Variable                   | Default                  | Meaning                                        |
|----------------------------|--------------------------|------------------------------------------------|
| `GATEWAY_HOST`             | `0.0.0.0`                | Bind address (0.0.0.0 lets the phone connect). |
| `GATEWAY_PORT`             | `8713`                   | Bind port.                                      |
| `THEOCRAFT_GATEWAY_TOKEN`  | *(unset)*                | If set, require `Authorization: Bearer <token>`.|
| `OLLAMA_URL`               | `http://127.0.0.1:11434` | Ollama base URL.                                |
| `OLLAMA_MODEL`             | `qwen2.5:3b`             | Fallback model when the request omits one.      |
| `OLLAMA_KEEP_ALIVE`        | `30m`                    | How long Ollama keeps the model + cache loaded. |
| `OLLAMA_NUM_PREDICT`       | `200`                    | Max reply tokens.                               |
| `OLLAMA_TEMPERATURE`       | `0.7`                    | Sampling temperature.                           |
| `OLLAMA_TIMEOUT`           | `60`                     | Seconds to wait on Ollama.                      |
| `TTS_ENABLED`              | *(unset)*                | Set to `1` to synthesize villager voices.       |
| `TTS_ENGINE`               | `piper`                  | `chatterbox`, `piper`, `sapi`, `espeak`, or `none`. |
| `PIPER_BIN`                | `piper`                  | Path to `piper.exe`.                             |
| `PIPER_VOICE_DIR`          | *(unset)*                | Folder holding the Piper `.onnx` voice models.  |
| `CHATTERBOX_DEVICE`        | *(auto)*                 | `cuda` or `cpu`; auto-detects the GPU by default. |
| `CHATTERBOX_VOICE_DIR`     | *(unset)*                | Folder of reference voice clips (gender-named).  |
| `CHATTERBOX_EXAGGERATION`  | `0.5`                    | Base emotion/intensity, 0..1.                    |
| `CHATTERBOX_CFG`           | `0.5`                    | Pacing / cfg_weight, 0..1 (lower = slower).      |
