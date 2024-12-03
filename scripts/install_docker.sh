#!/bin/bash

set -euo pipefail

# Define logging function
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

log "Starting Docker installation..."

# Uninstall conflicting packages
log "Removing conflicting packages..."
conflicting_packages=(
  docker.io docker-doc docker-compose docker-compose-v2
  podman-docker containerd runc
)
for pkg in "${conflicting_packages[@]}"; do
  if dpkg -l | grep -q "^ii  $pkg"; then
    log "Removing $pkg..."
    sudo apt-get remove -y "$pkg" || log "Failed to remove $pkg, continuing..."
  fi
done

# Update package lists
log "Updating package lists..."
sudo apt-get update -y

# Install prerequisites
log "Installing prerequisites..."
sudo apt-get install -y ca-certificates curl || {
  log "Failed to install prerequisites. Exiting."
  exit 1
}

# Add Docker's official GPG key
log "Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
log "Adding Docker repository..."
docker_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable"
echo "$docker_repo" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package lists again to include Docker packages
log "Updating package lists with Docker repository..."
sudo apt-get update -y

# Install Docker packages
log "Installing Docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
  log "Failed to install Docker packages. Exiting."
  exit 1
}

# Verify Docker installation
log "Verifying Docker installation..."
if command -v docker &> /dev/null; then
  log "Docker successfully installed. Version: $(docker --version)"
else
  log "Docker installation failed. Please check logs."
  exit 1
fi

log "Docker installation completed successfully."