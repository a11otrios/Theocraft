# Theocraft

Theocraft is an Android voxel survival game in which persistent villagers can converse through a configurable remote LLM and carry out constrained in-world instructions.

Production is based on the native [Luanti](https://github.com/luanti-org/luanti) engine and the [VoxeLibre](https://github.com/VoxeLibre/VoxeLibre) game. The earlier Flutter renderer is preserved on the `prototype/flutter` branch but is not part of the production architecture.

## Current milestone

- Native voxel engine and mature survival gameplay pinned as Git submodules.
- Persistent villager names, short bios, and per-player conversation histories that survive world restarts.
- Mobile conversation formspec with local history and trade hand-off.
- Configurable HTTPS LLM-gateway contract with a deterministic offline fallback.
- Server-validated `follow`, `stay`, `come`, `gather`, and `build` actions.
- Generated Android staging that bundles and brands the game without changing upstream checkouts.

Minecraft Java world import is the next implementation milestone; see `docs/architecture.md` for its boundary.

## Bootstrap and build on Windows

```powershell
git submodule update --init --depth 1
.\scripts\Assemble-Game.ps1
.\scripts\Prepare-Android.ps1
.\scripts\Build-Android.ps1 -Configuration Debug
```

Android SDK/NDK requirements are inherited from the pinned Luanti release. The first Gradle build downloads Luanti's Android native dependencies.

Configure the optional remote model under the game's advanced settings. Use a gateway endpoint and a gateway-issued access token; do not put an OpenAI or other provider secret directly into a distributed APK. See `docs/llm-gateway.md` for the provider-neutral contract.

## Licensing

The assembled game is a derivative distribution of GPL-3.0 VoxeLibre. Luanti is LGPL-2.1-or-later, and individual media retain their upstream licenses and attribution requirements. Release packaging must ship the corresponding licenses, source offer/source code, and VoxeLibre media attribution described by the pinned upstream `LEGAL.md`.
