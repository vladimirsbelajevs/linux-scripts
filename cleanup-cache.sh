#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./cleanup-cache.sh [CACHE_DIRECTORY]

Lists immediate entries in the selected cache directory by size and lets you
remove entries by entering comma-separated numbers. The default directory is
${XDG_CACHE_HOME:-$HOME/.cache}.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi

if [ "${EUID}" -eq 0 ]; then
    echo "Do not run this script with sudo; it is intended for your user cache." >&2
    exit 1
fi

cache_dir="${1:-${XDG_CACHE_HOME:-${HOME}/.cache}}"
if [ ! -d "${cache_dir}" ]; then
    echo "Cache directory does not exist: ${cache_dir}" >&2
    exit 1
fi

cache_dir="$(realpath -- "${cache_dir}")"
if [ "${cache_dir}" = "/" ] || [ "${cache_dir}" = "${HOME}" ]; then
    echo "Refusing unsafe cache directory: ${cache_dir}" >&2
    exit 1
fi

for command_name in du find numfmt realpath sort; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    fi
done

declare -a cache_paths=()
declare -a cache_sizes=()

while IFS= read -r -d '' record; do
    size="${record%%$'\t'*}"
    path="${record#*$'\t'}"
    cache_sizes+=("${size}")
    cache_paths+=("${path}")
done < <(
    find "${cache_dir}" -mindepth 1 -maxdepth 1 -print0 \
        | du -sx --block-size=1 --null --files0-from=- 2>/dev/null \
        | sort -zrn
)

if [ "${#cache_paths[@]}" -eq 0 ]; then
    echo "No cache entries found in ${cache_dir}."
    exit 0
fi

human_size() {
    numfmt --to=iec-i --suffix=B "$1"
}

printf 'Cache entries in %s:\n\n' "${cache_dir}"
for index in "${!cache_paths[@]}"; do
    number=$((index + 1))
    display_name="$(basename -- "${cache_paths[index]}")"
    printf '%3d) %9s  %q\n' \
        "${number}" \
        "$(human_size "${cache_sizes[index]}")" \
        "${display_name}"
done

printf '\nEnter comma-separated numbers to clear, or q to quit: '
read -r selection
selection="${selection//[[:space:]]/}"

case "${selection}" in
    q|Q|"")
        echo "Nothing removed."
        exit 0
        ;;
esac

if ! [[ "${selection}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "Invalid selection. Use comma-separated numbers, for example: 1,3,5" >&2
    exit 2
fi

declare -a selected_indices=()
declare -A already_selected=()
IFS=',' read -r -a requested_numbers <<< "${selection}"

for number in "${requested_numbers[@]}"; do
    number_value=$((10#${number}))
    if [ "${number_value}" -lt 1 ] || [ "${number_value}" -gt "${#cache_paths[@]}" ]; then
        echo "Selection is out of range: ${number}" >&2
        exit 2
    fi

    index=$((number_value - 1))
    if [ -z "${already_selected[${index}]:-}" ]; then
        selected_indices+=("${index}")
        already_selected["${index}"]=1
    fi
done

selected_total=0
printf '\nSelected for permanent removal:\n'
for index in "${selected_indices[@]}"; do
    selected_total=$((selected_total + cache_sizes[index]))
    printf '  %9s  %q\n' \
        "$(human_size "${cache_sizes[index]}")" \
        "$(basename -- "${cache_paths[index]}")"
done
printf '  %9s  total\n' "$(human_size "${selected_total}")"

printf '\nClose applications using these caches. Type yes to remove them: '
read -r confirmation
if [ "${confirmation}" != "yes" ]; then
    echo "Nothing removed."
    exit 0
fi

for index in "${selected_indices[@]}"; do
    path="${cache_paths[index]}"

    # Every candidate came from an immediate child of the resolved cache root.
    # Check again immediately before deletion to guard against accidental edits.
    if [ "$(dirname -- "${path}")" != "${cache_dir}" ]; then
        echo "Refusing path outside cache directory: ${path}" >&2
        exit 1
    fi

    rm -rf --one-file-system -- "${path}"
done

remaining_size="$(du -sx --block-size=1 "${cache_dir}" 2>/dev/null | cut -f1)"
printf '\nRemoved selected entries (previously %s).\n' "$(human_size "${selected_total}")"
printf 'Current cache size: %s\n' "$(human_size "${remaining_size}")"
