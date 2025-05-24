#!/bin/bash
#
# Raspberry Pi Ubuntu Setup Script
# - Miniconda + 'statsenv' conda environment
# - Python packages for I2C OLED stats
# - I2C kernel config
# - MicroK8s install
# - Systemd service for stats.py
# - Halo-style progress indicators

set -e

# Spinner (Halo-style)
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
# 1) Update & install base packages
########################################
start_spinner "Updating package lists..."
sudo apt-get update -y
stop_spinner

start_spinner "Installing system packages..."
sudo apt-get install -y wget git i2c-tools libgpiod-dev libi2c0 read-edid
stop_spinner

########################################
# 2) Install Miniconda (ARM64)
########################################
start_spinner "Downloading Miniconda..."
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh
stop_spinner

start_spinner "Installing Miniconda to /opt..."
sudo bash miniconda.sh -b -p /opt/miniconda
stop_spinner

eval "$(/opt/miniconda/bin/conda shell.bash hook)"

start_spinner "Creating conda environment 'statsenv'..."
conda create -y -n statsenv python=3.9
stop_spinner

start_spinner "Activating 'statsenv' environment..."
conda activate statsenv
stop_spinner

########################################
# 3) Install Python packages (with gcc fix)
########################################
start_spinner "Installing compiler toolchain for Python packages..."
sudo apt-get install -y build-essential
stop_spinner

start_spinner "Installing Python packages in conda env..."
pip install \
  adafruit-circuitpython-ssd1306 \
  adafruit-python-shell \
  build \
  click \
  setuptools \
  gpiod \
  --upgrade --break-system-packages
stop_spinner

########################################
# 4) Clone Adafruit Scripts & run libgpiod.py
########################################
start_spinner "Setting /opt ownership to ylabs..."
sudo chown -R ylabs:ylabs /opt
stop_spinner

cd /opt
start_spinner "Cloning Adafruit Pi Installer Scripts..."
git clone https://github.com/adafruit/Raspberry-Pi-Installer-Scripts.git || echo "Already cloned."
stop_spinner

cd Raspberry-Pi-Installer-Scripts
start_spinner "Running libgpiod.py with conda Python..."
/opt/miniconda/envs/statsenv/bin/python libgpiod.py
stop_spinner

########################################
# 5) I2C kernel module and boot config
########################################
start_spinner "Loading I2C kernel modules..."
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708
stop_spinner

start_spinner "Enabling I2C on boot..."
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
echo "i2c-bcm2708" | sudo tee /etc/modules-load.d/i2c-bcm2708.conf >/dev/null
stop_spinner

start_spinner "Configuring /boot/firmware/config.txt..."
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt; then
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt >/dev/null
fi
stop_spinner

########################################
# 6) Install MicroK8s
########################################
start_spinner "Installing MicroK8s via snap..."
sudo snap install microk8s --classic
stop_spinner

start_spinner "Adding user '$USER' to microk8s group..."
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

start_spinner "Enabling mystats systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable mystats.service
stop_spinner

########################################
# 8) Final reboot
########################################
echo ""
echo "=============================================="
echo " Setup completed successfully!"
echo " System will reboot in 5 seconds..."
echo "=============================================="
sleep 5
sudo reboot
