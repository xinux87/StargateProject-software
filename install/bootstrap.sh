#!/bin/bash

# Detect the real user even when invoked via sudo
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SG1_DIR="$USER_HOME/sg1_v4"

sudo apt-get install --no-install-recommends git
cd "$USER_HOME"
git clone https://github.com/xinux87/StargateProject-software.git sg1_v4
sudo chmod u+x "$SG1_DIR/install/"*.sh
cd "$SG1_DIR/install" && ./install.sh
