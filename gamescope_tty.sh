#!/usr/bin/env bash
set -euo pipefail

MANGOAPP="${MANGOAPP:-0}"

MODE="${1:-}"

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 {TV|TV_60|Deck|PC}"
  exit 1
fi

# Normalize case so tv/TV/Tv all work
MODE="$(tr '[:lower:]' '[:upper:]' <<< "$MODE")"

# Performance tweaks (direct)
# export DXVK_MAX_FRAME_LATENCY=1
export STEAM_DISABLE_DESKTOP_GL=1

# Performance tweaks (used by ~/Scripts/steam_gamescope.sh)
export HDR=1
export WAYLAND=0


START_SUNSHINE=0
WIDTH=3840
HEIGHT=2160
INTERNAL_WIDTH=3840
INTERNAL_HEIGHT=2160
ADDITIONAL_ARGS=()

# Output Target (Your DP-1)
TARGET_OUT="DP-1"

case "$MODE" in
  TV)
    START_SUNSHINE=1
    REFRESH=120
    ADDITIONAL_ARGS+=(-S fill) # Default to fill for 4K modes
    # ADDITIONAL_ARGS+=(--immediate-flips) #bypasses compositor pacing
    ADDITIONAL_ARGS+=(--hdr-itm-target-nits 700)
    ADDITIONAL_ARGS+=(--nested-refresh 120)
    ;;
  TV_60)
    START_SUNSHINE=1
    REFRESH=60
    ADDITIONAL_ARGS+=(-S fill) # Default to fill for 4K modes
    # ADDITIONAL_ARGS+=(--immediate-flips) #bypasses compositor pacing
    ADDITIONAL_ARGS+=(--hdr-itm-target-nits 700)
    ADDITIONAL_ARGS+=(--nested-refresh 60)
    ;;
  PC)
    START_SUNSHINE=0
    #ADDITIONAL_ARGS+=(-S fill) # Default to fill for 4K modes
    ADDITIONAL_ARGS+=(--hdr-itm-target-nits 1200)
    ADDITIONAL_ARGS+=(--nested-refresh 160)
    ADDITIONAL_ARGS+=(--framerate-limit 160)
    ADDITIONAL_ARGS+=(--immediate-flips)
    ADDITIONAL_ARGS+=(--adaptive-sync)
    ;;
  DECK)
    # DECK mode does not work properly in embedded gamescope, it's defaulting the resolution to 4k60 for some reason...
    START_SUNSHINE=1
    WIDTH=1920
    HEIGHT=1080
    INTERNAL_WIDTH=1280
    INTERNAL_HEIGHT=800
    ADDITIONAL_ARGS+=(-S fit) # Keep 16:10 aspect ratio on 16:9 screen
    # ADDITIONAL_ARGS+=(--immediate-flips) #bypasses compositor pacing
    ADDITIONAL_ARGS+=(--hdr-itm-target-nits 1000)
    ADDITIONAL_ARGS+=(--nested-refresh 100)
    ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Usage: $0 {TV|TV_60|Deck|PC}"
    exit 1
    ;;
esac

if [[ "$MANGOAPP" -eq 1 ]]; then
  ADDITIONAL_ARGS+=(--mangoapp)
fi

SUNSHINE_PID=""

cleanup() {
  if [[ -n "$SUNSHINE_PID" ]] && kill -0 "$SUNSHINE_PID" 2>/dev/null; then
    kill "$SUNSHINE_PID" || true
  fi
}

trap cleanup EXIT INT TERM

if [[ "$START_SUNSHINE" -eq 1 ]]; then
  sunshine &
  SUNSHINE_PID=$!
  # Optional: give Sunshine a moment to initialize
  sleep 4
fi

# Start Gamescope (embedded mode for TTY)
# --framerate-limit "$REFRESH" \
#   --force-grab-cursor \ his works only for nested mode, useless for embedded
#   -o "$REFRESH" \ This works only for nested mode, useless for embedded
# --mangoapp Mango for the embedded gamescope and gamescope in general
#  --hdr-itm-enabled tone-mapping-sdr to HDR

#  --hdr-itm-enabled \
#   --hdr-sdr-content-nits 203 \ (Default 400)
#   --hdr-itm-sdr-nits 100 \ (Default 100)
# --hdr-itm-target-nits 700 \

  # --scaler auto \
  # --filter fsr \
  # --sharpness 0 \

gamescope -e \
  --prefer-output "$TARGET_OUT" \
  --backend drm \
  --rt \
  --hdr-enabled \
  --hdr-itm-enabled \
  --hdr-sdr-content-nits 203 \
  --hdr-itm-sdr-nits 100 \
  --sdr-gamut-wideness 0 \
  --nested-width $INTERNAL_WIDTH --nested-height $INTERNAL_HEIGHT \
  --output-width $WIDTH --output-height $HEIGHT \
  "${ADDITIONAL_ARGS[@]}" \
  -- steam -gamepadui -steamos3
