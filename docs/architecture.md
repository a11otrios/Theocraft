# Architecture

Theocraft is a branded Android distribution of the native Luanti voxel engine with VoxeLibre as its survival game. Flutter is retained only in the `prototype/flutter` Git branch; the production renderer, chunk meshing, physics, touch input, and world database are native Luanti code.

The repository pins both upstreams as Git submodules and applies Theocraft through copied build staging:

- `vendor/luanti`: native Android-capable engine.
- `vendor/voxelibre`: survival gameplay and Minecraft-like content.
- `mods/theocraft_villagers`: identity, conversation UI, gateway client, response policy, and safe actions.
- `patches`: narrowly scoped Android branding and bundled-game changes applied to generated source.
- `scripts`: reproducible game assembly and Android builds without editing either upstream checkout.

Minecraft Java world conversion is a separate import pipeline. It will read Anvil region files, map block states and entities into VoxeLibre nodes, and emit a Luanti world database. Unsupported blocks will be reported and replaced by an explicit placeholder rather than silently discarded.

Conversation history is keyed by the persistent villager UUID and player name, bounded to the most recent 20 messages, and stored in the world's mod storage. This keeps each villager's memory separate and restores it after entity unloads or app restarts.
