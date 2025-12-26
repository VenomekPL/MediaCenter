#!/bin/bash

echo "Installing Kodi and Samba natively..."

# Update package list
sudo apt update

# Install Kodi
echo "Installing Kodi..."
sudo apt install -y kodi

# Install Samba
echo "Installing Samba..."
sudo apt install -y samba samba-common-bin

# Elementum Setup (Kodi Plugin)
echo "Preparing Elementum repository for Kodi..."
ELEMENTUM_REPO_URL="https://github.com/elgatito/repository.elementum/releases/download/v0.1.87/repository.elementum-0.1.87.zip"
mkdir -p ~/Downloads
wget -O ~/Downloads/repository.elementum.zip "$ELEMENTUM_REPO_URL"

echo "Installation complete."
echo "-------------------------------------------------------"
echo "NEXT STEPS:"
echo "1. Open Kodi."
echo "2. Go to Add-ons -> Install from zip file."
echo "3. Select ~/Downloads/repository.elementum.zip."
echo "4. Install Elementum, Elementum Burst, and Context Menu from the Elementum Repository."
echo "5. To configure Samba, edit /etc/samba/smb.conf"
echo "-------------------------------------------------------"
