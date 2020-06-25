#!/bin/sh

set -e

# Make sure podman user owns storage directory
chown podman:podman /podman/.local/share/containers/storage

exec gosu podman:podman "$@"
