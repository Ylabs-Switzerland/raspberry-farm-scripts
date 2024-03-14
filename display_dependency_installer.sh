#!/bin/bash

# This script installs necessary packages and configures I2C on a Raspberry Pi running Ubuntu.

# Exit immediately if a command exits with a non-zero status.
set -e

# Update package lists
sudo apt-get update

# Install Python3 pip and PIL (Python Imaging Library)
sudo apt-get install -y python3-pip python3-pil

# Install Python packages using pip
sudo pip3 install adafruit-circuitpython-ssd1306 adafruit-python-shell build click setuptools gpiod --upgrade --break-system-packages

# Change ownership of the current directory (previously missing target directory)
# Assuming /opt is the intended directory for changing ownership to 'ylabs:ylabs'
sudo chown -R ylabs:ylabs /opt

# Navigate to /opt and clone the Raspberry Pi Installer Scripts repository
cd /opt
git clone https://github.com/adafruit/Raspberry-Pi-Installer-Scripts.git || echo "Git repo already cloned."

cd Raspberry-Pi-Installer-Scripts
sudo python3 libgpiod.py

# Load the I2C kernel modules
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708

# Ensure the I2C kernel modules are loaded on boot
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf > /dev/null
echo "i2c-bcm2708" | sudo tee /etc/modules-load.d/i2c-bcm2708.conf > /dev/null

# Enable I2C via the boot config (might not be necessary on all setups)
# Append dtparam=i2c_arm=on if not already set in /boot/firmware/config.txt
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt; then
    echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt > /dev/null
fi

sudo apt install -y i2c-tools

echo "Setup completed successfully."

echo "creating systemd service for stats.py"
# Create a systemd service file for our custom service
cat <<EOF | sudo tee /etc/systemd/system/mystats.service
[Unit]
Description=My Python Script Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/raspberry-farm-scripts/stats.py
User=root
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload the systemd daemon to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable mystats.service

echo "Setup completed successfully. The system will now reboot in 5 seconds..."
sleep 5
sudo reboot
