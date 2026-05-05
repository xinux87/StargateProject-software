#!/bin/bash

# Detect the real user even when invoked via sudo
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
VENV_NAME="venv_v4"
VENV_DIR="$USER_HOME/$VENV_NAME"
SG1_DIR="$USER_HOME/sg1_v4"

cd "$USER_HOME"

# Remove the env if it already exists
[ -d "$VENV_DIR" ] && rm -Rf "$VENV_DIR"

echo "Initializing Python virtual environment in $VENV_DIR"
python3 -m venv "$VENV_DIR"

echo 'Installing pip setuptools into the virtual environment'
source "$VENV_DIR/bin/activate"
export CFLAGS=-fcommon
pip install setuptools | sed 's/^/     /'

echo 'Installing requirements.txt dependencies into the Virtual Environment'
pip install -r "$SG1_DIR/requirements.txt" | sed 's/^/     /'

echo 'Deactivating the virtual environment'
deactivate
