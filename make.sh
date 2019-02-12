#!/bin/sh

set -eux

while [ $# -gt 0 ]; do
	case "$1" in
		build)
			docker build --force-rm -t mgoltzsche/podman .
		;;
		run)
			docker run -ti --rm --name podman --privileged \
				-v "`pwd`/storage":/podman/.local/share/containers/storage \
				mgoltzsche/podman /bin/sh
		;;
	esac
	shift
done
