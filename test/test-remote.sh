#!/bin/sh

DOCKER=${DOCKER:-docker}

echo
echo TEST REMOTE PODMAN
echo

cd "$(dirname $0)"

set -ux

ADDRESS=127.0.0.1:53453

mkdir -pm1777 `pwd`/storage/user
PODMAN_CONTAINER="$($DOCKER run -d --rm --privileged --network=host -u podman:podman \
	-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
	"${PODMAN_IMAGE}" \
	podman system service -t 0 tcp:$ADDRESS)"
docker logs -f "$PODMAN_CONTAINER" 2>&1 | sed -E 's/^/podman service: /g' &

sleep 5

(
set -eu
$DOCKER run --rm --network=host -v "$(pwd):/build" \
	"${PODMAN_REMOTE_IMAGE}" \
	podman --url=tcp://$ADDRESS run alpine:3.12 echo hello from remote container

# ATTENTION: podman remote fails if it cannot map the uids/gids from the server locally as well (which is why podman-remote user has been added)
$DOCKER run --rm --network=host --user=podman-remote:podman-remote \
	-v "`pwd`/Dockerfile:/build/Dockerfile" \
	"${PODMAN_REMOTE_IMAGE}" \
	sh -c "set -ex; \
		podman --log-level=debug --remote --url=tcp://$ADDRESS build -t testbuild -f /build/Dockerfile /build; \
		podman --url=tcp://$ADDRESS run testbuild echo hello from remote container"

# ATTENTION: volume mounts don't work (using podman 2.0.4)
#$DOCKER run --rm --network=host \
#	-v "`pwd`:/build" \
#	"${PODMAN_REMOTE_IMAGE}" \
#	sh -c "set -ex; \
#		echo hello > myfile; \
#		podman --url=tcp://$ADDRESS run -v \$(pwd)/myfile:/myfile alpine:3.12 cat /myfile"
)
STATUS=$?

$DOCKER kill $PODMAN_CONTAINER
exit $STATUS
