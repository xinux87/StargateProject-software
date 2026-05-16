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

### Lamp Mode

The LED wormhole strip can be repurposed as a generic RGB light (lamp mode), independent of Stargate dialing. Lamp mode state lives entirely in `Stargate` and is accessible via the REST API and Home Assistant.

**State variables (`Stargate.__init__`):**
| Variable | Type | Default | Description |
|---|---|---|---|
| `lamp_mode` | `bool` | `False` | Whether lamp mode is active |
| `lamp_color` | `tuple[int,int,int]` | `(255,255,255)` | RGB color |
| `lamp_brightness` | `int` | `255` | Brightness scale 0–255 |
| `lamp_animation` | `str` | `'static'` | Active animation ID |
| `lamp_animation_active` | `bool` | `False` | Set to `False` to stop animation thread |
| `_lamp_animation_thread` | `Thread\|None` | `None` | Background daemon thread |

**Available animations (`Stargate.LAMP_ANIMATIONS`):**

| ID | Name | Description |
|---|---|---|
| `static` | Static Color | Solid color at configured RGB + brightness |
| `wormhole` | Wormhole Effect | Continuous random fade/sweep transitions with standard blue patterns |
| `black_hole` | Black Hole | Same transitions with red/dark palette |
| `kawoosh` | Kawoosh Loop | Repeating kawoosh opening animation |

**Control flow:**
```
set_lamp_mode(True, animation='wormhole')
  → _stop_lamp_animation()          # stops any previous thread
  → shutdown(...)                    # clears dialing state
  → lamp_animation = 'wormhole'
  → lamp_mode = True
  → _start_lamp_animation()
      → Thread(_run_lamp_animation)  # daemon=True

_run_lamp_animation():
  while lamp_animation_active and lamp_mode:
    animation_manager.do_random_transitions()   # blocks per cycle

set_lamp_mode(False)  OR  auto-off on Stargate activity:
  → _stop_lamp_animation()           # sets lamp_animation_active=False, joins thread
  → lamp_mode = False
  → animation_manager.clear_wormhole()
```

**Auto-off:** `update()` calls `_stop_lamp_animation()` and clears lamp mode whenever `address_buffer_outgoing`, `address_buffer_incoming`, or `wormhole_active` become truthy.

**Animation manager integration:** `WormholeAnimationManager.rotate_pattern()` and `fade_transition()` check `stargate.wormhole_active OR stargate.lamp_animation_active` as their stop condition, allowing both wormhole and lamp animation threads to drive them.

### Threading Model

- Main thread: `stargate.update()` infinite loop
- Daemon thread: HTTP web server (port 8080)
- Daemon threads: keyboard input listeners
- Daemon thread: lamp animation loop (when a non-static animation is active)
- Scheduled tasks via `schedule` library

### Web API

`classes/web_server.py` serves static files from `web/` and handles REST endpoints. The full API contract is in `api_spec.yaml` (OpenAPI/Swagger).

**Lamp-related endpoints:**

| Method | Path | Description |
|---|---|---|
| `GET` | `/get/lamp_status` | Returns current lamp state (mode, color, brightness, animation) |
| `GET` | `/get/lamp_animations` | Returns list of available animations with `id` and `name` |
| `POST` | `/do/lamp_on` | Enable lamp mode. Body: `{color, brightness, animation}` (all optional) |
| `POST` | `/do/lamp_off` | Disable lamp mode |
| `POST` | `/do/lamp_set` | Update color/brightness/animation while lamp is active |

`/get/dialing_status` also includes `lamp_mode`, `lamp_color`, `lamp_brightness`, and `lamp_animation` so the HA coordinator gets everything in one poll.

### Home Assistant Integration

Custom component at `homeassistant/custom_components/stargate/`. Polls `/get/dialing_status` + `/get/system_info` every 2 seconds via `StargateCoordinator`.

**Entities:**

| File | Entity | Description |
|---|---|---|
| `light.py` | `{Gate} Lamp` | RGB light with brightness. Turn on/off, set color. |
| `select.py` | `{Gate} Lamp Animation` | Dropdown: Static Color / Wormhole Effect / Black Hole / Kawoosh Loop |
| `select.py` | `{Gate} Target Planet` | Dropdown to dial a destination planet |
| `binary_sensor.py` | Wormhole Active, Dialing In Progress | State sensors |
| `sensor.py` | State, Locked Chevrons, Connected Planet, Time Remaining | Sensors |
| `button.py` | Wormhole Open/Close, Simulate Incoming, Abort Dial | Action buttons |
| `switch.py` | Silence Mode | Toggle silence |
| `number.py` | Volume | Slider 0–100 |

**Lamp Animation selector behavior:**
- If lamp is ON: sends `POST /do/lamp_set {"animation": id}` → switches animation instantly
- If lamp is OFF: sends `POST /do/lamp_on {"animation": id}` → turns lamp on with selected animation

**Setup:** `coordinator.async_setup()` fetches `/get/lamp_animations` once at startup (with a hardcoded fallback if the gate firmware is older).

**Reload after update:**  
HA: Developer Tools → YAML → Reload Custom Integrations, or restart HA.  
Pi: `sudo systemctl restart stargate.service`

## Known Issues / Gaps

- `SERVOMotor` class in `electronics_servo_helpers.py` is an unused stub.
- Servo throttle values are hardcoded in `Chevron.__init__`, not config-driven.
- Chevrons 8 and 9 use `DCMotorSim()` — not physically wired.
- `configure_audio` in `install/functions.sh` hardcodes ALSA card `1`; the app corrects this at runtime via `set_correct_audio_output_device()`.
- Lamp animation thread uses `t.join(timeout=3)` on stop — if a `do_random_transitions` cycle takes longer (e.g. slow fade on many LEDs), the thread may outlive the join.
