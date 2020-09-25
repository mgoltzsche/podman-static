#!/bin/sh

set -e

if [ $(id -u) -eq 0 ]; then
	# Make sure podman user owns storage directory
	chown podman:podman /podman/.local/share/containers/storage

	exec gosu podman:podman "$@"
else
	# TODO: avoid "No subuid ranges found" and setuid errors - follow rootless improvements: https://github.com/containers/podman/issues/3932
	#   As a solution an OCI hook could be configured that runs proot
	exec "$@"
fi
