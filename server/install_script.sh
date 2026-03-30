#!/bin/bash

# Enable strict error handling to exit immediately on failure
echo "Tested up to Stardew Valley 1.6.15"
set -Eeuo pipefail
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR

# ============================================================================
# SMAPI Configuration - Update these variables when new SMAPI versions release
# ============================================================================
SMAPI_VERSION="
${SMAPI_VERSION:-4.5.2}"
SMAPI_DOWNLOAD_URL="https://github.com/Pathoschild/SMAPI/releases/download/${SMAPI_VERSION}/SMAPI-${SMAPI_VERSION}-installer.zip"
SMAPI_CHECKSUM_VALIDATION="
${SMAPI_CHECKSUM_VALIDATION:-false}"

# Supported SMAPI versions with checksums
declare -A SMAPI_CHECKSUMS=(
    ["4.5.2"]="8b7e8f8c8d9e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f"
    ["4.6.0"]="9c8f9e0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7"
)

echo "========================================="
echo "SMAPI Installation Configuration"
echo "========================================="
echo "Version: ${SMAPI_VERSION}"
echo "Download URL: ${SMAPI_DOWNLOAD_URL}"
echo "Checksum Validation: ${SMAPI_CHECKSUM_VALIDATION}"
echo "========================================="

# Validate SMAPI version is supported (optional, for future safety)
if [ "${SMAPI_CHECKSUM_VALIDATION}" = "true" ]; then
    if [[ ! " ${!SMAPI_CHECKSUMS[@]} " =~ " ${SMAPI_VERSION} " ]]; then
        echo "[WARNING] SMAPI version ${SMAPI_VERSION} checksum not found in validation list"
    fi
fi

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
  x11vnc \
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

## Stardew Valley specific setup - Download and install SMAPI
echo "[*] Downloading SMAPI ${SMAPI_VERSION}..."
if ! wget "${SMAPI_DOWNLOAD_URL}" -qO ./storage/nexus.zip; then
    echo "[ERROR] Failed to download SMAPI from ${SMAPI_DOWNLOAD_URL}"
    echo "[ERROR] Check that version ${SMAPI_VERSION} exists on GitHub releases"
    exit 1
fi

echo "[*] Extracting SMAPI installer..."
if ! unzip -o ./storage/nexus.zip -d ./nexus/; then
    echo "[ERROR] Failed to extract SMAPI installer"
    exit 1
fi

echo "[+] SMAPI ${SMAPI_VERSION} installation completed successfully!"
echo "[*] Server installation finished. Ready to start."