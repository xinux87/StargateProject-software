#!/usr/bin/env bash
# deploy.sh — Diff, sync y restart del Stargate en la Raspberry Pi
#
# Uso:
#   bash scripts/deploy.sh            # diff + confirmar + deploy + restart
#   bash scripts/deploy.sh --dry-run  # solo muestra el diff, no toca nada
#   bash scripts/deploy.sh --no-restart  # deploy sin reiniciar el servicio

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Configuración — se puede sobreescribir con variables de entorno
# o en scripts/deploy.local.conf (gitignoreado)
# ──────────────────────────────────────────────────────────────────────────────
PI_HOST="${PI_HOST:-stargate.local}"
PI_USER="${PI_USER:-sg1}"
PI_PATH="${PI_PATH:-/home/sg1/sg1_v4}"
SUDO_PASS="${SUDO_PASS:-}"

LOCAL_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="$(dirname "${BASH_SOURCE[0]}")/deploy.local.conf"

if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Flags
# ──────────────────────────────────────────────────────────────────────────────
DRY_RUN=false
NO_RESTART=false
YES=false

for arg in "$@"; do
    case $arg in
        --dry-run)    DRY_RUN=true ;;
        --no-restart) NO_RESTART=true ;;
        --yes|-y)     YES=true ;;
        *) echo "Opción desconocida: $arg"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────────
# Colores
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}▶  $*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
error()   { echo -e "${RED}✖  $*${NC}"; exit 1; }
header()  { echo -e "\n${BOLD}━━━  $*  ━━━${NC}\n"; }

# ──────────────────────────────────────────────────────────────────────────────
# Opciones comunes de rsync
# Excluye: git, soundfx (400 MB de audio), pycache, logs, config (vive en la Pi)
# ──────────────────────────────────────────────────────────────────────────────
RSYNC_OPTS=(
    -avz
    --checksum
    --exclude='.git'
    --exclude='.claude'
    --exclude='soundfx'
    --exclude='__pycache__'
    --exclude='*.pyc'
    --exclude='logs'
    --exclude='config/milkyway-*.json'
    --exclude='*.local.md'
    --exclude='*.local.conf'
    --exclude='deploy.local.conf'
)

# ──────────────────────────────────────────────────────────────────────────────
# Comprobación de conexión SSH
# ──────────────────────────────────────────────────────────────────────────────
header "Stargate Deploy — ${PI_USER}@${PI_HOST}:${PI_PATH}"

info "Comprobando conexión SSH con la Pi..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${PI_USER}@${PI_HOST}" "exit" 2>/dev/null; then
    error "No se puede conectar a ${PI_USER}@${PI_HOST}. ¿Está la Pi encendida y en la red?"
fi
success "Conexión SSH OK"

# ──────────────────────────────────────────────────────────────────────────────
# DIFF — dry-run de rsync para ver qué cambia
# ──────────────────────────────────────────────────────────────────────────────
header "Diferencias: local → Pi"

DIFF_OUTPUT=$(rsync "${RSYNC_OPTS[@]}" --dry-run \
    "${LOCAL_PATH}/" \
    "${PI_USER}@${PI_HOST}:${PI_PATH}/" \
    | grep -v '/$' \
    | grep -v '^sending\|^sent\|^total\|^$' || true)

if [[ -z "$DIFF_OUTPUT" ]]; then
    success "No hay diferencias. La Pi ya está al día."
    if [[ "$DRY_RUN" == "true" ]]; then exit 0; fi
    # Si se pidió restart explícitamente (sin --dry-run), lo hacemos igualmente
else
    echo -e "${YELLOW}${DIFF_OUTPUT}${NC}"
    echo ""
    info "$(echo "$DIFF_OUTPUT" | wc -l) archivo(s) con diferencias."
fi

if [[ "$DRY_RUN" == "true" ]]; then
    warn "Modo --dry-run: no se ha modificado nada."
    exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# Confirmación
# ──────────────────────────────────────────────────────────────────────────────
if [[ -n "$DIFF_OUTPUT" ]] && [[ "$YES" == "false" ]]; then
    echo -e "${BOLD}¿Desplegar estos cambios y reiniciar el servicio? [s/N]${NC} \c"
    read -r CONFIRM < /dev/tty || true
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        warn "Operación cancelada."
        exit 0
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# DEPLOY — rsync real
# ──────────────────────────────────────────────────────────────────────────────
header "Desplegando archivos..."

rsync "${RSYNC_OPTS[@]}" \
    "${LOCAL_PATH}/" \
    "${PI_USER}@${PI_HOST}:${PI_PATH}/"

success "Archivos sincronizados."

# ──────────────────────────────────────────────────────────────────────────────
# RESTART del servicio
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$NO_RESTART" == "true" ]]; then
    warn "Reinicio omitido (--no-restart)."
    exit 0
fi

header "Reiniciando stargate.service..."

# Obtener la contraseña sudo si no está configurada
if [[ -z "$SUDO_PASS" ]]; then
    echo -e "${BOLD}Contraseña sudo de ${PI_USER}@${PI_HOST}:${NC} \c"
    read -rs SUDO_PASS
    echo ""
fi

ssh "${PI_USER}@${PI_HOST}" \
    "echo '${SUDO_PASS}' | sudo -S systemctl restart stargate.service 2>/dev/null"

success "Servicio reiniciado."

# ──────────────────────────────────────────────────────────────────────────────
# Estado del servicio y últimos logs
# ──────────────────────────────────────────────────────────────────────────────
header "Estado del servicio"

ssh "${PI_USER}@${PI_HOST}" \
    "systemctl status stargate.service --no-pager -n 5" || true

echo ""
header "Últimas líneas del log"

ssh "${PI_USER}@${PI_HOST}" \
    "tail -20 ${PI_PATH}/logs/milkyway.log 2>/dev/null || echo '(log vacío o no encontrado)'"

echo ""
success "Deploy completo. Stargate en marcha en http://${PI_HOST}:8080"
