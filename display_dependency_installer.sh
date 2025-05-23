
#!/bin/bash
#
# This script sets up a Raspberry Pi on Ubuntu with:
#  - Miniconda & a dedicated conda environment
#  - I2C configuration and necessary Python libs for SSD1306 usage
#  - A systemd service (mystats.service) that runs stats.py from the conda environment
#  - MicroK8s installation and autostart

# Exit immediately if a command exits with a non-zero status
set -e

#######################################
# Simple "halo-style" spinner function
# usage:
#   start_spinner "Your message..."
#   # run your command
#   stop_spinner
#######################################
spin='-\|/'
i=0
spinner_pid=0

start_spinner() {
  echo -n "$1 "
  (
    while true
    do
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

#######################################
# 1) Update and install system dependencies
#######################################
start_spinner "Updating APT package lists..."
sudo apt-get update -y
stop_spinner

start_spinner "Installing system dependencies..."
sudo apt-get install -y \
    wget \
    git \
    i2c-tools \
    python3-gpiod  # needed for i2c detection tools & gpiod system library
stop_spinner

#######################################
# 2) Install Miniconda
#######################################
start_spinner "Downloading Miniconda for ARM64..."
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh
stop_spinner

start_spinner "Installing Miniconda (silent mode) to /opt/miniconda..."
sudo bash miniconda.sh -b -p /opt/miniconda
stop_spinner

# Initialize conda in current shell without requiring re-login
eval "$(/opt/miniconda/bin/conda shell.bash hook)"

start_spinner "Creating conda environment 'statsenv'..."
conda create -y -n statsenv python=3.9
stop_spinner

start_spinner "Activating conda environment 'statsenv'..."
conda activate statsenv
stop_spinner

#######################################
# 3) Install Python packages into conda env
#######################################
start_spinner "Installing required Python packages in 'statsenv'..."
# Use pip inside conda environment (the --break-system-packages is not really needed 
# inside conda, but included if absolutely required by your environment):
pip install \
    adafruit-circuitpython-ssd1306 \
    adafruit-python-shell \
    build \
    click \
    setuptools \
    gpiod \
    --upgrade --break-system-packages
stop_spinner

#######################################
# 4) Clone Adafruit's Raspberry-Pi-Installer-Scripts, run libgpiod.py
#######################################
# Change directory ownership so we can clone into /opt
start_spinner "Changing ownership of /opt to 'ylabs:ylabs'..."
sudo chown -R ylabs:ylabs /opt
stop_spinner

cd /opt
start_spinner "Cloning Adafruit's Raspberry-Pi-Installer-Scripts..."
git clone https://github.com/adafruit/Raspberry-Pi-Installer-Scripts.git || echo "Git repo already cloned."
stop_spinner

cd Raspberry-Pi-Installer-Scripts
start_spinner "Running libgpiod.py..."
sudo /opt/miniconda/envs/statsenv/bin/python libgpiod.py
stop_spinner

#######################################
# 5) Configure I2C modules and enable on boot
#######################################
start_spinner "Loading I2C kernel modules..."
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708
stop_spinner

start_spinner "Ensuring I2C modules load on boot..."
echo "i2c-dev"     | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
echo "i2c-bcm2708" | sudo tee /etc/modules-load.d/i2c-bcm2708.conf >/dev/null
stop_spinner

start_spinner "Enabling I2C via /boot/firmware/config.txt..."
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt; then
    echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt >/dev/null
fi
stop_spinner

#######################################
# 6) Install MicroK8s and enable on boot
#######################################
start_spinner "Installing MicroK8s (Snap)..."
sudo snap install microk8s --classic
stop_spinner

start_spinner "Adding user '$USER' to microk8s group..."
sudo usermod -aG microk8s "$USER"
stop_spinner

start_spinner "Waiting for MicroK8s to become ready..."
sudo microk8s status --wait-ready
stop_spinner

# MicroK8s typically autostarts via systemd once installed; no additional steps are usually needed.
# If you need to enable additional services:
#   sudo microk8s enable dns storage ingress etc.

#######################################
# 7) Create systemd service for stats.py
#######################################
echo "Creating systemd service for stats.py"

# Example uses the conda python interpreter from /opt/miniconda/envs/statsenv/bin/python
# Also note that /opt/raspberry-farm-scripts/stats.py should exist and be executable by root.

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

start_spinner "Reloading systemd daemon & enabling mystats.service..."
sudo systemctl daemon-reload
sudo systemctl enable mystats.service
stop_spinner

#######################################
# 8) Final message and reboot
#######################################
echo ""
echo "===================================================="
echo "Setup completed successfully."
echo "The system will now reboot in 5 seconds..."
echo "===================================================="
sleep 5
sudo reboot
