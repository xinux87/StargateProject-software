# [TheStargateProject.com](https://TheStargateProject.com)
![GitHub License](https://img.shields.io/github/license/jonnerd154/StargateProject-software)
[![Generate Raspberry Pi OS Image](https://github.com/jonnerd154/StargateProject-software/actions/workflows/rpi.yml/badge.svg)](https://github.com/jonnerd154/StargateProject-software/actions/workflows/rpi.yml)

Software for Kristian's Fully Functional 3D Printed Stargate

## Setup Instructions:
It is _highly_ recommended to build your gate by using the pre-built Disk Image (ISO) provided by Kristian.
 - If you are **upgrading an existing gate** read this first: [UPGRADING_FROM_V3.X.md](UPGRADING_FROM_V3.X.md)
 - EXPRESS SETUP process can be found in [EXPRESS_SETUP.md](EXPRESS_SETUP.md)
 - A manual setup guide can be found in [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md)

## Default SSH/SCP credentials
```
Username: pi
Password: sg1
```

## Start/Stop/Restart the Stargate Software manually
The Stargate Software will automatically start when the Raspi boots. It runs as a systemd daemon called `stargate.service`. If you want to manually start/stop/restart it, you can use these commands:
```
sudo systemctl start stargate.service
sudo systemctl stop stargate.service
sudo systemctl restart stargate.service
```

## Web interface
A web interface is provided to allow testing of individual hardware components, dialing, address book, and much more. Find it here:

[http://stargate.local](http://stargate.local)

## Web API
There is a JSON API to interact with the Stargate via a web service. This enables anyone to build software that can control the Stargate. We'd love to see someone build a Stargate Command computer-style controller, or a RPG game that interfaces with the 'Gate. Your imagination is the limit!

The documentation can be found in the repo, or at one of the below links

- v1.0.0 (Current): https://app.swaggerhub.com/apis-docs/TheStargateProject/StargateWebAPI/1.0.0#/
- v1.1.0 (In development): https://app.swaggerhub.com/apis-docs/TheStargateProject/StargateWebAPI/1.1.0

## Mobile App (Android & iOS)

A native Flutter application provides full **Bluetooth Low Energy (BLE)** control of the Stargate — no WiFi or internet connection required on the phone.

> Full documentation, build instructions, and BLE protocol reference: [mobile_app/README.md](mobile_app/README.md)

### Features

- Scan for and connect to the Stargate via BLE (PIN-protected)
- Full DHD dialing: press symbols, lock chevrons, open/close wormhole
- Simulate incoming wormhole
- Lamp mode: RGB color picker, brightness, animated effects
- WiFi management: scan, connect, disconnect, rename hostname
- Hardware tests: chevrons, ring, LEDs, audio
- Live gate status pushed every 2 seconds

### Quick Start

**On the Raspberry Pi (one-time setup):**

```bash
# Install BLE server library
sudo /home/sg1/venv_v4/bin/pip install bless

# Enable BlueZ experimental features (required for GATT advertising)
sudo mkdir -p /etc/systemd/system/bluetooth.service.d
sudo tee /etc/systemd/system/bluetooth.service.d/experimental.conf > /dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental
EOF
sudo systemctl daemon-reload && sudo systemctl restart bluetooth

# On Pi Zero 2W — unblock the BT radio
sudo rfkill unblock bluetooth

# Restart the gate software
sudo systemctl restart stargate.service
```

**Build the Android APK (from WSL/Linux):**

```bash
cd mobile_app
export ANDROID_SDK_ROOT=~/android-sdk
export PATH=$PATH:~/flutter/bin:~/android-sdk/cmdline-tools/latest/bin
flutter pub get
flutter build apk --release
# APK → mobile_app/build/app/outputs/flutter-apk/app-release.apk
```

**iOS:** Open `mobile_app/ios/Runner.xcworkspace` in Xcode, set your signing team, and run on device.

### BLE Configuration

In `config/milkyway-config.json`:

```json
{
  "bluetooth_enabled": true,
  "bluetooth_device_name": "Stargate",
  "bluetooth_pin": "1969"
}
```

### Architecture

The BLE server (`classes/bluetooth_server.py`) runs as a daemon thread alongside the HTTP server. It exposes a single GATT service with three characteristics:

| Characteristic | Direction | Purpose |
|---|---|---|
| CMD | Client → Gate | Send JSON commands |
| RESPONSE | Gate → Client | Per-command reply (notify) |
| STATUS | Gate → Client | State push every 2 s (notify + read) |

Large payloads are automatically split into 180-byte chunks with a 1-byte sequence prefix. The Flutter app reassembles them transparently.

## Hardware Variants

The software automatically detects the connected hardware via I2C at startup and loads the appropriate driver.

| I2C devices detected | Hardware variant | Chevron actuation |
|---|---|---|
| `0x60`, `0x61`, `0x62` | Original Adafruit shields | DC motors |
| `0x66`, `0x6f` | Custom Mainboard v1.1 | DC motors |
| `0x40`, `0x60` | **PCA9685 + Adafruit Motor HAT** | **Continuous-rotation servos** |
| (none detected) | Simulation mode | — |

### Servo variant (PCA9685 + Adafruit Motor HAT)

> Full hardware details, BOM, wiring diagram and 3D files: [Stargate Readme Hardware PCA9685PW +Adafruit Servo Hat.md](Stargate%20Readme%20Hardware%20PCA9685PW%20%2BAdafruit%20Servo%20Hat.md)

This variant drives the 9 chevrons with **continuous-rotation servo motors** controlled through a PCA9685 PWM board:

- **PCA9685** (I2C `0x40`) — controls chevron servos on channels 0–6 (chevrons 1–7) via `ServoKit`.
- **Adafruit Motor HAT** (I2C `0x60`) — controls the symbol ring stepper motor.
- Chevron LEDs remain on GPIO pins (6, 12, 13, 16, 19, 20, 21).
- Chevron motor and LED channel assignments are configurable in `config/milkyway-board_servo.json`.

The servo throttle values (speed and direction for lock/unlock) are defined in `classes/StargateMilkyWay/chevrons.py`.

## Home Assistant Integration

A custom component is included to integrate the Stargate with [Home Assistant](https://www.home-assistant.io/).

### Installation

1. Copy the `homeassistant/custom_components/stargate/` folder into your Home Assistant `config/custom_components/` directory.
2. Restart Home Assistant.
3. Go to **Settings → Devices & Services → Add Integration** and search for **Stargate**.
4. Enter the IP address and port of your Stargate (default port: `8080`).

The integration also supports **automatic discovery** via Zeroconf if your Stargate and Home Assistant are on the same network.

### Entities

All entities are grouped under a single **Stargate** device.

| Entity | Type | Description |
|---|---|---|
| State | Sensor | Current gate state: `idle`, `dialing`, or `open` |
| Locked Chevrons | Sensor | Number of chevrons currently locked (0–9) |
| Connected Planet | Sensor | Name of the connected planet, or empty when idle |
| Wormhole Remaining | Sensor | Seconds until the wormhole closes (duration) |
| Wormhole Active | Binary Sensor | `on` while a wormhole is open |
| Dialing | Binary Sensor | `on` while a dialing sequence is in progress |
| Target Planet | Select | Dial any planet from the address book; select `Standby` to abort |
| Volume | Number | Audio volume (0–100 slider) |
| Silence Mode | Switch | When `on`, only LEDs activate during dialing — motors and audio are disabled |
| Lamp | Light | Control the LED strip as an RGB light (see below) |
| Wormhole Open | Button | Open a wormhole manually |
| Wormhole Close | Button | Close the active wormhole |
| Simulate Incoming | Button | Trigger an incoming wormhole simulation |
| Abort Dial | Button | Cancel an in-progress dialing sequence |

### Lamp mode

The **Lamp** entity exposes the NeoPixel LED strip (122 LEDs, WS2812B) as a standard Home Assistant `light` with full RGB color and brightness control.

**Mutual exclusion:** lamp mode and Stargate mode are mutually exclusive.

- Turning the lamp **on** cancels any active dialing sequence or wormhole and takes over the LED strip.
- The lamp turns **off automatically** when any Stargate activity is detected: an incoming or outgoing symbol is received, a wormhole becomes active, or any of the 5 explicit actions are triggered via the API or HA buttons (Wormhole Open, Wormhole Close, Simulate Incoming, Abort Dial, DHD Press).
- Turning the lamp **off** clears the LEDs and returns the gate to idle, ready for dialing.

**API endpoints:**

| Method | Path | Body | Description |
|---|---|---|---|
| `GET` | `/get/lamp_status` | — | Returns `lamp_mode`, `color [R,G,B]`, `brightness` |
| `POST` | `/do/lamp_on` | `{"color": [R,G,B], "brightness": 0-255}` | Enable lamp mode (fields optional) |
| `POST` | `/do/lamp_off` | — | Disable lamp mode, clear LEDs |
| `POST` | `/do/lamp_set` | `{"color": [R,G,B], "brightness": 0-255}` | Update color/brightness while lamp is on |

### Example automation

```yaml
automation:
  - alias: "Close wormhole when I leave home"
    trigger:
      - platform: state
        entity_id: person.your_name
        to: "not_home"
    condition:
      - condition: state
        entity_id: binary_sensor.stargate_wormhole_active
        state: "on"
    action:
      - service: button.press
        target:
          entity_id: button.stargate_wormhole_close
```

## Credits
- Kristian Tysse designed and wrote all of the original code, most of which is still in use today's program.
- Jonathan Moyes restructured the code and extended it to include additional functionalities.
- The Web UI and basic implementation of the Stargate API Server were based on Dan Clarke's work: https://github.com/danclarke/WorkingStargateMk2Raspi

Stargate SG-1, Stargate Atlantis & Stargate Universe are ™ & © of Metro-Goldwyn-Mayer Studios Inc.  This project is in no way sponsored or endorsed by: SyFy or MGM. This project was created solely as a hobby project and to help other Stargate fans create their own Stargates and to keep the passion and love for Stargate alive.

TheStargateProject.com is a fan-based project and is not intended to infringe upon any copyrights or registered trademarks.

# Development
## Running PyLint
 - To run for StargateMilkyWay: `pylint --rcfile=.pylintrc-milkyway ./*`
 - To run for StargatePegasus:  `pylint --rcfile=.pylintrc-pegasus ./*`

## Helpful Commands
 - Tail the software logs: `tail -f ~/sg1_v4/logs/*`
 - Tail the systemd log: `journalctl -u stargate.service -f`