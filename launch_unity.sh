#!/usr/bin/env bash
set -euo pipefail

# Allow per-launch overrides while retaining the scaling fix by default.
export GDK_SCALE="${GDK_SCALE:-2}"
export GDK_DPI_SCALE="${GDK_DPI_SCALE:-0.5}"

# Uncomment this if Wayland causes issues.
# export GDK_BACKEND=x11

UNITY_CLI="${UNITY_CLI:-$(command -v unity || true)}"
if [[ -z "$UNITY_CLI" ]]; then
    printf 'Error: Unity CLI was not found on PATH.\n' >&2
    exit 127
fi

# Match `unity open`: with no project argument, open the current directory.
if (( $# == 0 )); then
    set -- .
fi

# UNITY_EDITOR_ARGS can override the default Editor arguments when necessary.
exec "$UNITY_CLI" open "$@" --args "${UNITY_EDITOR_ARGS:--force-vulkan}"
