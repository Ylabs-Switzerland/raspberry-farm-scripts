### A repository for consolidating Bash scripts necessary to accelerate deployments in the Raspberry Pi farm.

#### Scripts:

- **display_dependency_installer.sh:** Installs everything necessary to set up the status OLED display. During the installation, you will need to press enter a few times to approve restarting the affected services. The script also creates a systemctl service responsible for launching the stats.py script, which displays the status on the OLED display.
