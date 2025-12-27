#!/bin/bash

echo "Stopping and removing all Media Center containers..."

# We use the 'full' profile to ensure we target ALL services, 
# regardless of which profile was used to start them.
# 'down' stops and removes containers, networks, and default volumes (not named volumes).
sudo docker compose --profile full down

echo "Shutdown complete."
