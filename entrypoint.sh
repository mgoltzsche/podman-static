#!/bin/sh

chown podman:podman /podman/.local/share/containers/storage || exit 1

exec gosu podman:podman "$@"
