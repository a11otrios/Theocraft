# Using ADB from this test PC

Practical notes for driving Android phones with `adb` on this machine
(Windows 11, PowerShell). Focused on how Theocraft gets built and pushed to a
phone over Wi-Fi.

## The adb you should use

Always use the copy that ships with the repo's Android SDK:

```
E:\Code\Theocraft\.tools\android\sdk\platform-tools\adb.exe
```

It is **version 41**. Handy PowerShell shortcut for a session:

```powershell
$adb = "E:\Code\Theocraft\.tools\android\sdk\platform-tools\adb.exe"
& $adb version
```

> **Gotcha — version clashes.** If another `adb` (e.g. one from Android Studio,
> version 32) is running as the background *adb server*, you'll see:
> `adb server version (xx) doesn't match this client (41); killing...`
> The server restarts and **wireless connections drop**, so you have to
> `adb connect` again. Avoid mixing adb versions: prefer the repo one every time,
> or run `& $adb kill-server` once at the start so the v41 server owns the port.

## Phone setup (once per phone)

1. Enable **Developer mode**: Settings → About phone → tap **Build number** 7×.
2. Settings → System → **Developer options** → turn on **Wireless debugging**
   (and **USB debugging** if you use a cable).

## Pair over Wi-Fi (once per phone, Android 11+)

On the phone: Developer options → Wireless debugging → **Pair device with pairing
code**. That popup shows a **pairing address** `IP:PORT` and a **6-digit code**.
The pairing port/code change every time you open the popup — use them fast.

```powershell
$adb = "E:\Code\Theocraft\.tools\android\sdk\platform-tools\adb.exe"
& $adb pair 192.168.1.149:36267 123358    # <pair IP:PORT> <code>
```

Expect: `Successfully paired to ...`. Pairing is remembered, so you normally only
do it once per phone.

## Connect (each session / after a server restart)

The **main** Wireless debugging screen shows a *different* `IP:PORT` — the
**connect address**. Many recent phones (and mDNS) connect automatically after
pairing, so check `devices` first.

```powershell
& $adb connect 192.168.1.149:41567       # <connect IP:PORT> (only if not already listed)
& $adb devices
```

Wireless devices show up with an mDNS-style serial, e.g.
`adb-ZA223K9BHW-7hyIhW._adb-tls-connect._tcp` — the `ZA223K9BHW` part is the
phone's real serial.

## Devices seen on this PC

| adb serial contains | phone |
|---------------------|-------|
| `ZA223K9BHW`        | Motorola Edge 70 Fusion (the new phone) |
| `RZCX60876NK`       | second phone (other test device)        |

When **more than one** device is connected, every command must target one with
`-s <serial>`, or the wrapper scripts will refuse with "more than one device".

```powershell
& $adb -s "adb-ZA223K9BHW-7hyIhW._adb-tls-connect._tcp" shell getprop ro.product.model
```

## Everyday commands

```powershell
& $adb devices                                   # list connected devices + state
& $adb -s <serial> install -r <path-to.apk>      # install / upgrade an APK
& $adb -s <serial> uninstall dev.theocraft.android    # remove the app
& $adb -s <serial> shell getprop ro.product.cpu.abi   # phone architecture (arm64-v8a here)
& $adb -s <serial> logcat                        # live device logs (Ctrl+C to stop)
& $adb -s <serial> logcat *:E                    # errors only
& $adb disconnect                                # drop all wireless connections
& $adb kill-server                               # stop the local adb server
```

A device state of `unauthorized` means the phone has a **"Allow debugging?"**
prompt waiting — unlock it and tap Allow (tick "always allow").

## The repo scripts (preferred way to deploy)

These wrap adb so you don't juggle paths/serials:

- **`scripts\Install-Android-Wireless.ps1`** — pair + connect + install in one go:
  ```powershell
  .\scripts\Install-Android-Wireless.ps1 -Pair 192.168.1.149:36267 -Code 123358 -Connect 192.168.1.149:41567
  ```
- **`scripts\Install-Android.ps1`** — install the already-built debug APK onto a
  connected phone (pass `-Serial` when more than one is connected):
  ```powershell
  .\scripts\Install-Android.ps1 -Serial "adb-ZA223K9BHW-7hyIhW._adb-tls-connect._tcp"
  ```
  It verifies the APK, reads the phone's ABI, and installs
  `.build\android-source\android\app\build\outputs\apk\debug\app-<abi>-debug.apk`.
- **`scripts\Build-Android.ps1`** — build the debug APK (Gradle `assembleDebug`).
  Run this first when the mods/code changed. If the app doesn't pick up mod
  changes, refresh the staged mod before building:
  ```powershell
  robocopy .\mods\theocraft_villagers .\.build\android-source\games\theocraft\mods\theocraft_villagers /MIR
  ```

Typical rebuild-and-deploy loop after changing mod code:

```powershell
.\scripts\Build-Android.ps1
.\scripts\Install-Android.ps1 -Serial "adb-ZA223K9BHW-7hyIhW._adb-tls-connect._tcp"
```

## Villager AI on the phone

The landmark commands and villager movement work offline. The AI chat/voice
needs the local gateway reachable from the phone (same Wi-Fi):

- Start it on the PC: `.\scripts\Run-LlmGateway.ps1` (GPU works since the driver
  was updated to 582.66; add `-Voice chatterbox` for neural voices).
- In the game's settings, set `theocraft_llm_endpoint` to
  `http://<this-PC-LAN-IP>:8713/` (and enable `theocraft_llm_enabled`);
  allow that port through the Windows firewall. `Run-LlmGateway.ps1` prints the
  exact phone endpoint to use.
