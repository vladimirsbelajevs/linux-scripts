#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./cleanup-docker-storage-migration.sh [--yes]

After a successful migration and reboot, verifies that Docker and containerd
use their recorded destination directories, then removes the retained source
directories. Migration state is read from /etc/docker-storage-migration.json.
EOF
}

assume_yes=false
case "${1:-}" in
    "") ;;
    --yes)
        assume_yes=true
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [ "$#" -ne 0 ]; then
    usage >&2
    exit 2
fi

if [ "${EUID}" -ne 0 ]; then
    if [ "${assume_yes}" = true ]; then
        exec sudo -- "$0" --yes
    else
        exec sudo -- "$0"
    fi
fi

for command_name in docker findmnt python3 realpath systemctl; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    fi
done

migration_state="/etc/docker-storage-migration.json"
if [ ! -f "${migration_state}" ]; then
    echo "Migration state not found: ${migration_state}" >&2
    echo "Run move-docker-storage.sh before using this cleanup script." >&2
    exit 1
fi

python3 - "${migration_state}" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
required = {
    "docker_source",
    "docker_target",
    "containerd_source",
    "containerd_target",
    "migration_boot_id",
}
missing = required.difference(state)
if missing:
    raise SystemExit(f"Migration state is missing fields: {', '.join(sorted(missing))}")
for key in required:
    if not isinstance(state[key], str) or not state[key]:
        raise SystemExit(f"Migration state field is invalid: {key}")
PY

mapfile -t state_values < <(
    python3 - "${migration_state}" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in (
    "docker_source",
    "docker_target",
    "containerd_source",
    "containerd_target",
    "migration_boot_id",
):
    print(state[key])
PY
)

docker_source="$(realpath -m -- "${state_values[0]}")"
docker_target="$(realpath -m -- "${state_values[1]}")"
containerd_source="$(realpath -m -- "${state_values[2]}")"
containerd_target="$(realpath -m -- "${state_values[3]}")"
migration_boot_id="${state_values[4]}"
current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"

if [ "${migration_boot_id}" = "${current_boot_id}" ]; then
    echo "Cleanup is blocked until the machine has rebooted after migration." >&2
    exit 1
fi

for path in \
    "${docker_source}" \
    "${docker_target}" \
    "${containerd_source}" \
    "${containerd_target}"; do
    if [[ "${path}" != /* ]] || [ "${path}" = "/" ]; then
        echo "Unsafe path in migration state: ${path}" >&2
        exit 1
    fi
done

if { [ "${docker_source}" != "${docker_target}" ] &&
        [[ "${docker_target}/" == "${docker_source}/"* ]]; } ||
    { [ "${containerd_source}" != "${containerd_target}" ] &&
        [[ "${containerd_target}/" == "${containerd_source}/"* ]]; }; then
    echo "Cleanup refused because a destination is inside a source directory." >&2
    exit 1
fi

actual_docker_root="$(realpath -m -- "$(docker info --format '{{.DockerRootDir}}')")"
if [ "${actual_docker_root}" != "${docker_target}" ]; then
    echo "Docker is not using the recorded destination." >&2
    echo "Expected: ${docker_target}" >&2
    echo "Actual:   ${actual_docker_root}" >&2
    exit 1
fi

containerd_pid="$(systemctl show containerd.service --property MainPID --value)"
if ! [[ "${containerd_pid}" =~ ^[1-9][0-9]*$ ]] ||
    [ ! -r "/proc/${containerd_pid}/cmdline" ]; then
    echo "containerd must be running so its data root can be verified." >&2
    exit 1
fi

actual_containerd_root="/var/lib/containerd"
mapfile -d '' containerd_command < "/proc/${containerd_pid}/cmdline"
for ((index = 0; index < ${#containerd_command[@]}; index++)); do
    case "${containerd_command[index]}" in
        --root)
            if ((index + 1 < ${#containerd_command[@]})); then
                actual_containerd_root="${containerd_command[index + 1]}"
            fi
            ;;
        --root=*)
            actual_containerd_root="${containerd_command[index]#--root=}"
            ;;
    esac
done
actual_containerd_root="$(realpath -m -- "${actual_containerd_root}")"

if [ "${actual_containerd_root}" != "${containerd_target}" ]; then
    echo "containerd is not using the recorded destination." >&2
    echo "Expected: ${containerd_target}" >&2
    echo "Actual:   ${actual_containerd_root}" >&2
    exit 1
fi

findmnt -T "${docker_target}" -o TARGET,SOURCE,FSTYPE,OPTIONS
findmnt -T "${containerd_target}" -o TARGET,SOURCE,FSTYPE,OPTIONS

printf '\nVerified active destinations:\n'
printf '  Docker:     %s\n' "${docker_target}"
printf '  containerd: %s\n' "${containerd_target}"
printf '\nSource directories to remove:\n'
if [ "${docker_source}" != "${docker_target}" ]; then
    printf '  %s\n' "${docker_source}"
fi
if [ "${containerd_source}" != "${containerd_target}" ]; then
    printf '  %s\n' "${containerd_source}"
fi

if [ "${docker_source}" = "${docker_target}" ] &&
    [ "${containerd_source}" = "${containerd_target}" ]; then
    echo "There are no old source directories to remove."
    rm -f -- "${migration_state}"
    exit 0
fi

if [ "${assume_yes}" != true ]; then
    printf '\nThis permanently deletes the listed source directories. Continue? [y/N] '
    read -r reply
    case "${reply}" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

services_stopped=false
on_error() {
    exit_code=$?
    echo "Cleanup failed; attempting to restart containerd and Docker." >&2
    if [ "${services_stopped}" = true ]; then
        systemctl start containerd.service || true
        systemctl start docker.service || true
    fi
    exit "${exit_code}"
}
trap on_error ERR

systemctl stop docker.service docker.socket
systemctl stop containerd.service
services_stopped=true

unmount_descendants() {
    local root="$1"
    local mount_target

    [ -e "${root}" ] || return 0
    while IFS= read -r mount_target; do
        if [[ "${mount_target}" == "${root}/"* ]]; then
            umount -- "${mount_target}"
        fi
    done < <(findmnt -Rnr -o TARGET --target "${root}" | tac)
}

remove_source() {
    local source="$1"
    local target="$2"

    if [ "${source}" = "${target}" ] || [ ! -e "${source}" ]; then
        return
    fi

    unmount_descendants "${source}"
    rm -rf --one-file-system -- "${source}"
}

remove_source "${docker_source}" "${docker_target}"
remove_source "${containerd_source}" "${containerd_target}"

systemctl start containerd.service
systemctl start docker.service
services_stopped=false

if [ "$(realpath -m -- "$(docker info --format '{{.DockerRootDir}}')")" != "${docker_target}" ]; then
    echo "Docker restarted with an unexpected data root." >&2
    exit 1
fi

rm -f -- "${migration_state}"
trap - ERR

echo "Old Docker and containerd source directories were removed successfully."
