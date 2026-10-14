#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: uninstall_proton_ge.sh [--dry-run]

Remove all GE-Proton versions from native Steam's
~/.steam/steam/compatibilitytools.d directory, after confirmation.
Game files, saves, prefixes, and other compatibility tools are left alone.

  --dry-run   List versions that would be removed without deleting anything.
  -h, --help  Show this help.

Run as your normal user, without sudo. Close Steam before uninstalling.
EOF
}

dry_run=false
case "${1:-}" in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    '') ;;
    *) usage >&2; exit 1 ;;
esac
if (( $# > 1 )); then
    usage >&2
    exit 1
fi

steam_dir="$HOME/.steam/steam"
tools_dir="$steam_dir/compatibilitytools.d"

if [[ ! -d "$tools_dir" ]]; then
    echo "No native Steam compatibility tools directory found at $tools_dir."
    exit 0
fi

shopt -s nullglob
versions=()
for path in "$tools_dir"/GE-Proton[0-9]*; do
    if [[ -d "$path" ]]; then
        versions+=("$path")
    fi
done

if (( ${#versions[@]} == 0 )); then
    echo "No GE-Proton versions found in $tools_dir."
    exit 0
fi

echo "GE-Proton versions to remove from $tools_dir:"
for path in "${versions[@]}"; do
    printf '  %s\n' "${path##*/}"
done

if [[ "$dry_run" == true ]]; then
    echo "Dry run: nothing was removed."
    exit 0
fi

echo "Close Steam before continuing."
if ! read -r -p 'Remove all listed GE-Proton versions? [y/N] ' answer; then
    echo "Cancelled."
    exit 0
fi
case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
esac

for path in "${versions[@]}"; do
    printf 'Removing %s...\n' "${path##*/}"
    # No trailing slash: if a version is a symlink, remove only the link.
    rm -rf -- "$path"
done

echo "Done. Restart Steam and select another compatibility tool for affected games."
