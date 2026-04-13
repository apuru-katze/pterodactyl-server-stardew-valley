#!/bin/bash

# Enable strict error handling to exit immediately on failure
echo "Tested up to Stardew Valley 1.6.15"
set -Eeuo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR

# Set Stardew Valley App ID
SRCDS_APPID=${SRCDS_APPID:-413150}  # Gunakan env var, atau default ke 413150

# Install Steam Immediately, in case of STEAM_AUTH usage
cd /tmp
mkdir -p /mnt/server/steamcmd

if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
    echo -e "Cannot use anonymous login for games that require a license. Please set a user and try again."
    exit 1
else
    echo -e "user set to ${STEAM_USER}"
fi

# SteamCMD fails otherwise for some reason, even running as root.
# This is changed at the end of the install process anyways.
chown -R root:root /mnt
export HOME=/mnt/server

## Install dependencies (must be before SteamCMD - needs lib32gcc-s1 for 32-bit steamcmd)
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  unzip \
  lib32gcc-s1 \
  mono-runtime \
  xvfb \
  cpulimit
apt-get clean
rm -rf /var/lib/apt/lists/*

## download and install steamcmd
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
cd /mnt/server/steamcmd

## install game using steamcmd
STEAMCMD_LOG=$(mktemp)

./steamcmd.sh \
  +force_install_dir /mnt/server \
  +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" \
  +app_update "${SRCDS_APPID}" validate \
  +quit | tee "$STEAMCMD_LOG"

# Hard fail on Steam Guard / login issues
if grep -Eqi "Two-factor code mismatch" "$STEAMCMD_LOG"; then
    echo "[ERROR] SteamCMD login failed (Steam Guard / credentials issue)"
    exit 1
fi

## set up 32 bit libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v /mnt/server/steamcmd/linux32/steamclient.so /mnt/server/.steam/sdk32/steamclient.so

## set up 64 bit libraries
mkdir -p /mnt/server/.steam/sdk64
cp -v /mnt/server/steamcmd/linux64/steamclient.so /mnt/server/.steam/sdk64/steamclient.so

## Game specific setup.
cd /mnt/server/
mkdir -p ./.config
mkdir -p ./.config/i3
mkdir -p ./.config/StardewValley
mkdir -p ./nexus
mkdir -p ./storage
mkdir -p ./logs

## Stardew Valley specific setup.
wget https://github.com/Pathoschild/SMAPI/releases/download/4.5.2/SMAPI-4.5.2-installer.zip -qO ./storage/nexus.zip
unzip -o ./storage/nexus.zip -d ./nexus/
/bin/bash -c "cd '/mnt/server/nexus/SMAPI 4.5.2 installer/internal/linux/' && printf '2\n1\n1\n\n' | ./SMAPI.Installer"
wget https://raw.githubusercontent.com/paytah232/pterodactyl-server-stardew-valley/main/server/stardew_valley_server.config -qO ./.config/StardewValley/startup_preferences
wget https://github.com/paytah232/pterodactyl-server-stardew-valley/raw/main/mods/AlwaysOnServer.zip -qO ./storage/AlwaysOnServer.zip
wget https://github.com/paytah232/pterodactyl-server-stardew-valley/raw/main/mods/UnlimitedPlayers.zip -qO ./storage/UnlimitedPlayers.zip
wget https://github.com/paytah232/pterodactyl-server-stardew-valley/raw/main/mods/AutoLoadGame.zip -qO ./storage/AutoLoadGame.zip
wget https://github.com/paytah232/pterodactyl-server-stardew-valley/raw/main/mods/StardewPortChanger.zip -qO ./storage/StardewPortChanger.zip
wget https://github.com/paytah232/pterodactyl-server-stardew-valley/raw/main/mods/AutoHideHost.zip -qO ./storage/AutoHideHost.zip
unzip -o ./storage/AlwaysOnServer.zip -d ./Mods
unzip -o ./storage/UnlimitedPlayers.zip -d ./Mods
unzip -o ./storage/AutoLoadGame.zip -d ./Mods
unzip -o ./storage/StardewPortChanger.zip -d ./Mods
unzip -o ./storage/AutoHideHost.zip -d ./Mods
wget https://raw.githubusercontent.com/paytah232/pterodactyl-server-stardew-valley/main/mods/AutoHideHost.json -qO ./Mods/AutoHideHost/config.json
wget https://raw.githubusercontent.com/paytah232/pterodactyl-server-stardew-valley/main/mods/AutoLoadGame.json -qO ./Mods/AutoLoadGame/config.json
wget https://raw.githubusercontent.com/paytah232/pterodactyl-server-stardew-valley/main/mods/StardewPortChanger.json -qO ./Mods/StardewPortChanger/config.json

# download stardew-valley-server.sh
wget https://raw.githubusercontent.com/apuru-katze/pterodactyl-server-stardew-valley/main/server/stardew-valley-server.sh -qO ./stardew-valley-server.sh
chmod +x ./stardew-valley-server.sh

# Rename the StardewValley executable to fix server starting conflicts
mv StardewValley StardewValley.exe.bak
echo 'Stardew Valley Installation complete.\nOpen in a VNC view to first create the CO-OP game.\nThen, restart the server, log back in and make sure it loaded the save again.'
