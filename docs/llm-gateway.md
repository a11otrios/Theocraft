# LLM gateway contract

Theocraft sends villager dialogue to a user-configurable HTTPS gateway. The Android app must never ship a model-provider API key. The gateway owns provider credentials, authentication, quotas, moderation, and any provider-specific response parsing.

## Request

`POST` the configured endpoint with `Content-Type: application/json` and this versioned shape:

```json
{
  "version": 1,
  "villager": {
    "id": "persistent-villager-id",
    "name": "Ada",
    "bio": "A practical farmer who knows the paths and people around this village.",
    "profession": "farmer",
    "position": {"x": 10, "y": 64, "z": -4}
  },
  "player": {"name": "player", "position": {"x": 12, "y": 64, "z": -4}},
  "message": "Please follow me",
  "history": [{"role": "player", "content": "Hello"}],
  "allowed_actions": [{"type": "none"}, {"type": "follow"}],
  "model": "gateway-defined-model-id",
  "system_prompt": "Be concise, friendly, and stay in character."
}
```

An optional gateway access token is sent as `Authorization: Bearer <token>`.

## Response

Return a JSON object:

```json
{
  "speech": "Of course. Lead the way.",
  "action": {"type": "follow"}
}
```

The gateway may only select actions advertised in `allowed_actions`. The game still validates every response, clamps counts, limits action range, checks protected areas, and rejects arbitrary node or command execution. Invalid, unavailable, or slow gateways automatically fall back to the offline instruction interpreter.

Supported actions in the first milestone are `none`, `follow`, `stay`, `come`, `gather`, and `build`. Gather resources and build blueprints are constrained to the values included in each request.
