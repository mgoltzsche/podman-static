#!/bin/sh

set -e

if [ $(id -u) -eq 0 ]; then
	# Make sure podman user owns the storage directory
	# (a volume created by the docker CLI is owned by root by default)
	mkdir -p /podman/.local/share/containers/storage
	chown podman:podman /podman /podman/.local /podman/.local/share/containers /podman/.local/share/containers/storage

	exec gosu podman:podman "$@"
else
	exec "$@"
fi
