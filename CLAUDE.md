# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kristian's Stargate Project (SG1 v4) — a Python control system for a 3D-printed, fully functional Stargate replica. Runs on a **Raspberry Pi Zero 2W** (target hardware for this branch) or Pi 3B+. Handles physical hardware (stepper motors, servos, LEDs, audio), a web-based control interface, and a REST API.

**This branch (`sg1_without_internet`) is an offline-only variant** designed for the Pi Zero 2W (512 MB RAM, no internet required):
- All internet/online dependencies removed (rollbar, gitpython, requests, WireGuard/Subspace)
- `SoftwareUpdateV2`, `SubspaceClient`, `SubspaceServer` are stubs or removed
- Audio playback uses `audio_player.py` (aplay subprocess) instead of `simpleaudio` (which segfaults on Python 3.13 / Debian 13 / aarch64)
- Adafruit libraries unpinned to allow pip to resolve compatible versions under Python 3.13
- `lgpio` added as dependency so gpiozero uses it instead of RPi.GPIO on newer kernels

**This branch also adds a new hardware variant:** the 9 chevrons can now be physically actuated with **continuous-rotation servo motors** instead of DC motors, controlled via a PCA9685 PWM board (I2C 0x40) alongside the existing Adafruit Motor HAT (I2C 0x60) for the ring stepper.

## Target Platform

| Item | Value |
|---|---|
| Hardware | Raspberry Pi Zero 2W |
| OS | Raspberry Pi OS / Debian 13 (trixie) |
| Python | 3.13 |
| RAM | 512 MB (416 MB usable) |
| Audio | USB audio adapter required (no onboard 3.5mm on Pi Zero 2W) |

## Deployment

### First-time install (from a fresh Pi OS image)

```bash
# 1. SSH into the Pi and install git
sudo apt-get install -y git

# 2. Clone the repo
git clone -b sg1_without_internet https://github.com/jonnerd154/StargateProject-software.git ~/sg1_v4

# 3. Copy soundfx directory (not in git, ~400 MB) from your machine:
#    rsync -av ./soundfx/ sg1@<pi-ip>:/home/sg1/sg1_v4/soundfx/

# 4. Run the installer
cd ~/sg1_v4/install && sudo bash install.sh
```

### Update an existing installation

```bash
# On the Pi:
git -C ~/sg1_v4 pull origin sg1_without_internet
sudo systemctl restart stargate.service

# Or from your dev machine via rsync:
rsync -av --exclude='.git' --exclude='soundfx' ./ sg1@<pi-ip>:/home/sg1/sg1_v4/
ssh sg1@<pi-ip> "sudo systemctl restart stargate.service"
```

## Running the Project

```bash
# Development/manual run (requires root for GPIO)
sudo /home/sg1/venv_v4/bin/python3 main.py

# Systemd service (production)
sudo systemctl start stargate.service
sudo systemctl status stargate.service
journalctl -u stargate.service -f

# Tail runtime logs
tail -f ~/sg1_v4/logs/milkyway.log
```

The web interface and API are served on port **8080** (`http://<pi-ip>:8080` or `http://stargate.local:8080`). Apache proxies requests from port 80.

## Running Tests

No automated test suite — tests are hardware-focused scripts:

```bash
sudo python3 test/servo_test.py    # Test continuous rotation servos
sudo python3 test/dhd_test.py      # Test DHD input device over USB serial
```

## Linting

```bash
pylint --rcfile=.pylintrc-milkyway ./*
```

## Architecture

### Startup Flow

`main.py` → `GateApplication.__init__()` initializes all subsystems in order, then `GateApplication.run()` calls `stargate.update()` in an infinite loop on the main thread.

### Core Class Hierarchy

```
GateApplication (main.py)
├── StargateConfig          — JSON config loader (config/*.json)
├── AncientsLogBook         — Thread-safe logging (2 MB rotation, 1 backup)
├── Electronics (factory)   — Detects hardware via I2C, returns driver:
│     ├── Electronics_Servo        (servo-based board) ← active on Pi Zero 2W
│     ├── ElectronicsOriginal      (Adafruit shield)
│     ├── ElectronicsMainBoard1V1  (custom mainboard)
│     └── ElectronicsNone          (simulation/no hardware)
├── StargateAudio           — Audio playback via aplay subprocess (audio_player.py)
├── NetworkTools            — Local IP/connectivity utilities (no internet checks)
├── StargateWebServer       — HTTP server (extends SimpleHTTPRequestHandler)
└── Stargate (main controller)
      ├── StargateSymbolManager   — 39-symbol constellation database
      ├── SymbolRing              — Stepper motor ring positioning
      ├── ChevronManager          — 9-chevron servo/LED control
      ├── StargateAddressManager  — Planet/address database (local only)
      ├── Dialer                  — Keyboard or DHD input
      ├── KeyboardManager         — Keyboard input (daemon threads)
      ├── WormholeManager         — Wormhole state machine & timing
      ├── WormholeAnimationManager — LED animation sequences
      └── DialingLog              — Call history
```

> **Removed in this branch:** `SoftwareUpdateV2`, `SubspaceClient`, `SubspaceServer`, `SubspaceMessages`, WireGuard utilities.

### Hardware Abstraction

`classes/StargateMilkyWay/electronics.py` is a factory that detects connected hardware via I2C device signatures and returns the appropriate driver.

| I2C signature detected | Mode | Driver |
|---|---|---|
| `0x60`, `0x61`, `0x62` | ORIGINAL | `ElectronicsOriginal` |
| `0x66`, `0x6f` | MAINBOARD_1V1 | `ElectronicsMainBoard1V1` |
| `0x40`, `0x60` | **SERVO** | **`Electronics_Servo`** |
| (none) | NONE | `ElectronicsNone` (simulation) |

### Servo Chevron Implementation

Relevant files: `electronics_servo.py`, `electronics_servo_helpers.py`, `chevrons.py`, `config/defaults-milkyway/board_servo.json.dist`.

**Hardware setup (`Electronics_Servo`):**
- **Board 1** — PCA9685 at `0x40`, managed via `ServoKit(channels=16)`. Chevrons 1–7 are mapped to `continuous_servo[0..6]`.
- **Board 2** — Adafruit Motor HAT at `0x60`, used only for the ring stepper motor.
- Chevron LEDs on GPIO pins 6, 12, 13, 16, 19, 20, 21 (via `gpiozero.LED`, uses `lgpio` backend).
- Channels 8 and 9 fall back to `DCMotorSim()` (not physically wired yet).

**Motor type dispatch (`Chevron`):**  
The `Chevron` class detects whether its motor is a servo by inspecting `str(type(self.motor))` for the substring `'servo'`.

**Throttle values (hardcoded in `Chevron.__init__`):**
- Down (unlock): `chevron_down_servo_throttle = -0.5`
- Up (lock): `chevron_up_servo_throttle = 0.7`

**On startup**, every servo chevron calls `move_up_servo()` to home itself. This plays an audio clip via `sound_start('chevron_2')`.

**Known gap:** `SERVOMotor` in `electronics_servo_helpers.py` is a stub (unused). `Electronics_Servo` uses `continuous_servo` objects from `ServoKit` directly.

### Audio System

Audio playback uses `classes/audio_player.py` — a drop-in replacement for `simpleaudio` that wraps `aplay` in a subprocess. This avoids a segfault in `simpleaudio 1.0.4` that occurs on Python 3.13 / Debian 13 / aarch64 when calling into ALSA.

```python
# audio_player.py provides the same API as simpleaudio:
wave_obj = sa.WaveObject.from_wave_file(path)
play_obj = wave_obj.play()
play_obj.is_playing()  # bool
play_obj.stop()
play_obj.wait_done()
```

`StargateAudio` detects the USB audio adapter at runtime via `aplay -l` and updates `/usr/share/alsa/alsa.conf` to point to the correct card. Wormhole WAV files are lazy-loaded on first play to reduce startup RAM usage.

### Configuration System

All config lives in `config/` as JSON files named `milkyway-*.json`. Default templates in `config/defaults-milkyway/*.json.dist` are auto-copied if the active config is missing.

```python
# Config access pattern throughout the codebase
value = self.cfg.get('key_name')  # returns config['key']['value']
```

Key config files:
- `milkyway-config.json` — Main settings (port, audio, timeouts)
- `milkyway-board_servo.json` — Servo/motor/LED pin assignments and calibration
- `milkyway-addresses.json` — Planet address book (local, canon + fan gates)
- `milkyway-ring_position.json` — Ring position persisted across reboots

### Threading Model

- Main thread: `stargate.update()` infinite loop
- Daemon thread: HTTP web server (port 8080)
- Daemon threads: keyboard input listeners
- Scheduled tasks via `schedule` library

### Web API

`classes/web_server.py` serves static files from `web/` and handles REST endpoints:
- `GET /get/is_alive`, `/get/dialing_status`, `/get/system_info`, etc.
- `POST` endpoints for control: dial, toggle wormhole, admin functions

The full API contract is in `api_spec.yaml` (OpenAPI/Swagger).

## Known Issues / Gaps

- `SERVOMotor` class in `electronics_servo_helpers.py` is an unused stub.
- Servo throttle values are hardcoded in `Chevron.__init__`, not config-driven.
- Chevrons 8 and 9 use `DCMotorSim()` — not physically wired.
- `configure_audio` in `install/functions.sh` hardcodes ALSA card `1`; the app corrects this at runtime via `set_correct_audio_output_device()`.
