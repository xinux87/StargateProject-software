# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kristian's Stargate Project (SG1 v4) — a Python control system for a 3D-printed, fully functional Stargate replica running on a Raspberry Pi 3B+. Handles physical hardware (stepper motors, servos, LEDs, audio), a web-based control interface, REST API, and a WireGuard-based "Subspace Network" for connecting multiple gates together.

**This branch adds a new hardware variant:** the 9 chevrons can now be physically actuated with **continuous-rotation servo motors** instead of DC motors, controlled via a PCA9685 PWM board (I2C 0x40) alongside the existing Adafruit Motor HAT (I2C 0x60) for the ring stepper.

## Running the Project

```bash
# Development/manual run (requires root for GPIO)
sudo python3 main.py

# Systemd service (production)
sudo systemctl start stargate.service
sudo systemctl status stargate.service
journalctl -u stargate.service -f

# Tail runtime logs
tail -f ~/sg1_v4/logs/milkyway.log
```

The web interface is served at `http://stargate.local` (port 5000 by default via Avahi mDNS).

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
├── AncientsLogBook         — Thread-safe logging
├── Electronics (factory)   — Detects hardware via I2C, returns driver:
│     ├── Electronics_Servo        (servo-based board)
│     ├── ElectronicsOriginal      (Adafruit shield)
│     ├── ElectronicsMainBoard1V1  (custom mainboard)
│     └── ElectronicsNone          (simulation/no hardware)
├── StargateAudio           — Audio playback (simpleaudio)
├── NetworkTools            — IP/connectivity utilities
├── SoftwareUpdateV2        — Auto-update checker (gitpython)
├── StargateWebServer       — HTTP server (extends SimpleHTTPRequestHandler)
└── Stargate (main controller)
      ├── StargateSymbolManager   — 39-symbol constellation database
      ├── SymbolRing              — Stepper motor ring positioning
      ├── ChevronManager          — 9-chevron LED control
      ├── StargateAddressManager  — Planet/address database
      ├── Dialer                  — Keyboard or DHD input
      ├── WormholeManager         — Wormhole state machine & timing
      ├── WormholeAnimationManager — LED animation sequences
      ├── SubspaceClient          — Outgoing remote gate connections
      ├── SubspaceServer          — Incoming remote gate connections
      └── DialingLog              — Call history
```

### Hardware Abstraction

`classes/StargateMilkyWay/electronics.py` is a factory that detects connected hardware via I2C device signatures and returns the appropriate driver. This allows the software to run in simulation mode (`ElectronicsNone`) without physical hardware — useful for development.

| I2C signature detected | Mode | Driver |
|---|---|---|
| `0x60`, `0x61`, `0x62` | ORIGINAL | `ElectronicsOriginal` |
| `0x66`, `0x6f` | MAINBOARD_1V1 | `ElectronicsMainBoard1V1` |
| `0x40`, `0x60` | **SERVO** | **`Electronics_Servo`** |
| (none) | NONE | `ElectronicsNone` (simulation) |

### Servo Chevron Implementation (new)

Relevant files: `electronics_servo.py`, `electronics_servo_helpers.py`, `chevrons.py`, `config/defaults-milkyway/board_servo.json.dist`.

**Hardware setup (`Electronics_Servo`):**
- **Board 1** — PCA9685 at `0x40`, managed via `ServoKit(channels=16)`. Chevrons 1–7 are mapped to `continuous_servo[0..6]`.
- **Board 2** — Adafruit Motor HAT at `0x60`, used only for the ring stepper motor.
- Chevron LEDs remain on dedicated GPIO pins (6, 12, 13, 16, 19, 20, 21).
- Channels 8 and 9 fall back to `DCMotorSim()` (not physically wired yet).

**Motor type dispatch (`Chevron`):**  
The `Chevron` class detects whether its motor is a servo by inspecting `str(type(self.motor))` for the substring `'servo'`. This drives two separate code paths:

```python
def move_down(self):
    if self.motorTypeServo in self.motorType:
        self.move_down_servo()
    elif self.motorTypeDC in self.motorType:
        self.move_down_dcmotor()

def move_up(self):
    if self.motorTypeServo in self.motorType:
        self.move_up_servo()
    elif self.motorTypeDC in self.motorType:
        self.move_up_dcmotor()
```

**Key difference vs. DC motors:** servo methods do **not** set `throttle = None` after movement — continuous servos stop when throttle is `0`, but the code intentionally leaves the throttle set so the servo holds its position. On startup, every servo chevron calls `move_up_servo()` to home itself.

**Throttle values (hardcoded in `Chevron.__init__`):**
- Down (unlock): `chevron_down_servo_throttle = -0.5`
- Up (lock): `chevron_up_servo_throttle = 0.7`
- DC equivalents are read from config (`chevron_down_throttle`, `chevron_up_throttle`) — the servo values are not yet config-driven.

**Known gap:** `SERVOMotor` in `electronics_servo_helpers.py` is a stub (the `__init__` references `self.log` without assigning it). It is not currently used — `Electronics_Servo` uses `continuous_servo` objects from `ServoKit` directly.

### Configuration System

All config lives in `config/` as JSON files named `milkyway-*.json`. Default templates in `config/defaults-milkyway/*.json.dist` are auto-copied if the active config is missing.

```python
# Config access pattern throughout the codebase
value = self.cfg.get('key_name')  # returns config['key']['value']
```

Key config files:
- `milkyway-config.json` — Main settings (port, audio, update, subspace IPs)
- `milkyway-board_servo.json` — Servo/motor/LED pin assignments and calibration
- `milkyway-addresses.json` — Planet address book (canon + fan gates)
- `milkyway-ring_position.json` — Ring position persisted across reboots

### Threading Model

- Main thread: `stargate.update()` infinite loop
- Daemon thread: HTTP web server
- Daemon thread: SubspaceServer (incoming remote gate listener)
- Scheduled tasks via `schedule` library (fan gate refresh every 30 min, update check every 6 hours)

### Multi-Galaxy Support

Core/shared classes are in `classes/`. Galaxy-specific implementations are in `classes/StargateMilkyWay/`. The active galaxy is set via `GALAXY = "Milky Way"` in `main.py`. Config files are segregated by galaxy path prefix.

### Web API

`classes/web_server.py` serves static files from `web/` and handles REST endpoints:
- `GET /get/is_alive`, `/get/dialing_status`, `/get/system_info`, etc.
- `POST` endpoints for control: dial, toggle wormhole, admin functions

The full API contract is in `api_spec.yaml` (OpenAPI/Swagger).

### Subspace Network

WireGuard-based mesh network allowing remote Stargate gates to dial each other. `SubspaceClient` initiates outgoing connections; `SubspaceServer` listens for incoming dialing commands. Utility scripts in `util/` manage WireGuard keys and config.
