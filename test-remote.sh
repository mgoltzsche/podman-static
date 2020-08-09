#!/bin/sh

set -x

ADDRESS=127.0.0.1:53453

PODMAN_CONTAINER="$(docker run -d --rm --privileged --network=host \
	-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
	"${PODMAN_IMAGE}" \
	podman system service -t 0 tcp:$ADDRESS)"
docker logs -f "$PODMAN_CONTAINER" 2>&1 | sed -E 's/^/podman service: /g' &

sleep 2

(
set -e
docker run --rm --network=host -v "$(pwd)/test:/build" \
	"${PODMAN_REMOTE_IMAGE}" \
	podman --url=tcp://$ADDRESS run alpine:3.12 echo hello from remote container

# ATTENTION: remote `podman build` and volume mounts don't work (using podman 2.0.4)
#docker run --rm --network=host \
#	-v "`pwd`/test:/build" \
#	"${PODMAN_REMOTE_IMAGE}" \
#	sh -c "set -ex; \
#		podman --log-level=debug --remote --url=tcp://$ADDRESS build -t testbuild -f /build/Dockerfile /build; \
#		podman --url=tcp://$ADDRESS run testbuild echo hello from remote container"
#docker run --rm --network=host \
#	-v "`pwd`/test:/build" \
#	"${PODMAN_REMOTE_IMAGE}" \
#	sh -c "set -ex; \
#		echo hello > myfile; \
#		podman --url=tcp://$ADDRESS run -v \$(pwd)/myfile:/myfile alpine:3.12 cat /myfile"
)
STATUS=$?

docker kill $PODMAN_CONTAINER
exit $STATUS
