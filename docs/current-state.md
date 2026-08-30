# What Theocraft is doing

Theocraft is turning VoxeLibre into an Android voxel-survival game where villagers are persistent characters rather than disposable NPCs. Players can talk to villagers in ordinary language, hear their replies, and ask them to perform a deliberately limited set of useful actions in the world.

The production game uses the native [Luanti](https://www.luanti.org/) engine and [VoxeLibre](https://www.voxelibre.net/) gameplay. Theocraft is applied as a small set of mods, engine patches, and repeatable build scripts instead of maintaining large forks of either upstream project. The earlier Flutter renderer remains only on the `prototype/flutter` branch.

## The player experience

Right-clicking a villager opens a compact mobile conversation panel. It shows the newest messages first, allows the player to send a message, and retains access to normal VoxeLibre trading. A player with the server privilege can also set limits for an individual villager.

Each villager receives a stable UUID, name, short biography, profession, and birthday. The identity is persisted with the entity, and conversations are stored separately for each villager/player pair in world mod storage. Villagers therefore remember previous conversations across entity unloads and world restarts.

Villager replies are spoken in the world. If the gateway supplies an Ogg text-to-speech clip, it is played from the villager's position; otherwise the game uses a short villager murmur. A reply can still be heard if the conversation window was closed while the model was thinking.

## Conversation and AI

The game supports two conversation paths:

1. A configurable HTTP gateway sends the villager identity, player message, recent history, allowed actions, model name, and system prompt to an LLM.
2. A deterministic offline interpreter handles common instructions whenever the gateway is disabled, unavailable, too slow, or returns an invalid response.

The repository includes a local gateway that translates Theocraft's provider-neutral protocol to Ollama. Its default model is `qwen2.5:3b`, it can run completely on the player's PC, and an Android device can reach it over the local network. The bridge uses an append-only prompt layout to help Ollama reuse its KV cache and can be installed to start automatically at Windows login.

Villagers receive stable, varied personality guidance from the gateway. They also know the basic rules of hide and seek, so a player can ask them to hide or seek without restating the rules every time.

Remote HTTPS is the production-safe default. Plain HTTP must be explicitly enabled for a trusted development LAN, and a shared bearer token can protect the local endpoint. Provider secrets remain in the gateway and are never bundled into the APK.

## What villagers can do

The server validates every model-selected action against an allowlist before applying it. The currently implemented actions are:

- `follow`: keep following the requesting player.
- `stay`: stop and wait.
- `come`: walk to the player and stop nearby.
- `gather`: collect a bounded amount of wood, stone, dirt, or sand into the villager's own inventory.
- `build`: construct a small wall or shelter using allowed materials taken from the player's inventory.
- `buildhome`: walk home and build a small house there.
- `goto`: travel to a named landmark and wait.
- `guard`: remain on watch at the current position or a landmark.
- `patrol`: loop between two or more named landmarks.
- `deliver`: carry gathered items to the player or a landmark.
- `teleport`: move immediately to the player or a known landmark and then stay there.

Villagers use Luanti pathfinding for directed movement, retry when temporarily stuck, and may make occasional idle journeys back toward their assigned home. Players can take gathered items through the conversation panel.

The advanced game settings include an optional **Invincible villagers** toggle. It is off by default; when enabled, villagers ignore player and mob attacks, projectiles, explosions, falls, fire, lava, and other environmental damage.

The bundled Halloween feature pack is enabled by default. Villagers offer a **Treat** action (or respond to “trick or treat”), candy and caramel apples are edible and craftable, decorative treat bowls provide a daily treat, and extra bats may appear nearby at night. `/halloween on|off|status|kit` controls the event and can provide a starter decoration kit containing jack-o'-lanterns and cobwebs.

Arbitrary commands and arbitrary node placement are not accepted. Unknown actions become `none`; text lengths and gather quantities are clamped; interaction distance, build bounds, inventory availability, and protected areas are checked in the game. These rules apply even when an LLM generated the response.

## Places, homes, and recovering villagers

Worlds maintain a persistent registry of named landmarks. A default village landmark is seeded automatically and initially follows the centre of the known villager population until a player pins it. Players can create, list, move, and remove landmarks and receive a visible beacon pointing toward a selected location.

Villager locations are periodically recorded. The following commands support world and character management:

| Command | Purpose |
| --- | --- |
| `/tcmark <name>` | Save the player's current location as a landmark. |
| `/tcmarks [name]` | List landmarks or show a beacon for one. |
| `/tcunmark <name>` | Remove a landmark. |
| `/tcsethome <villager> <landmark>` | Assign a villager's home. Coordinates are also accepted. |
| `/tcfind <name> [DDMMYY]` | Locate a known villager; birthday disambiguates duplicate names. |
| `/tcteleport <villager> here\|<landmark>\|x y z` | Teleport a loaded villager. |
| `/tcrevive <name> [DDMMYY]` | Respawn a lost villager and reconnect its saved identity and memory when possible. |
| `/tcexport [label]` | Export the villager roster and conversation memories to JSON. |
| `/tcimport [label]` | Merge an exported roster and memories into another world. |

The export contains a villager's recorded identity, birthday, last position, and conversation records. It does not move the original map entity itself; after importing, `/tcrevive` creates the body and reconnects the saved data.

## Villager voices

The local gateway has optional text-to-speech support:

- Windows SAPI provides a zero-setup fallback.
- Piper provides local neural voices with stable per-villager gender/accent selection.
- Chatterbox provides higher-quality neural speech and optional voice cloning from reference clips.

Voice choice is stable for a villager's ID. Chatterbox runs in an isolated Python environment because its dependencies conflict with the repository's development tools. A birthday cutoff can keep existing villagers on a legacy Piper or SAPI voice while assigning Chatterbox only to newer villagers.

## Android and desktop workflow

The repository pins Luanti, VoxeLibre, and the original `mcimport` reference as Git submodules. Build scripts then:

1. Assemble a generated VoxeLibre game with the Theocraft mods.
2. Copy Luanti into generated Android staging.
3. Apply narrowly scoped branding, bundled-game, and HTTP-permission patches.
4. Build architecture-specific Android APKs with an automatically incremented build number.
5. Verify that the APK contains the expected game and mod files before installation.

The generated trees live under `.build`; upstream checkouts are not edited. Installation scripts support USB and wireless ADB while preserving an existing installation's worlds. A separate desktop launcher creates an isolated Luanti profile for quicker integration testing.

## Minecraft Java world import

The desktop importer converts Minecraft Java Anvil worlds into Luanti worlds compatible with Theocraft. It supports legacy numeric sections and modern palette/block-state sections, including the negative build heights introduced in Minecraft 1.18.

The importer currently converts Overworld blocks and the original spawn location. Unknown block states are counted in `import-report.json` and represented by the visible `theocraft_import:unknown` node rather than silently becoming air. An optional JSON map can add or override block conversions, and the result can be packaged as a ZIP for transfer to Android.

Nether and End dimensions, entities, block entities and their inventories, signs, and player files are not currently converted.

## Main implementation areas

| Area | Location |
| --- | --- |
| Villager identity, UI, memory, policy, actions, speech, landmarks, recovery, and transfer | `mods/theocraft_villagers` |
| Placeholder for unsupported imported blocks | `mods/theocraft_import` |
| Local Ollama and text-to-speech gateway | `tools/llm_gateway` |
| Minecraft Java world converter | `tools/world_import` |
| Reproducible assembly, build, install, gateway, and voice helpers | `scripts` |
| Luanti branding and bundled-game changes | `patches` |
| Policy, source, and importer verification | `tests` |

## Current boundaries

Theocraft is currently a locally built Android distribution rather than a finished store release. Villager capabilities are intentionally constrained and based on small built-in action implementations, not general autonomous access to the game engine. The local Ollama/TTS service runs on a separate PC, so a phone needs network access to that machine for AI conversation and generated voices; deterministic offline instructions and villager murmurs remain available without it.

For setup and detailed interfaces, see the [project README](../README.md), [architecture](architecture.md), [LLM gateway contract](llm-gateway.md), [local gateway guide](../tools/llm_gateway/README.md), and [world importer guide](../tools/world_import/README.md).
