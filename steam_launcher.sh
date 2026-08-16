#!/usr/bin/env bash
set -euo pipefail

HDR="${HDR:-1}"
PROTON_DLSS_UPGRADE="${PROTON_DLSS_UPGRADE:-1}"
WAYLAND="${WAYLAND:-1}"
CLEAR_LD_PRELOAD="${CLEAR_LD_PRELOAD:-0}"
MANGO="${MANGO:-0}"

# Optional pass-through env vars
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}"

log_settings() {
  logger -t steam_launcher \
    "Settings: HDR=$HDR PROTON_DLSS_UPGRADE=$PROTON_DLSS_UPGRADE WAYLAND=$WAYLAND CLEAR_LD_PRELOAD=$CLEAR_LD_PRELOAD MANGOHUD=$MANGO WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-<empty>}"
}

env_vars=()

if [[ "$CLEAR_LD_PRELOAD" == "1" ]]; then
  env_vars+=("LD_PRELOAD=")
fi

if [[ "$WAYLAND" == "1" ]]; then
  env_vars+=("PROTON_ENABLE_WAYLAND=1")
  env_vars+=("PROTON_WAYLAND_MONITOR=DP-3")
fi

if [[ "$HDR" == "1" ]]; then
  env_vars+=("PROTON_ENABLE_HDR=1")
fi

if [[ "$PROTON_DLSS_UPGRADE" == "1" ]]; then
  env_vars+=("PROTON_DLSS_UPGRADE=1")
fi

if [[ -n "$WINEDLLOVERRIDES" ]]; then
  env_vars+=("WINEDLLOVERRIDES=$WINEDLLOVERRIDES")
fi

if [[ "$MANGO" == "1" ]]; then
  env_vars+=("MANGOHUD=1")
fi

log_settings

log_cmd=(env "${env_vars[@]}" game-performance "$@")

printf -v log_line '%q ' "${log_cmd[@]}"
logger -t steam_launcher "Launching: $log_line"

exec env "${env_vars[@]}" game-performance "$@"
