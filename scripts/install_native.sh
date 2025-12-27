#!/bin/bash

echo "Installing Docker, Kodi and Samba natively..."

# Update package list
sudo apt update

# Install Docker if missing
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt install -y docker.io docker-compose-v2
    sudo usermod -aG docker $USER
    echo "Docker installed. You might need to log out and log back in for group changes to take effect."
fi

# Install Kodi
echo "Installing Kodi..."
sudo apt install -y kodi

# Install Samba
echo "Installing Samba..."
sudo apt install -y samba samba-common-bin

# Install curl if missing
if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    sudo apt install -y curl
fi

# Install jq for JSON processing
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt install -y jq
fi

# Elementum Setup (Kodi Plugin)
echo "Preparing Elementum repository for Kodi..."
# Using the official Elementum site download link for the repository
ELEMENTUM_REPO_URL="https://elementum.surge.sh/repository.elementumorg-0.0.7.zip"
mkdir -p ~/Downloads
# Try downloading from the official site first, then fallback to a manual message
if wget -O ~/Downloads/repository.elementum.zip "$ELEMENTUM_REPO_URL"; then
    echo "Elementum repository downloaded successfully."
else
    echo "Warning: Could not download Elementum repository automatically."
    echo "Please download 'All-in-one (repository.elementumorg-0.0.7.zip)' manually from https://elementum.surge.sh/"
fi

echo "Installation complete."
echo "-------------------------------------------------------"
echo "NEXT STEPS:"
echo "1. Open Kodi."
echo "2. Go to Add-ons -> Install from zip file."
echo "3. Select ~/Downloads/repository.elementum.zip."
echo "4. Install Elementum, Elementum Burst, and Context Menu from the Elementum Repository."
echo "5. To configure Samba, edit /etc/samba/smb.conf"
echo "-------------------------------------------------------"
