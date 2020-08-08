#!/bin/sh

set -x

ADDRESS=127.0.0.1:53453

PODMAN_CONTAINER="$(docker run -d --rm --privileged --network=host \
	-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
	"${PODMAN_IMAGE}" \
	podman system service -t 0 tcp:$ADDRESS)"

sleep 2

(
set -e
docker run --rm --network=host \
	-v "$(pwd)/test:/build" \
	-w /build \
	"${PODMAN_REMOTE_IMAGE}" \
	sh -c "podman --url=tcp://$ADDRESS run alpine:3.12 echo hello from remote container"

# TODO: make `podman build` and volume mounts work
docker run --rm --network=host \
	-v "$(pwd)/test:/build" \
	-w /build \
	"${PODMAN_REMOTE_IMAGE}" \
	sh -c "set -ex; echo hello > /myfile; podman --log-level=debug --remote --url=tcp://$ADDRESS build -t testbuild -f Dockerfile .; podman --url=tcp://$ADDRESS run -v /myfile:/myfile testbuild cat /myfile"
)
STATUS=$?

docker kill $PODMAN_CONTAINER
exit $STATUS
