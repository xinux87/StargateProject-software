# Stargate Controller — Mobile App

Flutter application for Android and iOS that controls the Stargate replica over **Bluetooth Low Energy (BLE)**. No WiFi or internet required on the mobile device — the app connects directly to the Raspberry Pi's BLE radio.

## Features

- **BLE scan & connect** — discovers Stargate devices advertising the custom GATT service
- **PIN authentication** — per-connection PIN challenge (default: `1969`)
- **Stargate control** — full DHD symbol dialing, wormhole open/close, simulate incoming
- **Lamp mode** — RGB color picker, brightness slider, animation selector (Static / Wormhole / Black Hole / Kawoosh)
- **WiFi management** — scan networks, connect/disconnect, view status, forget saved networks, rename Pi hostname
- **Hardware tests** — cycle individual chevrons, all LEDs on/off, ring forward/backward, test audio
- **Live status** — pushed every 2 seconds over BLE NOTIFY; shows wormhole state, dialing progress, locked chevrons
- **Stargate glyph icons** — all 39 Milky Way constellation symbols displayed as SVG icons

---

## App Architecture

```
mobile_app/
├── lib/
│   ├── main.dart                   # Entry point, ProviderScope
│   ├── app.dart                    # MaterialApp.router + ThemeData
│   ├── services/
│   │   ├── ble_service.dart        # Raw BLE layer: connect, chunked notify, completers
│   │   └── stargate_service.dart   # High-level typed API over BLE
│   ├── providers/
│   │   └── connection_provider.dart # Riverpod providers: BleService, StargateService, auth, state
│   └── screens/
│       ├── scan_screen.dart        # BLE device scanner
│       ├── auth_screen.dart        # PIN entry
│       ├── home_screen.dart        # Navigation hub
│       ├── control_screen.dart     # DHD symbol grid + wormhole controls
│       ├── lights_screen.dart      # Lamp mode: color, brightness, animation
│       ├── wifi_screen.dart        # WiFi management
│       └── test_screen.dart        # Hardware test panel
├── assets/
│   └── symbols/                    # 001.svg … 039.svg — Milky Way glyphs
├── android/
│   └── app/
│       ├── build.gradle.kts        # NDK 27.0.12077973, API targets
│       └── src/main/AndroidManifest.xml  # BLE permissions
└── pubspec.yaml
```

### Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_blue_plus` | BLE scan, connect, GATT read/write/notify |
| `flutter_riverpod` | Reactive state management |
| `go_router` | Declarative navigation |
| `flex_color_picker` | HSV color wheel for lamp mode |
| `flutter_svg` | Render SVG constellation icons |
| `permission_handler` | Runtime BT/location permission requests |
| `shared_preferences` | Persist saved PIN across app restarts |

---

## BLE Protocol

### GATT Service

| UUID | Name | Properties | Direction |
|---|---|---|---|
| `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | Service | — | — |
| `a1b2c3d4-e5f6-7890-abcd-ef1234567891` | CMD | Write / WriteNoResponse | Client → Gate |
| `a1b2c3d4-e5f6-7890-abcd-ef1234567892` | RESPONSE | Notify | Gate → Client |
| `a1b2c3d4-e5f6-7890-abcd-ef1234567893` | STATUS | Notify + Read | Gate → Client |

### Message Format

All messages are JSON, written/notified as UTF-8 bytes.

**Command (client → gate):**
```json
{ "cmd": "lamp_on", "params": {"color": [0, 180, 216], "brightness": 200, "animation": "wormhole"}, "id": "uuid-v4" }
```

**Response (gate → client):**
```json
{ "status": "ok", "data": { ... }, "id": "uuid-v4" }
```

**Status push (gate → client, every 2 s):**
```json
{
  "wormhole_active": false,
  "lamp_mode": true,
  "lamp_color": [0, 180, 216],
  "lamp_brightness": 200,
  "lamp_animation": "wormhole",
  "dialing": false,
  "locked_chevrons": 0
}
```

### Chunking Protocol

BLE MTU is often only 23 bytes (20 payload). All outgoing notifications from the gate are split into 180-byte chunks:

- Byte 0 = `0..254` → chunk index (more chunks follow)
- Byte 0 = `255` → final (or only) chunk

The Flutter `BleService` reassembles chunks in a `Map<String,List<int>>` buffer per characteristic, dispatching the complete JSON only when the final chunk arrives.

### Authentication

Every new BLE connection starts unauthenticated. The `auth` command must succeed before any other command is accepted:

```json
{ "cmd": "auth", "params": {"pin": "1969"}, "id": "..." }
```

Success response: `{"status": "ok", "data": {"authenticated": true}, "id": "..."}`

The app saves the PIN in `SharedPreferences` and retries silently on reconnect.

### Command Reference

| Command | Params | Description |
|---|---|---|
| `auth` | `{pin}` | Authenticate this connection |
| `get_status` | — | Current gate state |
| `get_system_info` | — | IP, gate name, Python version |
| `dial_planet` | `{address: [s1…s6]}` | **Dial a planet in one command** — the gate queues all 7 symbols (6 address + point-of-origin) and presses centre. Preferred over `dhd_press` for address-book dialing. |
| `dhd_press` | `{symbol: 1–39}` | Press a single symbol on the DHD (manual/interactive use) |
| `dhd_press` | `{symbol: 0}` | Press centre button (dial / close wormhole) |
| `dhd_press` | `{symbol: -1}` | Abort dialing sequence |
| `clear_buffer` | — | Clear address buffer / cancel dialing |
| `simulate_incoming` | — | Simulate an incoming wormhole |
| `wormhole_on` | — | Open wormhole immediately |
| `wormhole_off` | — | Close active wormhole |
| `lamp_on` | `{color?, brightness?, animation?}` | Enable lamp mode |
| `lamp_off` | — | Disable lamp mode |
| `lamp_set` | `{color?, brightness?, animation?}` | Update lamp while active |
| `lamp_status` | — | Current lamp state |
| `lamp_animations` | — | List available animations |
| `wifi_scan` | — | Scan for nearby WiFi networks |
| `wifi_connect` | `{ssid, password?}` | Connect to a network |
| `wifi_disconnect` | — | Disconnect current network |
| `wifi_status` | — | Current connection: ssid, ip, signal |
| `wifi_saved` | — | List of saved networks |
| `wifi_forget` | `{ssid}` | Forget a saved network |
| `set_hostname` | `{hostname}` | Change Pi hostname |
| `get_hostname` | — | Current Pi hostname |
| `chevron_cycle` | `{chevron: 1–7}` | Cycle one chevron (lock → unlock) |
| `all_leds_on` | — | Turn all chevron LEDs on |
| `all_leds_off` | — | Turn all LEDs off |
| `symbol_forward` | — | Move ring forward one symbol |
| `symbol_backward` | — | Move ring backward one symbol |
| `ring_set_zero` | — | Set ring current position as zero |
| `test_audio` | — | Play wormhole_open sound clip |
| `reboot` | — | Reboot the Raspberry Pi |
| `restart_service` | — | Restart stargate.service |

---

## Raspberry Pi Setup

These steps are required once on the Pi before the app can connect.

### 1. Install Python dependencies

```bash
sudo /home/sg1/venv_v4/bin/pip install bless bleak
```

> `bless>=0.2.0` is the GATT server library. `bleak` is only needed for the optional `test/bluetooth_test.py` client test.

### 2. Enable BlueZ experimental mode

The `bless` library requires BlueZ experimental features to register GATT services.

```bash
sudo mkdir -p /etc/systemd/system/bluetooth.service.d
sudo tee /etc/systemd/system/bluetooth.service.d/experimental.conf > /dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental
EOF

sudo systemctl daemon-reload
sudo systemctl restart bluetooth
```

### 3. Enable Bluetooth auto-power on reboot

Edit `/etc/bluetooth/main.conf` and set:
```ini
[Policy]
AutoEnable=true
```

### 4. Unblock Bluetooth radio (Pi Zero 2W)

On Pi Zero 2W, the BT adapter is rfkill-blocked by default:

```bash
sudo rfkill unblock bluetooth
sudo bluetoothctl power on
```

To persist across reboots, add to `/etc/rc.local` before `exit 0`:
```bash
rfkill unblock bluetooth
```

### 5. Configure the gate (optional)

In `config/milkyway-config.json`:
```json
{
  "bluetooth_enabled": true,
  "bluetooth_device_name": "Stargate",
  "bluetooth_pin": "1969"
}
```

If these keys are absent the server defaults to `bluetooth_enabled=true`, name `"Stargate"`, PIN `"1969"`.

### 6. Restart the Stargate service

```bash
sudo systemctl restart stargate.service
```

Verify BLE is advertising:
```bash
journalctl -u stargate.service -f
# Should show: BluetoothServer: advertising as 'Stargate' on service a1b2c3d4-...
```

---

## Building the APK (Android)

Build entirely in WSL (Ubuntu) — no Android Studio needed.

### Prerequisites

```bash
# Java 17
sudo apt-get install -y openjdk-17-jdk-headless

# Android SDK command-line tools
mkdir -p ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
unzip /tmp/cmdline-tools.zip -d /tmp/cmdtools
mv /tmp/cmdtools/cmdline-tools ~/android-sdk/cmdline-tools/latest

export ANDROID_SDK_ROOT=~/android-sdk
export PATH=$PATH:~/android-sdk/cmdline-tools/latest/bin:~/android-sdk/platform-tools

# Accept licenses and install platform tools
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# Flutter SDK
git clone https://github.com/flutter/flutter.git ~/flutter --depth 1 -b stable
export PATH=$PATH:~/flutter/bin
flutter precache --android
```

### Build

```bash
cd /path/to/sg1_v4/mobile_app
export ANDROID_SDK_ROOT=~/android-sdk
export PATH=$PATH:~/flutter/bin:~/android-sdk/cmdline-tools/latest/bin:~/android-sdk/platform-tools

flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (~23 MB)

### Install via ADB

```bash
~/android-sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or copy to Windows and install manually:
```bash
cp build/app/outputs/flutter-apk/app-release.apk /mnt/c/Users/$USER/Desktop/stargate.apk
```

---

## Building for iOS

iOS requires macOS + Xcode. From the `mobile_app/` directory:

```bash
flutter pub get
open ios/Runner.xcworkspace   # Opens Xcode
```

In Xcode:
1. Set your Team under **Signing & Capabilities**.
2. Connect your iPhone and select it as target.
3. **Product → Run** (for development) or **Product → Archive** (for distribution).

> Core Bluetooth on iOS requires the `NSBluetoothAlwaysUsageDescription` key in `Info.plist`. This is already included via `permission_handler`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| App doesn't find Stargate | BT blocked / service not started | `rfkill unblock bluetooth && sudo systemctl restart stargate.service` |
| "Failed to register advertisement" | BlueZ missing `--experimental` | See step 2 above |
| PIN rejected | Wrong PIN in config or app | Check `bluetooth_pin` in config; clear app storage and re-enter |
| WiFi shows "not connected" even when connected | Old firmware (pre-fix) | Update Pi files and restart service |
| Audio test fails | Missing sound file or wrong clip name | Verify `soundfx/wormhole_open.wav` exists on Pi |
| App crashes after BLE connect on Android 12+ | Missing BT permissions in manifest | Already fixed; rebuild APK |
| Large responses truncated | MTU negotiation | The chunking protocol handles this; ensure `flutter_blue_plus >=1.32` |
