#!/usr/bin/env bash

# ===== CONFIG =====
UNITY_PATH="/home/vladimirs/Unity/Hub/Editor/6000.3.9f1/Editor/Unity"
SCALE="2"          # 1, 1.5, 2 etc
DPI_SCALE="0.5"      # usually keep at 1 for sharp text

# ===== ENVIRONMENT =====
export GDK_SCALE="$SCALE"
export GDK_DPI_SCALE="$DPI_SCALE"

# Uncomment this if Wayland causes issues
# export GDK_BACKEND=x11

# ===== LAUNCH =====
exec "$UNITY_PATH" -force-vulkan "$@"
