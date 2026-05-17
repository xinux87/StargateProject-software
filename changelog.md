## New in version 4.1.0 (sg1_without_internet branch)

### Bluetooth BLE Mobile App

Full Android and iOS mobile application built with Flutter for wireless control of the Stargate over Bluetooth Low Energy. No WiFi, no internet, no pairing hassle — the phone connects directly to the Pi's BT radio.

**Pi-side changes:**

- `classes/bluetooth_server.py` — New `StargateBluetoothServer` class. Runs a GATT server in a background daemon thread using the `bless` library. Exposes three GATT characteristics on service UUID `a1b2c3d4-e5f6-7890-abcd-ef1234567890`:
  - CMD (write) — receives JSON commands from the app
  - RESPONSE (notify) — sends per-command replies
  - STATUS (notify + read) — pushes gate state every 2 seconds
  - Large payloads are chunked in 180-byte packets with a 1-byte sequence prefix.
- `classes/bluetooth_command_handler.py` — New `BluetoothCommandHandler` bridge. Maps 30+ BLE command strings to Stargate/WiFi manager calls. Mirrors `web_server.py` API patterns exactly.
- `classes/wifi_manager.py` — New `WiFiManager` class. Wraps `nmcli` for WiFi scan, connect, disconnect, status, saved networks, forget, hostname get/set.
- `main.py` — Initialises `WiFiManager`, `BluetoothCommandHandler`, and `StargateBluetoothServer` after the HTTP server. BT startup is non-fatal (logged as warning if adapter missing).
- `requirements.txt` — Added `bless>=0.2.0` and `bleak>=0.21.0`.

**Authentication:** Every new BLE connection is unauthenticated. The `auth` command with the configured PIN (default `1969`) must succeed before other commands are accepted. PIN is configurable via `bluetooth_pin` in `milkyway-config.json`.

**Flutter app (`mobile_app/`):**

- Screens: Scan, Auth, Home, Control (DHD), Lights (lamp mode), WiFi, Tests
- State: `flutter_riverpod` providers, `go_router` navigation
- BLE: `flutter_blue_plus`, custom chunking reassembly, 10-second command timeout using `Completer`
- DHD control: all 39 Milky Way symbols displayed as SVG glyphs (`flutter_svg`) sourced from `web/chevrons/milkyway/`
- Lamp mode: `flex_color_picker` HSV wheel with anti-jitter guard (skips STATUS sync for 5 s after user interaction)
- WiFi: scan, connect, disconnect, status, saved networks, forget, rename hostname
- Tests: cycle chevrons (7), ring forward/backward/zero, all LEDs, audio test

**Pi Zero 2W BLE requirements:**

- BlueZ `--experimental` flag required for GATT service registration
- `rfkill unblock bluetooth` required at boot (adapter is blocked by default on Pi Zero 2W)
- `AutoEnable=true` in `/etc/bluetooth/main.conf` keeps the adapter powered after reboot

### Audio system fix

- `bluetooth_command_handler.py` `_test_audio` now plays `wormhole_open` (previously referenced non-existent `dhd_center` clip).

### Offline-only branch hardening

- Audio playback replaced `simpleaudio` (segfaults on Python 3.13/aarch64) with `audio_player.py` wrapping `aplay` subprocess.
- All internet-dependent modules removed: `SoftwareUpdateV2`, `SubspaceClient`, `SubspaceServer`, WireGuard utilities, Rollbar.
- Adafruit library pins removed to allow pip to resolve compatible versions under Python 3.13.
- `lgpio` added as dependency so `gpiozero` uses it instead of `RPi.GPIO` on newer kernels.
- `evdev` replaces `keyboard` library for DHD serial input (no root-only `/dev/input` limitations).

### Servo chevron variant

- New hardware mode: 9 chevrons driven by continuous-rotation servos via PCA9685 PWM board (I2C 0x40) + Adafruit Motor HAT (I2C 0x60) for ring stepper.
- Auto-detected by I2C signature at startup (`Electronics_Servo` driver).
- Chevron LEDs on GPIO 6, 12, 13, 16, 19, 20, 21 via `gpiozero` + `lgpio`.
- Full hardware BOM, wiring diagram, and setup guide: `Stargate Readme Hardware PCA9685PW +Adafruit Servo Hat.md`.

### Home Assistant lamp mode integration

- New HA entities: `light` (RGB + brightness), `select` (animation), updated coordinator polling.
- Available animations: Static Color, Wormhole Effect, Black Hole, Kawoosh Loop.
- Lamp mode and Stargate mode are mutually exclusive; gate activity auto-disables lamp.

---

## New in version 4.0.0
This version is a major upgrade from the v3.x branch. Completely refactored and with a lot of exciting new functionality and opportunities to extend the existing functionality!

- Vastly improved setup and installation process - quick and easy!
- Added web interface to dial, see what planet an incoming wormhole is from, run tests, and more
  - Dialing by pressing symbol buttons in a web browser
  - Dialing by clicking on an entry in the Address Book (both Movie Gates, and Fan Gates)
  - Shows what type of wormhole (incoming/outgoing), if any, and what planet is connected
  - Shows the approximate time-to-disengage (~38 minutes max)
  - Dialing a black hole is dangerous - you shouldn't do that. But if you did it's dangerous. You've been warned!!
  - Testing functions:
    - Cycle Chevrons individually
    - Move the symbol ring
    - Turn on ALL of the chevron LEDs
    - Turn off ALL of the LEDs on the Gate
    - Instantly open a wormhole
    - Close any open wormhole
    - Simulate an incoming wormhole (most requested feature)
    - Enter a DHD Test Mode, wherein pressing a button will toggle it's LED on/off
  - Administrative functions:
    - Volume up/down (+/-5%/click) Volume level is saved and persists between reboots
    - Restart the Stargate Software
    - Reboot the Raspberry Pi
    - Shutdown the Raspberry Pi (no more dirty shutdowns!)
  - In-App Subspace Network configuration: no more typing commands in SSH!
  - Shows helpful debug information, internet & subspace connection status, and software update information.
  - Responsive Web UI (Bootstrap+JQuery) UI works well on Mobile Devices, too.
  - Configuration of all aspects of the software is available in the web interface.
    - Type and value validation of all input data ensures system stability
  - A Symbol Overview page details all of the symbols on the gate/DHD, their keyboard mappings and symbol numbers, and provides links to Wikipedia pages for more information about each constellation
  - Helpful FAQs and links to resources for building and troubleshooting your gate
  - A System Information page provides information about the Raspi and Stargate Software running
  - Lifetime Statistics track the number of failed dialing attempts, count of inbound/outbound wormholes established to different types of gates, the amount of time connected.
- The software will run as normal even if hardware isn't connected or is not connected correctly. The gate will gracefully degrade to a "hardware simulation" state, where everything works as it should, just without actually controlling the hardware.
- Startup and shutdown are now graceful, and the software cleans up it's threads on exit.
- Completely restructured the code for readability, adherence to industry/language standards, and facilitating further extension of the software.
- Configurations have been moved out of static Python code into JSON configuration files to allow easy, dynamic reconfiguration all in one place
- Migrated to an HTTP-based API for retrieving Fan Gates and Software Updates - previously done via SQL server direct query.
- Fan Gates are automatically updated every 30 minutes. Previously required a reboot.
- Software Updates are checked every 6 hours. Previously required a reboot.
- Software now runs as a systemd daemon. Manage the daemon with these commands:
```
sudo systemctl start stargate.service
sudo systemctl stop stargate.service
sudo systemctl restart stargate.service
sudo systemctl status stargate.service
```
- Added `avahi` / `Bonjour` so the 'Gate can be accessed as `stargate.local` - you don't need to know it's IP address anymore!
- Adopted SemVer versioning
- Fully documented Web/HTTP API
- Code is linted with pylint
- Lots of behind the scenes stuff to make development, extension and debugging easier
- Installation script and pre-prepared disk image (for the Raspi 3B+) make installation a breeze
- Adds the Stargate Loopback Address (27, 7, 15, 1, 2), analogous with 127.0.0.1 to allow simulating incoming wormholes
- Security enhancements
- Better exception handling to prevent crashes
- Improved memory management
- Added firewall (UFW) to limit access. This is redundant and complementary to the firewalling that occurs on the Subspace Network.
- Improved logging - threads don't step on STDOUT anymore
- Added logrotate, so log files don't get huge and slow things down or fill up the drive. Retains 30 days of daily log file backups, FIFO.
- Automatic configuration of the audio devices to prevent snafus.
- Multi-universe support

## FEATURES on the backlog for possible future development
  - Scheduled Iris open/closed times
  - Scheduled mute times
  - Button in Web to open/close the Iris
  - Button in Web to connect/disconnect from subspace
  - Incoming wormhole alert in Web
  - Configure WiFi via Bluetooth (WebBluetooth in a browser), so you can skip the wpa_supplicant part of setup.
  - Implement homing
  - Support for the Milky Way Main Board
  - More Web stuff: fun interfaces, alternate "keyboard layouts," hidden movie references, etc.
  - Upload your own, additional sound clips
  - Play sound clips by clicking buttons in the Web UI
  - "Call Log" in Web: Shows last 25 incoming and outgoing wormholes, duration established, and what planet.
  - Show log files in Web (WebSocket streaming?)
  - Consider moving API away from polling to use WebSockets? Polling was just the quick/easy way out.
  - More granularity in hardware fall-back modes

## New in version 3.7:
- The Stargate server will now also start with eth0 interface only. (If subspace or wlan is missing)

## New in version 3.6:
- DHD detection update. Planet/stargate name is used in the log instead of the IP.

## New in version 3.5:
- Fix an issue with audio output. The program will now edit the alsa.conf file to set the USB audio adapter as output.
