#!/bin/sh

set -e

# Make sure podman user owns storage directory
chown podman:podman /podman/.local/share/containers/storage

# Workaround since rootless podman 1.6 within a container fails to
# resolve its cgroup because /proc/1/cgroup contains the host path
# while the container's cgroup is mounted as root cgroup in
# /sys/fs/cgroups.
# The cgroup host path issue is old (https://github.com/moby/moby/issues/34584)
# but it appears in podman since 1.6 when run as unprivileged user somehow.
# --cgroup-parent option could solve it but appears not to be functional.
# Alternatively the container could be run with the host's cgroups
# mounted: `-v /sys/fs/cgroup:/sys/fs/cgroup:rw`.
CGROUP="$(grep -E '^1:name=' /proc/self/cgroup | sed -E 's/^1:name=([^:]+):/\1/')"
mkdir -p "/sys/fs/cgroup/$CGROUP"

# Run the provided command as podman user
exec gosu podman:podman "$@"
