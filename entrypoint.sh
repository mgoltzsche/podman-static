#!/bin/sh

# Make sure podman user owns storage directory
chown podman:podman /podman/.local/share/containers/storage || exit 1

mount --make-shared /
ls -la /sys/fs/cgroup/systemd/

# TODO: fix or remove: Attempted workaround for podman 1.6
# cannot resolve cgroups since the ones listed in /proc/1/cgroups
# are not visible in /sys/fs/cgroups
#mkdir /sys/fs/cgroup/systemd/podman
#chown -R podman:podman /sys/fs/cgroup/systemd/podman
#ls -la /sys/fs/cgroup/systemd/podman
#echo $$ > /sys/fs/cgroup/systemd/podman/cgroup.procs

#mount -t cgroup cgroups /sys/fs/cgroup/systemd/podman

exec gosu podman:podman "$@"
