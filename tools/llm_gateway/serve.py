#!/usr/bin/env python3
"""Local bridge between Theocraft's villager gateway contract and Ollama.

Theocraft POSTs the ``version: 1`` JSON described in ``docs/llm-gateway.md`` and
expects ``{"speech": ..., "action": ...}`` back. Ollama speaks its own
``/api/chat`` protocol. This process translates between the two and runs on the
same machine (or LAN) as the game.

Design notes
------------
* **Dependency-free**: standard library only (``http.server`` + ``urllib``).
* **Stateless**: it keeps no per-conversation memory. Theocraft already sends the
  (capped) history on every request, and Ollama/llama.cpp reuses the KV cache for
  the longest common *prefix* of consecutive prompts while the model stays loaded
  (``keep_alive``). To make that cache actually hit, the prompt is built
  **append-only**: the system message holds only the *stable* villager persona
  (no positions or other per-turn-volatile data), history is emitted verbatim in
  order, and only the newest turn changes between requests.
* **Safe by construction**: the game re-validates and clamps every action
  (``mod.normalise_response`` / ``mod.normalise_action``), so the bridge can pass
  the model's choice straight through. On any Ollama error it returns HTTP 502 and
  the game falls back to its offline interpreter.

Configuration (environment variables)
-------------------------------------
* ``GATEWAY_HOST``            bind address           (default ``0.0.0.0`` so the phone can reach it)
* ``GATEWAY_PORT``            bind port              (default ``8713``)
* ``THEOCRAFT_GATEWAY_TOKEN`` optional shared secret; when set, requests must send ``Authorization: Bearer <token>``
* ``OLLAMA_URL``              Ollama base URL        (default ``http://127.0.0.1:11434``)
* ``OLLAMA_MODEL``            fallback model id used when the request omits ``model`` (default ``qwen2.5:3b``)
* ``OLLAMA_KEEP_ALIVE``       how long Ollama keeps the model + KV cache resident (default ``30m``)
* ``OLLAMA_NUM_PREDICT``      max reply tokens       (default ``200``)
* ``OLLAMA_TEMPERATURE``      sampling temperature   (default ``0.7``)
* ``OLLAMA_TIMEOUT``          seconds to wait on Ollama (default ``60``)
"""

from __future__ import annotations

import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GATEWAY_HOST = os.environ.get("GATEWAY_HOST", "0.0.0.0")
GATEWAY_PORT = int(os.environ.get("GATEWAY_PORT", "8713"))
GATEWAY_TOKEN = os.environ.get("THEOCRAFT_GATEWAY_TOKEN", "").strip()
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:3b")
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")
OLLAMA_NUM_PREDICT = int(os.environ.get("OLLAMA_NUM_PREDICT", "200"))
OLLAMA_TEMPERATURE = float(os.environ.get("OLLAMA_TEMPERATURE", "0.85"))
OLLAMA_TIMEOUT = float(os.environ.get("OLLAMA_TIMEOUT", "60"))
# Force CPU by setting OLLAMA_NUM_GPU=0 (useful when the GPU/CUDA backend
# crashes). Leave unset to let Ollama auto-detect the GPU.
_num_gpu = os.environ.get("OLLAMA_NUM_GPU", "").strip()
OLLAMA_NUM_GPU = int(_num_gpu) if _num_gpu else None

# Maximum request body we will read, to avoid an accidental huge payload.
MAX_BODY_BYTES = 256 * 1024

# ---------------------------------------------------------------------------
# Text-to-speech (optional). When enabled, the reply text is synthesized to an
# Ogg Vorbis clip and returned base64-encoded as ``audio_b64``; the game plays it
# out of the villager. Any failure just omits the audio so chat is never broken.
#
# * ``TTS_ENABLED``  turn the whole feature on (default off)
# * ``TTS_ENGINE``   piper | espeak | test | none  (default piper)
# * ``TTS_TEST_OGG`` engine=test: path to a fixed .ogg returned for every reply
#                    (used to prove client playback before installing a real TTS)
# * ``PIPER_BIN``    piper executable (default "piper")
# * ``PIPER_VOICES`` comma-separated .onnx voice models; one is picked per villager
# * ``PIPER_MODEL``  single default .onnx model (used if PIPER_VOICES is unset)
# * ``ESPEAK_BIN``   espeak-ng executable (default "espeak-ng")
# * ``FFMPEG_BIN``   ffmpeg executable used to encode WAV -> Ogg Vorbis (default "ffmpeg")
TTS_ENABLED = os.environ.get("TTS_ENABLED", "").strip().lower() in ("1", "true", "yes", "on")
TTS_ENGINE = os.environ.get("TTS_ENGINE", "piper").strip().lower()
TTS_TEST_OGG = os.environ.get("TTS_TEST_OGG", "").strip()
PIPER_BIN = os.environ.get("PIPER_BIN", "piper").strip()
# Directory holding the downloaded Piper .onnx voice models (+ .onnx.json).
PIPER_VOICE_DIR = os.environ.get("PIPER_VOICE_DIR", "").strip()

# Known voices and their (gender, accent). A villager is matched to a voice of
# its gender; the specific voice (hence accent) is then stable per villager id.
PIPER_VOICE_REGISTRY = [
    ("en_US-ryan-medium", "male", "US"),
    ("en_GB-alan-medium", "male", "GB"),
    ("en_US-amy-medium", "female", "US"),
    ("en_GB-jenny_dioco-medium", "female", "GB"),
]

# Villager first names (from the mod's identity.lua) mapped to a voice gender so
# obviously-gendered names get a matching voice. Unknown names fall back to a
# stable hash of the id.
NAME_GENDER = {
    "ada": "female", "anika": "female", "cora": "female", "dara": "female",
    "esme": "female", "farah": "female", "hana": "female", "jora": "female",
    "lina": "female", "mara": "female", "orla": "female", "rhea": "female",
    "talia": "female", "uma": "female", "vero": "female",
    "alden": "male", "bram": "male", "elian": "male", "galen": "male",
    "ivo": "male", "kellan": "male", "niko": "male", "pavel": "male", "soren": "male",
}
ESPEAK_BIN = os.environ.get("ESPEAK_BIN", "espeak-ng").strip()
FFMPEG_BIN = os.environ.get("FFMPEG_BIN", "ffmpeg").strip()


def describe_actions(allowed_actions):
    """Turn Theocraft's allowed_actions list into a compact, stable instruction."""
    lines = []
    for entry in allowed_actions or []:
        if not isinstance(entry, dict):
            continue
        atype = entry.get("type")
        if atype == "none":
            lines.append('- none: just talk, take no action.')
        elif atype == "follow":
            lines.append('- follow: start following the player.')
        elif atype == "stay":
            lines.append('- stay: stop and wait here.')
        elif atype == "come":
            lines.append('- come: walk over to the player.')
        elif atype == "gather":
            resources = ", ".join(str(r) for r in entry.get("resources", []))
            max_count = entry.get("max_count", 8)
            lines.append(
                f'- gather: collect a resource. Include "resource" (one of: {resources}) '
                f'and "count" (1-{max_count}).'
            )
        elif atype == "build":
            blueprints = ", ".join(str(b) for b in entry.get("blueprints", []))
            lines.append(f'- build: construct something. Include "blueprint" (one of: {blueprints}).')
        elif atype == "goto":
            landmarks = ", ".join(str(l) for l in entry.get("landmarks", []))
            lines.append(
                f'- goto: walk to a named landmark and wait there. '
                f'Include "landmark" (one of: {landmarks}).'
            )
        elif atype == "guard":
            landmarks = ", ".join(str(l) for l in entry.get("landmarks", []))
            lines.append(
                f'- guard: stand watch at a spot. Optionally include "landmark" '
                f'(one of: {landmarks}); omit it to guard where you are.'
            )
        elif atype == "patrol":
            landmarks = ", ".join(str(l) for l in entry.get("landmarks", []))
            lines.append(
                f'- patrol: walk a loop between landmarks. '
                f'Include "landmarks", a list of 2+ from: {landmarks}.'
            )
        elif atype == "deliver":
            destinations = ", ".join(str(d) for d in entry.get("destinations", []))
            lines.append(
                f'- deliver: carry what you have gathered to a destination. '
                f'Include "destination" (one of: {destinations}).'
            )
    return "\n".join(lines)


# Give each villager a distinct, consistent character. Traits are picked
# deterministically from the villager's id/name so the same villager always has
# the same personality, but different villagers differ.
PERSONALITIES = [
    "warm, chatty, and quick to laugh",
    "gruff and blunt, but kind underneath",
    "shy and soft-spoken, choosing your words carefully",
    "boastful and dramatic, always with a story to tell",
    "endlessly curious and a little bit nosy",
    "dry, sarcastic, and hard to impress",
    "cheerful and easily delighted by small things",
    "world-weary and a touch philosophical",
    "a hopeless gossip who loves village rumours",
    "practical and no-nonsense, straight to the point",
    "dreamy and poetic, with your head in the clouds",
    "anxious and fidgety, prone to worrying",
    "jolly and generous, treating everyone like an old friend",
    "proud and stubborn, quite set in your ways",
    "mischievous, with a teasing sense of humour",
]
INTERESTS = [
    "You love talking about food and whatever's cooking.",
    "You're a bit obsessed with the weather and the seasons.",
    "You always seem to have the latest village gossip.",
    "You miss the old days and love to reminisce.",
    "You're fascinated by the player as a stranger from far away.",
    "You collect odd little trinkets and like to show them off.",
    "You hum old songs and only half-remember the words.",
    "You fret about wolves and things that lurk in the dark.",
    "You take great pride in your trade.",
    "You secretly dream of leaving to see the wider world.",
    "You dote on the village animals.",
    "You love a good tall tale and tend to exaggerate.",
    "You have strong (and loud) opinions about your neighbours.",
    "You're a bit of a homebody who loves a quiet evening.",
]
MOODS = [
    "in a great mood today",
    "a little tired and grumpy today",
    "feeling especially talkative today",
    "feeling wistful today",
    "in unusually high spirits today",
    "a bit distracted today",
]


def _seed(text):
    """Small deterministic hash (Python's hash() is salted per process)."""
    h = 0
    for ch in text:
        h = (h * 131 + ord(ch)) & 0xFFFFFFFF
    return h


def build_system_prompt(payload):
    """Stable persona + rules. Deliberately excludes positions and other volatile data."""
    villager = payload.get("villager") or {}
    name = str(villager.get("name") or "the villager")
    profession = str(villager.get("profession") or "villager")
    bio = str(villager.get("bio") or "")
    extra = str(payload.get("system_prompt") or "").strip()
    actions = describe_actions(payload.get("allowed_actions"))

    seed = _seed(str(villager.get("id") or name))
    personality = PERSONALITIES[seed % len(PERSONALITIES)]
    interest = INTERESTS[(seed // 7) % len(INTERESTS)]
    mood = MOODS[(seed // 13) % len(MOODS)]

    parts = [
        f"You are {name}, a {profession} in a small village. {bio}".strip(),
        f"Your personality: you are {personality}. {interest} You're {mood}.",
        "You are a real, ordinary villager with your own life, moods, and opinions. You are "
        "NOT a helper, assistant, guide, shopkeeper, or quest-giver, and you are NOT an AI. "
        "The player is just some person who wandered up to you — you owe them nothing. "
        "NEVER say things like 'How can I help you?', 'What can I do for you?', 'I'm here to "
        "help', 'let me know if you need anything', or 'at your service'. NEVER list what you "
        "can do or offer your services. Don't be eager, polite, or peppy like a shop clerk. "
        "Just talk like a person mid-day: grumble, ramble, gossip, complain, joke, get "
        "distracted. React to what's said the way YOU would, with your own mood and opinions. "
        "Talk about your day, your trade, your aches, the neighbours, village rumours, the "
        "weather, or nose into the player's business instead. It's fine to be blunt, "
        "uninterested, or to answer a question with a question. Speak plainly, like real "
        "chatter — no fancy narration or stage directions. Keep it to 1-2 short sentences.",
    ]
    if extra:
        parts.append(extra)
    parts.append(
        "You may optionally perform ONE action, chosen only from this list:\n" + actions
    )
    parts.append(
        'Reply with ONLY a JSON object of the form '
        '{"speech": "<what you say out loud>", "action": {"type": "<one allowed type>"}}. '
        'Use {"type": "none"} when no action fits. Do not invent action types or extra fields.'
    )
    return "\n\n".join(parts)


KNOWN_ACTION_TYPES = [
    "none", "follow", "stay", "come", "gather", "build",
    "goto", "guard", "patrol", "deliver",
]


def build_format(payload):
    """A JSON schema constraining the reply shape, so even small models can't
    emit malformed or nested JSON. The action is an anyOf of per-type shapes
    limited to what this request allows, so e.g. a gather action is forced to
    carry a resource and count and a build action a blueprint."""
    variants = []
    for entry in payload.get("allowed_actions") or []:
        if not isinstance(entry, dict) or entry.get("type") not in KNOWN_ACTION_TYPES:
            continue
        atype = entry["type"]
        if atype == "gather":
            resources = [str(r) for r in entry.get("resources", [])] or ["wood", "stone", "dirt", "sand"]
            variants.append({
                "type": "object",
                "properties": {
                    "type": {"const": "gather"},
                    "resource": {"type": "string", "enum": resources},
                    "count": {"type": "integer"},
                },
                "required": ["type", "resource", "count"],
            })
        elif atype == "build":
            blueprints = [str(b) for b in entry.get("blueprints", [])] or ["wall", "shelter"]
            variants.append({
                "type": "object",
                "properties": {
                    "type": {"const": "build"},
                    "blueprint": {"type": "string", "enum": blueprints},
                },
                "required": ["type", "blueprint"],
            })
        elif atype == "goto":
            landmarks = [str(l) for l in entry.get("landmarks", [])]
            prop = {"type": "string"}
            if landmarks:
                prop["enum"] = landmarks
            variants.append({
                "type": "object",
                "properties": {"type": {"const": "goto"}, "landmark": prop},
                "required": ["type", "landmark"],
            })
        elif atype == "guard":
            landmarks = [str(l) for l in entry.get("landmarks", [])]
            prop = {"type": "string"}
            if landmarks:
                prop["enum"] = landmarks
            variants.append({
                "type": "object",
                "properties": {"type": {"const": "guard"}, "landmark": prop},
                "required": ["type"],  # landmark optional: omit to guard the current spot
            })
        elif atype == "patrol":
            landmarks = [str(l) for l in entry.get("landmarks", [])]
            item = {"type": "string"}
            if landmarks:
                item["enum"] = landmarks
            variants.append({
                "type": "object",
                "properties": {
                    "type": {"const": "patrol"},
                    "landmarks": {"type": "array", "items": item, "minItems": 2},
                },
                "required": ["type", "landmarks"],
            })
        elif atype == "deliver":
            destinations = [str(d) for d in entry.get("destinations", [])] or ["player"]
            variants.append({
                "type": "object",
                "properties": {
                    "type": {"const": "deliver"},
                    "destination": {"type": "string", "enum": destinations},
                },
                "required": ["type", "destination"],
            })
        else:  # none, follow, stay, come
            variants.append({
                "type": "object",
                "properties": {"type": {"const": atype}},
                "required": ["type"],
            })
    if not variants:
        variants.append({
            "type": "object",
            "properties": {"type": {"type": "string", "enum": list(KNOWN_ACTION_TYPES)}},
            "required": ["type"],
        })
    return {
        "type": "object",
        "properties": {
            "speech": {"type": "string"},
            "action": {"anyOf": variants},
        },
        "required": ["speech", "action"],
    }


def build_messages(payload):
    """Assemble the append-only chat: stable system, verbatim history, newest turn last."""
    messages = [{"role": "system", "content": build_system_prompt(payload)}]
    for turn in payload.get("history") or []:
        if not isinstance(turn, dict):
            continue
        role = "assistant" if turn.get("role") == "villager" else "user"
        content = str(turn.get("content") or "")
        if content:
            messages.append({"role": role, "content": content})
    # The final player message. The game already appends it to history before
    # sending, so guard against emitting it twice.
    message = str(payload.get("message") or "")
    if message and not (
        len(messages) > 1
        and messages[-1]["role"] == "user"
        and messages[-1]["content"] == message
    ):
        messages.append({"role": "user", "content": message})
    return messages


def call_ollama(payload):
    """Send the chat to Ollama and return the parsed assistant content string."""
    model = str(payload.get("model") or "").strip() or OLLAMA_MODEL
    request_body = {
        "model": model,
        "messages": build_messages(payload),
        "stream": False,
        "format": build_format(payload),
        "keep_alive": OLLAMA_KEEP_ALIVE,
        "options": {
            "temperature": OLLAMA_TEMPERATURE,
            "num_predict": OLLAMA_NUM_PREDICT,
        },
    }
    if OLLAMA_NUM_GPU is not None:
        request_body["options"]["num_gpu"] = OLLAMA_NUM_GPU
    data = json.dumps(request_body).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
        decoded = json.loads(resp.read().decode("utf-8"))
    return (decoded.get("message") or {}).get("content") or ""


def to_theocraft_response(content):
    """Coerce the model's content into {speech, action}. The game re-validates."""
    speech, action = "", {"type": "none"}
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict):
            speech = parsed.get("speech") or parsed.get("message") or ""
            raw_action = parsed.get("action")
            if isinstance(raw_action, dict):
                action = raw_action
            elif isinstance(raw_action, str):
                action = {"type": raw_action}
    except (ValueError, TypeError):
        # Not JSON (rare with format=json): treat the whole thing as speech.
        speech = content
    if not isinstance(speech, str) or not speech.strip():
        speech = content if isinstance(content, str) else ""
    return {"speech": speech, "action": action}


def _run(cmd, input_bytes=None):
    """Run a child process, return its stdout bytes. Raises on non-zero exit."""
    proc = subprocess.run(
        cmd,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return proc.stdout


def _wav_to_ogg(wav_bytes):
    """Encode WAV/PCM bytes to mono Ogg Vorbis (Luanti only plays Ogg, and only
    mono sounds play positionally). Prefers the `soundfile` library; falls back to
    ffmpeg if it isn't installed."""
    try:
        import soundfile as sf  # bundled libsndfile, no system binary needed
        data, sr = sf.read(io.BytesIO(wav_bytes), always_2d=True)
        mono = data.mean(axis=1)  # downmix -> mono so it plays from the villager
        buf = io.BytesIO()
        sf.write(buf, mono, sr, format="OGG", subtype="VORBIS")
        return buf.getvalue()
    except ImportError:
        return _run(
            [FFMPEG_BIN, "-hide_banner", "-loglevel", "error",
             "-f", "wav", "-i", "pipe:0", "-ac", "1", "-c:a", "libvorbis", "-f", "ogg", "pipe:1"],
            wav_bytes,
        )


def _sapi_wav(text, villager):
    """Synthesize `text` to WAV bytes using the Windows built-in voices (SAPI).
    Rate is nudged per villager so they don't all sound identical."""
    seed = _seed(str(villager.get("id") or villager.get("name") or ""))
    rate = (seed % 7) - 3  # -3..3, SAPI's speaking-rate range is -10..10
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wav_path = tf.name
    try:
        # Pick one of the installed voices deterministically per villager so
        # different villagers sound different (e.g. British vs American).
        script = (
            "Add-Type -AssemblyName System.Speech;"
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            "$v = @($s.GetInstalledVoices() | Where-Object { $_.Enabled });"
            "if ($v.Count -gt 0) {"
            " $s.SelectVoice($v[[int]$env:TC_VOICE_IDX % $v.Count].VoiceInfo.Name) };"
            f"$s.Rate = {rate};"
            "$s.SetOutputToWaveFile($env:TC_WAV);"
            "$s.Speak([Console]::In.ReadToEnd());"
            "$s.Dispose()"
        )
        env = dict(os.environ, TC_WAV=wav_path, TC_VOICE_IDX=str(seed))
        subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
            input=text.encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, env=env,
        )
        with open(wav_path, "rb") as fh:
            return fh.read()
    finally:
        try:
            os.remove(wav_path)
        except OSError:
            pass


def _villager_gender(villager):
    """A villager has no real gender, so derive one: by name when recognizable,
    otherwise a stable coin-flip on the id."""
    name = str(villager.get("name") or "").strip().lower()
    if name in NAME_GENDER:
        return NAME_GENDER[name]
    return "male" if _seed(str(villager.get("id") or name)) % 2 == 0 else "female"


def _pick_piper_voice(villager):
    """Pick a Piper model path: a voice of the villager's gender, chosen stably by
    id so each villager always sounds the same (and picks up that voice's accent)."""
    if not PIPER_VOICE_DIR:
        return None

    def available(stems):
        return [s for s in stems
                if os.path.exists(os.path.join(PIPER_VOICE_DIR, s + ".onnx"))]

    gender = _villager_gender(villager)
    pool = available([s for (s, g, _a) in PIPER_VOICE_REGISTRY if g == gender])
    if not pool:  # no voice of that gender downloaded -> any voice we have
        pool = available([s for (s, _g, _a) in PIPER_VOICE_REGISTRY])
    if not pool:
        return None
    key = str(villager.get("id") or villager.get("name") or "")
    return os.path.join(PIPER_VOICE_DIR, pool[_seed(key) % len(pool)] + ".onnx")


def synth_ogg(text, villager):
    """Synthesize `text` to Ogg Vorbis bytes for the given villager, or None."""
    text = (text or "").strip()
    if not text:
        return None
    try:
        if TTS_ENGINE == "test":
            if TTS_TEST_OGG and os.path.exists(TTS_TEST_OGG):
                with open(TTS_TEST_OGG, "rb") as fh:
                    return fh.read()
            return None
        if TTS_ENGINE == "sapi":
            return _wav_to_ogg(_sapi_wav(text, villager))
        if TTS_ENGINE == "piper":
            model = _pick_piper_voice(villager)
            if not model:
                return None
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
                wav_path = tf.name
            try:
                _run([PIPER_BIN, "--model", model, "--output_file", wav_path],
                     text.encode("utf-8"))
                with open(wav_path, "rb") as fh:
                    wav = fh.read()
            finally:
                try:
                    os.remove(wav_path)
                except OSError:
                    pass
            return _wav_to_ogg(wav)
        if TTS_ENGINE == "espeak":
            wav = _run([ESPEAK_BIN, "--stdout", text])
            return _wav_to_ogg(wav)
    except Exception as exc:  # noqa: BLE001 - TTS must never break the chat reply
        sys.stderr.write(f"[bridge] tts failed: {exc}\n")
    return None


def add_audio(response, payload):
    """Attach base64 Ogg audio to the response when TTS is enabled (best-effort)."""
    if not TTS_ENABLED or TTS_ENGINE in ("", "none"):
        return
    ogg = synth_ogg(response.get("speech"), payload.get("villager") or {})
    if ogg:
        response["audio_b64"] = base64.b64encode(ogg).decode("ascii")
        response["audio_format"] = "ogg"


class Handler(BaseHTTPRequestHandler):
    server_version = "TheocraftOllamaBridge/1.0"

    def _send_json(self, status, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        if not GATEWAY_TOKEN:
            return True
        header = self.headers.get("Authorization", "")
        return header == f"Bearer {GATEWAY_TOKEN}"

    def do_GET(self):
        self._send_json(200, {"status": "ok", "model": OLLAMA_MODEL, "ollama": OLLAMA_URL})

    def do_POST(self):
        if not self._authorized():
            return self._send_json(401, {"error": "invalid or missing gateway token"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            return self._send_json(400, {"error": "missing or oversized request body"})
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self._send_json(400, {"error": "request body is not valid JSON"})

        try:
            content = call_ollama(payload)
        except urllib.error.URLError as exc:
            # Ollama down / model missing / timeout -> game uses offline fallback.
            return self._send_json(502, {"error": f"ollama request failed: {exc}"})
        except Exception as exc:  # noqa: BLE001 - report anything else as a gateway error
            return self._send_json(502, {"error": f"gateway error: {exc}"})

        response = to_theocraft_response(content)
        add_audio(response, payload)
        self._send_json(200, response)

    def log_message(self, fmt, *args):
        sys.stderr.write("[bridge] " + (fmt % args) + "\n")


def main():
    server = ThreadingHTTPServer((GATEWAY_HOST, GATEWAY_PORT), Handler)
    print(
        f"Theocraft-Ollama bridge listening on http://{GATEWAY_HOST}:{GATEWAY_PORT}/\n"
        f"  -> forwarding to Ollama at {OLLAMA_URL} (default model {OLLAMA_MODEL}, "
        f"keep_alive {OLLAMA_KEEP_ALIVE})",
        flush=True,
    )
    if GATEWAY_TOKEN:
        print("  -> requiring Authorization: Bearer <token>", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping bridge.", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
