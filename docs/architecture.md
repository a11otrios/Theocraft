# Architecture

Theocraft is a branded Android distribution of the native Luanti voxel engine with VoxeLibre as its survival game. Flutter is retained only in the `prototype/flutter` Git branch; the production renderer, chunk meshing, physics, touch input, and world database are native Luanti code.

The repository pins both upstreams as Git submodules and applies Theocraft through copied build staging:

- `vendor/luanti`: native Android-capable engine.
- `vendor/voxelibre`: survival gameplay and Minecraft-like content.
- `vendor/mcimport`: pinned provenance and serializer reference for the world importer.
- `mods/theocraft_villagers`: identity, conversation UI, gateway client, response policy, and safe actions.
- `mods/theocraft_import`: visible placeholder node for block states the importer cannot map.
- `patches`: narrowly scoped Android branding and bundled-game changes applied to generated source.
- `scripts`: reproducible game assembly and Android builds without editing either upstream checkout.

Minecraft Java world conversion is a separate desktop pipeline. It reads legacy
and palette-based Anvil region files, maps Overworld block states into VoxeLibre
nodes, and emits a Luanti world database. Unsupported blocks are counted in an
import report and replaced by an explicit placeholder rather than silently
discarded. Dimensions other than the Overworld, entities, block entities, and
player files remain outside the current conversion boundary.

Conversation history is keyed by the persistent villager UUID and player name, bounded to the most recent 20 messages, and stored in the world's mod storage. This keeps each villager's memory separate and restores it after entity unloads or app restarts.
