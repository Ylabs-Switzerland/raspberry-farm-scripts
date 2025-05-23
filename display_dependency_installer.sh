#!/bin/bash
#
# Full Raspberry Pi setup script for Ubuntu (64-bit)
# - Miniconda installation + conda env
# - Python libs in conda
# - I2C setup
# - mystats systemd service
# - MicroK8s install & enable

set -e

# Spinner (halo-like)
spin='-\|/'
i=0
spinner_pid=0

start_spinner() {
  echo -n "$1 "
  (
    while true; do
      i=$(( (i+1) %4 ))
      printf "\b${spin:$i:1}"
      sleep 0.1
    done
  ) &
  spinner_pid=$!
  disown
}

stop_spinner() {
  if [ "$spinner_pid" != "0" ]; then
    kill "$spinner_pid" &>/dev/null || true
    spinner_pid=0
    echo -e "\b Done."
  fi
}

########################################
# 1) Update & install system packages
########################################
start_spinner "Updating package lists..."
sudo apt-get update -y
stop_spinner

start_spinner "Installing system tools..."
sudo apt-get install -y wget git i2c-tools libgpiod-dev
stop_spinner

########################################
# 2) Install Miniconda (ARM64)
########################################
start_spinner "Downloading Miniconda..."
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh
stop_spinner

start_spinner "Installing Miniconda..."
sudo bash miniconda.sh -b -p /opt/miniconda
stop_spinner

eval "$(/opt/miniconda/bin/conda shell.bash hook)"

start_spinner "Creating conda environment 'statsenv'..."
conda create -y -n statsenv python=3.9
stop_spinner

start_spinner "Activating conda environment..."
conda activate statsenv
stop_spinner

########################################
# 3) Install Python dependencies (conda env)
########################################
start_spinner "Installing Python packages into 'statsenv'..."
pip install adafruit-circuitpython-ssd1306 adafruit-python-shell build click setuptools gpiod --upgrade --break-system-packages
stop_spinner

########################################
# 4) Clone Adafruit repo & run libgpiod.py
########################################
start_spinner "Setting permissions for /opt..."
sudo chown -R ylabs:ylabs /opt
stop_spinner

cd /opt
start_spinner "Cloning Raspberry Pi Installer Scripts..."
git clone https://github.com/adafruit/Raspberry-Pi-Installer-Scripts.git || echo "Already cloned."
stop_spinner

cd Raspberry-Pi-Installer-Scripts
start_spinner "Running libgpiod.py..."
/opt/miniconda/envs/statsenv/bin/python libgpiod.py
stop_spinner

########################################
# 5) Setup I2C modules & boot config
########################################
start_spinner "Loading I2C kernel modules..."
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708
stop_spinner

start_spinner "Configuring I2C to load on boot..."
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
echo "i2c-bcm2708" | sudo tee /etc/modules-load.d/i2c-bcm2708.conf >/dev/null
stop_spinner

start_spinner "Ensuring I2C enabled in /boot/firmware/config.txt..."
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt; then
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt >/dev/null
fi
stop_spinner

########################################
# 6) Install MicroK8s & enable
########################################
start_spinner "Installing MicroK8s..."
sudo snap install microk8s --classic
stop_spinner

start_spinner "Adding '$USER' to microk8s group..."
sudo usermod -aG microk8s "$USER"
stop_spinner

start_spinner "Waiting for MicroK8s to be ready..."
sudo microk8s status --wait-ready
stop_spinner

########################################
# 7) Create systemd service
########################################
echo "Creating mystats.service..."

cat <<EOF | sudo tee /etc/systemd/system/mystats.service
[Unit]
Description=My Python Script Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/miniconda/envs/statsenv/bin/python /opt/raspberry-farm-scripts/stats.py
User=root
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

start_spinner "Reloading systemd & enabling mystats.service..."
sudo systemctl daemon-reload
sudo systemctl enable mystats.service
stop_spinner

########################################
# 8) Reboot
########################################
echo ""
echo "=============================================="
echo " Setup completed successfully."
echo " Rebooting system in 5 seconds..."
echo "=============================================="
sleep 5
sudo reboot
