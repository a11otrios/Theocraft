# Theocraft

Theocraft is an Android voxel survival game in which persistent villagers can converse through a configurable remote LLM and carry out constrained in-world instructions.

For a consolidated description of the currently implemented game, villager capabilities, AI and voice pipeline, build process, and known boundaries, see [What Theocraft is doing](docs/current-state.md).

Production is based on the native [Luanti](https://github.com/luanti-org/luanti) engine and the [VoxeLibre](https://github.com/VoxeLibre/VoxeLibre) game. The earlier Flutter renderer is preserved on the `prototype/flutter` branch but is not part of the production architecture.

## Current milestone

- Native voxel engine and mature survival gameplay pinned as Git submodules.
- Persistent villager names, short bios, and per-player conversation histories that survive world restarts.
- Mobile conversation formspec with local history and trade hand-off.
- Configurable HTTPS LLM-gateway contract with a deterministic offline fallback.
- Server-validated `follow`, `stay`, `come`, `gather`, and `build` actions.
- Generated Android staging that bundles and brands the game without changing upstream checkouts.
- Desktop conversion of legacy and modern Minecraft Java Anvil worlds, including
  Minecraft 1.18+ negative build heights and explicit unknown-block reporting.

The importer currently converts Overworld terrain and spawn data. See
`tools/world_import/README.md` for usage and the deliberately narrower treatment
of dimensions, entities, block entities, and player data.

## Bootstrap and build on Windows

```powershell
git submodule update --init --depth 1
.\scripts\Assemble-Game.ps1
.\scripts\Prepare-Android.ps1
.\scripts\Build-Android.ps1 -Configuration Debug
.\scripts\Verify-AndroidApk.ps1
```

To install the debug build on a connected Android phone, enable Developer
options and USB debugging, unlock the phone, approve its USB debugging prompt,
and run:

```powershell
.\scripts\Install-Android.ps1
```

The installer detects the phone's CPU architecture, verifies the matching APK,
and updates an existing Theocraft installation without removing its local data.

For a fast desktop integration test, extract the official Luanti 5.16.1 Windows
archive under `.tools\luanti-5.16.1-win64` (or pass its executable explicitly),
then run:

```powershell
.\scripts\Run-Desktop.ps1
```

The script uses an isolated profile under `.tools\desktop-test`; it does not
touch an existing Luanti installation or its worlds. In the test world, use
`/summon mobs_mc:villager` (VoxeLibre renames the engine's `/spawnentity` to
`/summon`) and right-click the villager to open Theocraft's conversation UI.

Convert an existing Minecraft Java Edition world on the desktop and optionally
package it for transfer to Android:

```powershell
.\scripts\Import-MinecraftWorld.ps1 `
  -Source "C:\Minecraft\saves\My World" `
  -Destination "C:\Converted\My World" `
  -Zip
```

Android SDK/NDK requirements are inherited from the pinned Luanti release. The first Gradle build downloads Luanti's Android native dependencies.

Configure the optional remote model under the game's advanced settings. Use a gateway endpoint and a gateway-issued access token; do not put an OpenAI or other provider secret directly into a distributed APK. See `docs/llm-gateway.md` for the provider-neutral contract.

## Licensing

The assembled game is a derivative distribution of GPL-3.0 VoxeLibre. Luanti is LGPL-2.1-or-later, and individual media retain their upstream licenses and attribution requirements. Release packaging must ship the corresponding licenses, source offer/source code, and VoxeLibre media attribution described by the pinned upstream `LEGAL.md`.
