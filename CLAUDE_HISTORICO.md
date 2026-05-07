# CLAUDE_HISTORICO.md

Registro de cambios realizados por sesiones de trabajo con Claude Code.

---

## Sesión 2026-05-05 — Deployment en Raspberry Pi Zero 2W

**Rama:** `sg1_without_internet`  
**Objetivo:** Instalar y arrancar el software en una Pi Zero 2W limpia (Debian 13 trixie, Python 3.13, 512 MB RAM).  
**Estado final:** `stargate.service` activo y funcionando.

### Problemas encontrados y soluciones

#### 1. `util/*` chmod falla en install.sh
- **Causa:** El directorio `util/` fue eliminado en este branch (scripts de WireGuard/Subspace) pero `set_permissions()` en `functions.sh` hacía `chmod u+x util/*` incondicionalmente.
- **Fix:** Añadido guard `[ -d "$SG1_DIR/util" ]` antes del chmod. Mismo fix para `scripts/`.
- **Fichero:** `install/functions.sh` → `set_permissions()`

#### 2. `AttributeError: module 'adafruit_platformdetect.constants.boards' has no attribute 'ORANGE_PI_3'`
- **Causa:** `Adafruit-Blinka~=7.0.0` (pinado) referenciaba la constante `ORANGE_PI_3` que no existe en `adafruit-platformdetect~=3.13.0`. Incompatibilidad de versiones que emerge en Python 3.13.
- **Fix:** Desancladas todas las versiones de librerías Adafruit en `requirements.txt` (de `~=` a `>=`) para que pip resuelva un conjunto compatible. Versiones instaladas: Blinka 9.1.0, PlatformDetect 3.88.0, etc.
- **Fichero:** `requirements.txt`

#### 3. Segfault de `simpleaudio` en Python 3.13 / Debian 13 / aarch64
- **Causa:** `simpleaudio 1.0.4` llama a `snd_pcm_open()` de ALSA desde código C. En la combinación Python 3.13 + Debian 13 + aarch64, esta llamada produce SIGSEGV. No se puede capturar con try/except de Python.
- **Diagnóstico:** Confirmado ejecutando `python3 -c "import simpleaudio as sa; sa.WaveObject.from_wave_file(...).play()"` → exit code 139 (SEGV).
- **Fix:** Creado `classes/audio_player.py` como reemplazo drop-in de `simpleaudio`. Implementa la misma API (`WaveObject`, `PlayObject`) usando `subprocess.Popen(['aplay', '-q', path])`. La reproducción ocurre en un proceso hijo, aislando cualquier crash. Actualizado `stargate_audio.py` para importar `audio_player as sa`.
- **Ficheros:** `classes/audio_player.py` (nuevo), `classes/stargate_audio.py`

#### 4. `lgpio.error: 'GPIO busy'` con lgpio
- **Causa:** Al instalar `lgpio`, `gpiozero` lo prefiere sobre `RPi.GPIO`. `lgpio` es más estricto y marca los pines como "ocupados" si un proceso previo los reclamó sin liberarlos (proceso crasheado).
- **Fix:** Reboot de la Pi limpia el estado de GPIO. Con la sesión limpia y `lgpio` instalado, `gpiozero` funciona correctamente.
- **Acción:** Añadido `lgpio>=0.2.0` a `requirements.txt` y `swig` + `liblgpio-dev` al apt install (necesarios para compilar el paquete pip de `lgpio`).

#### 5. `SyntaxWarning: invalid escape sequence '\{'`
- **Causa:** Dos f-strings en `stargate_audio.py` usaban `\{` dentro de la cadena, que en Python 3.12+ genera `SyntaxWarning` (y en el futuro será `SyntaxError`).
- **Fix:** Cambiado `\{` por `\\{` (backslash literal) en los dos `subprocess.run(['sudo', 'sed', ...])` de `set_correct_audio_output_device()`.
- **Fichero:** `classes/stargate_audio.py`

#### 6. `sudo cp /boot/config.txt /boot/config.bak` falla
- **Causa:** En Pi OS Bookworm/Trixie, el fichero de configuración de boot es `/boot/firmware/config.txt`, no `/boot/config.txt`. La línea de backup apuntaba a la ruta antigua que no existe.
- **Fix:** Cambiado a `sudo cp "$CONFIG" "${CONFIG}.bak"` donde `CONFIG='/boot/firmware/config.txt'`.
- **Fichero:** `install/functions.sh` → `disable_onboard_audio()`

#### 7. `aplay` no disponible en instalación limpia
- **Causa:** `alsa-utils` (que provee `aplay`) no estaba en la lista de paquetes apt del instalador, pero es necesario para el nuevo `audio_player.py`.
- **Fix:** Añadido `alsa-utils` al `apt-get install` en `apt_update_and_install()`.
- **Fichero:** `install/functions.sh`

### Commits generados

| Hash | Descripción |
|---|---|
| `b0dc583` | Fix Pi Zero 2W deployment: Adafruit version pins and install script |
| `c23e1e0` | Fix Pi Zero 2W deployment: replace simpleaudio, add lgpio, fix audio |
| `7a0b009` | install: add swig/liblgpio-dev/alsa-utils, fix boot config backup |

### Proceso de deployment usado

1. `ssh-copy-id sg1@<IP_DE_LA_PI>` — clave SSH sin contraseña
2. `sudo apt-get install -y git` — git no estaba instalado
3. `git clone -b sg1_without_internet <repo> ~/sg1_v4`
4. `rsync -av ./soundfx/ sg1@<IP_DE_LA_PI>:/home/sg1/sg1_v4/soundfx/` — 382 MB de audio fuera del repo
5. `sudo bash install.sh` — instalador completo (apt, venv, apache, systemd)
6. Correcciones iterativas vía rsync de ficheros individuales + `systemctl restart`

### Estado final

```
stargate.service: active (running)
Hardware: Electronics Servo PCA9685 Board + Adafruit HAT
I2C detectado: [0x40, 0x60]
Audio: USB AB13X (card 0), playback via aplay subprocess
API: http://<IP_DE_LA_PI>:8080
```

---

## Sesiones anteriores

### 2026-05-04 — Optimizaciones de memoria para Pi Zero 2W (commit `8fe914c`)

- `ancients_log_book.py`: `threading.Lock` movido a `__init__`; rotación de log a 2 MB con 1 backup.
- `stargate_audio.py`: lazy-load de WAVs de wormhole; caché de clips aleatorios.
- `stargate_address_book.py`: métodos de búsqueda iteran directamente sin `.copy()`.
- `wormhole_animation_manager.py`: `rotate_pattern` usa `deque.rotate()` (in-place); `sleep(0.005)` para ceder CPU; reemplazados loops manuales de NeoPixel.
- `keyboard_manager.py`: threads de input marcados como daemon; eliminada referencia a `subspace_client` que crasheaba.

### 2026-05-04 — Eliminación de dependencias de internet (commit `95a42a6`)

- Eliminados: rollbar, gitpython, requests, icmplib, urllib3, certifi, chardet, idna, python-dotenv de `requirements.txt`.
- `software_update_v2.py` reemplazado por stub mínimo (sin gitpython, sin GitHub fetch).
- `SubspaceClient`, `SubspaceServer` y lógica fan-gate eliminados de `stargate.py`.
- `stargate_address_manager.py`: eliminada actualización online de fan gates.
- `web_server.py`: eliminadas referencias a subspace_client.
- `network_tools.py`: reducido a helpers locales (eliminados icmplib, internet checks).

### 2026-05-05 — Limpieza final y fix de scripts de instalación (commit `4593824`)

- Eliminados `SoftwareUpdateV2`, `SubspaceClient`, `SubspaceServer`, `SubspaceMessages` y todas las referencias.
- Eliminados scripts util de WireGuard y `.github/` CI image builder.
- `install/functions.sh`: eliminada contraseña sg1 hardcodeada; fix de crontab bajo `REAL_USER`; alineado binario python3 entre crontab y systemd.
- `install/bootstrap.sh`: detección de usuario con sudo, URL correcta del repo.
- `install/install.sh`: hint SSH muestra `REAL_USER` en vez de `pi`.
- `install/audio.sh`: índice de tarjeta ALSA alineado a 1.
