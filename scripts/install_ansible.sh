#!/bin/bash

set -euo pipefail

# Define logging function
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

log "Starting Ansible installation..."

# Update package lists
log "Updating package lists..."
sudo apt update -y || {
  log "Failed to update package lists. Exiting."
  exit 1
}

# Install prerequisites
log "Installing prerequisites..."
sudo apt install -y software-properties-common || {
  log "Failed to install prerequisites. Exiting."
  exit 1
}

# Add Ansible PPA
log "Adding Ansible PPA repository..."
sudo add-apt-repository --yes --update ppa:ansible/ansible || {
  log "Failed to add Ansible PPA. Exiting."
  exit 1
}

# Install Ansible
log "Installing Ansible..."
sudo apt install -y ansible || {
  log "Failed to install Ansible. Exiting."
  exit 1
}

# Verify Ansible installation
log "Verifying Ansible installation..."
if command -v ansible &> /dev/null; then
  log "Ansible successfully installed. Version: $(ansible --version | head -n 1)"
else
  log "Ansible installation failed. Please check logs."
  exit 1
fi

log "Ansible installation completed successfully."
