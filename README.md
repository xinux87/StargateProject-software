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

## Hardware Variants

The software automatically detects the connected hardware via I2C at startup and loads the appropriate driver.

| I2C devices detected | Hardware variant | Chevron actuation |
|---|---|---|
| `0x60`, `0x61`, `0x62` | Original Adafruit shields | DC motors |
| `0x66`, `0x6f` | Custom Mainboard v1.1 | DC motors |
| `0x40`, `0x60` | **PCA9685 + Adafruit Motor HAT** | **Continuous-rotation servos** |
| (none detected) | Simulation mode | — |

### Servo variant (PCA9685 + Adafruit Motor HAT)

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
| Wormhole Open | Button | Open a wormhole manually |
| Wormhole Close | Button | Close the active wormhole |
| Simulate Incoming | Button | Trigger an incoming wormhole simulation |
| Abort Dial | Button | Cancel an in-progress dialing sequence |

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