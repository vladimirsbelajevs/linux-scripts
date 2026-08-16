#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./move-docker-storage.sh [--yes] DOCKER_DATA_DIR CONTAINERD_DATA_DIR

Stops Docker and containerd, copies their current data into the requested
absolute directories, configures both services to use those directories, and
starts the services again.

The source directories are retained for rollback. Reboot and verify Docker
before removing them manually.

Example:
  ./move-docker-storage.sh \
    /mnt/Samsung_SSD/docker-data \
    /mnt/Samsung_SSD/containerd-data
EOF
}

assume_yes=false
if [ "${1:-}" = "--yes" ]; then
    assume_yes=true
    shift
fi

if [ "$#" -ne 2 ]; then
    usage >&2
    exit 2
fi

if [ "${EUID}" -ne 0 ]; then
    if [ "${assume_yes}" = true ]; then
        exec sudo -- "$0" --yes "$@"
    else
        exec sudo -- "$0" "$@"
    fi
fi

for command_name in docker findmnt python3 realpath rsync systemctl; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is missing: ${command_name}" >&2
        exit 1
    fi
done

docker_target="$(realpath -m -- "$1")"
containerd_target="$(realpath -m -- "$2")"

for target in "${docker_target}" "${containerd_target}"; do
    if [[ "${target}" != /* ]] || [ "${target}" = "/" ]; then
        echo "Storage directories must be absolute paths other than root: ${target}" >&2
        exit 1
    fi
    if [[ "${target}" =~ [[:space:]] ]]; then
        echo "Storage directory paths must not contain whitespace: ${target}" >&2
        exit 1
    fi
done

if [ "${docker_target}" = "${containerd_target}" ]; then
    echo "Docker and containerd must use different data directories." >&2
    exit 1
fi

if [[ "${docker_target}/" == "${containerd_target}/"* ]] ||
    [[ "${containerd_target}/" == "${docker_target}/"* ]]; then
    echo "Docker and containerd data directories must not contain one another." >&2
    exit 1
fi

docker_source="$(docker info --format '{{.DockerRootDir}}')"
containerd_source="/var/lib/containerd"
containerd_pid="$(systemctl show containerd.service --property MainPID --value)"

if ! [[ "${containerd_pid}" =~ ^[1-9][0-9]*$ ]] ||
    [ ! -r "/proc/${containerd_pid}/cmdline" ]; then
    echo "containerd must be running so its current data root can be detected." >&2
    exit 1
fi

mapfile -d '' containerd_command < "/proc/${containerd_pid}/cmdline"
containerd_binary="${containerd_command[0]:-/usr/bin/containerd}"
for ((index = 0; index < ${#containerd_command[@]}; index++)); do
    case "${containerd_command[index]}" in
        --root)
            if ((index + 1 < ${#containerd_command[@]})); then
                containerd_source="${containerd_command[index + 1]}"
            fi
            ;;
        --root=*)
            containerd_source="${containerd_command[index]#--root=}"
            ;;
    esac
done

containerd_source="$(realpath -m -- "${containerd_source}")"
docker_source="$(realpath -m -- "${docker_source}")"

if { [ "${docker_source}" != "${docker_target}" ] &&
        { [[ "${docker_target}/" == "${docker_source}/"* ]] ||
          [[ "${docker_source}/" == "${docker_target}/"* ]]; }; } ||
    { [ "${containerd_source}" != "${containerd_target}" ] &&
        { [[ "${containerd_target}/" == "${containerd_source}/"* ]] ||
          [[ "${containerd_source}/" == "${containerd_target}/"* ]]; }; }; then
    echo "A destination must not contain, or be contained by, its source." >&2
    exit 1
fi

if [ ! -d "${docker_source}" ]; then
    echo "Current Docker data directory does not exist: ${docker_source}" >&2
    exit 1
fi
if [ ! -d "${containerd_source}" ]; then
    echo "Current containerd data directory does not exist: ${containerd_source}" >&2
    exit 1
fi

if [ "${docker_source}" = "${docker_target}" ] &&
    [ "${containerd_source}" = "${containerd_target}" ]; then
    echo "Docker and containerd already use the requested directories."
    exit 0
fi

printf 'Docker:     %s -> %s\n' "${docker_source}" "${docker_target}"
printf 'containerd: %s -> %s\n' "${containerd_source}" "${containerd_target}"
printf '\nDestination filesystems:\n'
findmnt -T "${docker_target}" -o TARGET,SOURCE,FSTYPE,OPTIONS
findmnt -T "${containerd_target}" -o TARGET,SOURCE,FSTYPE,OPTIONS

if [ "${assume_yes}" != true ]; then
    printf '\nDocker containers will be stopped during the migration. Continue? [y/N] '
    read -r reply
    case "${reply}" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

services_stopped=false
configuration_switched=false
on_error() {
    exit_code=$?
    echo "Migration failed." >&2
    if [ "${services_stopped}" = true ] && [ "${configuration_switched}" = false ]; then
        echo "Restarting services with their original configuration." >&2
        systemctl start containerd.service || true
        systemctl start docker.service || true
    else
        echo "Inspect with: journalctl -u containerd.service -u docker.service -n 100" >&2
    fi
    exit "${exit_code}"
}
trap on_error ERR

systemctl stop docker.service docker.socket
systemctl stop containerd.service
services_stopped=true

# Remove stale runtime mounts below a data directory, but never unmount the data
# directory itself when it is a dedicated filesystem.
unmount_descendants() {
    local root="$1"
    local mount_target

    while IFS= read -r mount_target; do
        if [[ "${mount_target}" == "${root}/"* ]]; then
            umount -- "${mount_target}"
        fi
    done < <(findmnt -Rnr -o TARGET --target "${root}" | tac)
}

unmount_descendants "${docker_source}"
unmount_descendants "${containerd_source}"

copy_storage() {
    local source="$1"
    local target="$2"

    if [ "${source}" = "${target}" ]; then
        return
    fi

    mkdir -p -- "${target}"
    chown --reference="${source}" -- "${target}"
    chmod --reference="${source}" -- "${target}"
    rsync -aHAXx --numeric-ids --info=progress2 "${source}/" "${target}/"
}

copy_storage "${docker_source}" "${docker_target}"
copy_storage "${containerd_source}" "${containerd_target}"

backup_suffix="$(date +%Y%m%d-%H%M%S)"
daemon_config="/etc/docker/daemon.json"
mkdir -p /etc/docker
if [ -f "${daemon_config}" ]; then
    cp -a -- "${daemon_config}" "${daemon_config}.${backup_suffix}.bak"
fi

python3 - "${daemon_config}" "${docker_target}" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
data_root = sys.argv[2]

if config_path.exists():
    with config_path.open(encoding="utf-8") as config_file:
        config = json.load(config_file)
else:
    config = {}

config["data-root"] = data_root
with config_path.open("w", encoding="utf-8") as config_file:
    json.dump(config, config_file, indent=2)
    config_file.write("\n")
PY

mkdir -p /etc/systemd/system/docker.service.d
if [ -f /etc/systemd/system/docker.service.d/data-root.conf ]; then
    cp -a /etc/systemd/system/docker.service.d/data-root.conf \
        "/etc/systemd/system/docker.service.d/data-root.conf.${backup_suffix}.bak"
fi
cat > /etc/systemd/system/docker.service.d/data-root.conf <<EOF
[Unit]
RequiresMountsFor=${docker_target}
EOF

mkdir -p /etc/systemd/system/containerd.service.d
if [ -f /etc/systemd/system/containerd.service.d/data-root.conf ]; then
    cp -a /etc/systemd/system/containerd.service.d/data-root.conf \
        "/etc/systemd/system/containerd.service.d/data-root.conf.${backup_suffix}.bak"
fi
cat > /etc/systemd/system/containerd.service.d/data-root.conf <<EOF
[Unit]
RequiresMountsFor=${containerd_target}

[Service]
ExecStart=
ExecStart=${containerd_binary} --root ${containerd_target}
EOF

configuration_switched=true
systemctl daemon-reload
systemctl start containerd.service
systemctl start docker.service
services_stopped=false

actual_docker_root="$(docker info --format '{{.DockerRootDir}}')"
if [ "${actual_docker_root}" != "${docker_target}" ]; then
    echo "Docker started with unexpected data root: ${actual_docker_root}" >&2
    exit 1
fi

if ! systemctl is-active --quiet containerd.service ||
    ! systemctl is-active --quiet docker.service; then
    echo "Docker or containerd did not remain active." >&2
    exit 1
fi

migration_state="/etc/docker-storage-migration.json"
python3 - \
    "${migration_state}" \
    "${docker_source}" \
    "${docker_target}" \
    "${containerd_source}" \
    "${containerd_target}" \
    "$(cat /proc/sys/kernel/random/boot_id)" <<'PY'
import datetime
import json
import os
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
state = {
    "docker_source": sys.argv[2],
    "docker_target": sys.argv[3],
    "containerd_source": sys.argv[4],
    "containerd_target": sys.argv[5],
    "migration_boot_id": sys.argv[6],
    "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}

with state_path.open("w", encoding="utf-8") as state_file:
    json.dump(state, state_file, indent=2)
    state_file.write("\n")
os.chmod(state_path, 0o600)
PY

trap - ERR

cat <<EOF

Migration completed successfully.
Docker root: ${actual_docker_root}

The old directories were retained:
  ${docker_source}
  ${containerd_source}

Reboot and verify Docker, then remove the retained sources with:
  ./cleanup-docker-storage-migration.sh

Migration state was saved to:
  ${migration_state}
EOF
