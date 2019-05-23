#!/bin/sh

IMAGE=${PODMAN_IMAGE:-mgoltzsche/podman}

set -eux

while [ $# -gt 0 ]; do
	case "$1" in
		build)
			docker build --force-rm -t ${IMAGE} .
		;;
		run)
			docker run -ti --rm --name podman --privileged \
				-v "`pwd`/storage":/podman/.local/share/containers/storage \
				${IMAGE} /bin/sh
		;;
	esac
	shift
done
