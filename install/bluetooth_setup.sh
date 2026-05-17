#!/usr/bin/env bash
# Bluetooth setup for Stargate BLE server
# Run as root: sudo bash install/bluetooth_setup.sh
#
# Note: no stargate.service template was found in install/ at the time this script
# was created. If you add a service file later, include bluetooth.target in its
# After= line, e.g.:
#   After=network.target sound.target bluetooth.target
#
# To make this script executable after copying to the Pi:
#   chmod +x install/bluetooth_setup.sh

set -e

echo "Installing Bluetooth dependencies..."
apt-get update -q
apt-get install -y bluez bluetooth libbluetooth-dev libglib2.0-dev python3-dbus

echo "Enabling Bluetooth service..."
systemctl enable bluetooth
systemctl start bluetooth

echo "Configuring Bluetooth adapter..."
# Give it a moment to initialize
sleep 2
bluetoothctl power on || true
bluetoothctl pairable on || true

echo "Adding sg1 user to bluetooth group..."
usermod -a -G bluetooth sg1 2>/dev/null || true

echo "Bluetooth setup complete."
echo "Restart the stargate service: sudo systemctl restart stargate.service"
