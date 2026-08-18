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

import json
import os
import sys
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
        "You are a real person with your own life, moods, and opinions — NOT a helper, "
        "assistant, or quest-giver, and NOT an AI. Never list your abilities or offer your "
        "services unless it comes up naturally. Just chat the way a villager would: talk about "
        "your day, your trade, the village and its people, rumours, the weather, or turn it "
        "around and ask the player about themselves. Have preferences, feelings and opinions. "
        "Keep replies short (1-2 sentences), casual, and in character.",
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


KNOWN_ACTION_TYPES = ["none", "follow", "stay", "come", "gather", "build"]


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

        self._send_json(200, to_theocraft_response(content))

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
