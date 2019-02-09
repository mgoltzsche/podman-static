#!/bin/sh

set -eux

while [ $# -gt 0 ]; do
	case "$1" in
		build)
			docker build --force-rm -t podman .
		;;
		run)
			mkdir -p storage
			chown 9000:9000 storage
			docker run -ti --rm --name podman --privileged -v "`pwd`/storage":/podman/.local/share/containers/storage podman /bin/sh
		;;
	esac
	shift
done
