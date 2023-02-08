#!/usr/bin/env bats

: ${DOCKER:=docker}
: ${PODMAN_IMAGE:=mgoltzsche/podman:latest}
: ${PODMAN_REMOTE_IMAGE:=mgoltzsche/podman:latest-remote}

PODMAN_ADDRESS=127.0.0.1:53453
PODMAN_CONTAINER=podman-test-server
PODMAN_DATA_DIR="$BATS_TEST_DIRNAME/../build/test-storage/user"

setup_file() {
	mkdir -pm1777 "$PODMAN_DATA_DIR"
	$DOCKER run --name=$PODMAN_CONTAINER -d --rm --privileged --pull=never \
		--network=host -u podman:podman \
		-v "$PODMAN_DATA_DIR:/podman/.local/share/containers/storage" \
		"${PODMAN_IMAGE}" \
		podman --log-level=debug system service -t 0 tcp:$PODMAN_ADDRESS 2>&1 >/dev/null | sed -E 's/^/# setup_file ERROR: start podman service: /g' >&3
	sleep 5
}

teardown_file() {
	$DOCKER kill $PODMAN_CONTAINER 2>&1 >/dev/null | sed -E 's/^/# teardown_file ERROR: kill podman svc: /g' >&3
}

@test "remote podman - run container" {
	$DOCKER run --rm --network=host --pull=never "${PODMAN_REMOTE_IMAGE}" \
		podman --url=tcp://$PODMAN_ADDRESS run alpine:3.17 echo hello from remote container
}

@test "remote podman - build image from dockerfile" {
	# ATTENTION: podman remote fails if it cannot map the uids/gids from the server locally as well (which is why podman-remote user has been added)
	$DOCKER run --rm --network=host --user=podman-remote:podman-remote --pull=never \
		"${PODMAN_REMOTE_IMAGE}" \
		sh -c "set -ex; \
			mkdir /tmp/testcontext
			printf 'FROM alpine:3.17\nRUN echo hello\nCMD [ "/bin/echo", "hello" ]' > /tmp/testcontext/Dockerfile
			podman --log-level=debug --remote --url=tcp://$PODMAN_ADDRESS build -t testbuild -f /tmp/testcontext/Dockerfile /tmp/testcontext; \
			podman --url=tcp://$PODMAN_ADDRESS run testbuild echo hello from remote container"
}
