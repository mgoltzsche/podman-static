#!/usr/bin/env bats

: ${DOCKER:=docker}
: ${PODMAN_IMAGE:=mgoltzsche/podman:latest}

PODMAN_ROOT_DATA_DIR="$BATS_TEST_DIRNAME/../build/test-storage/root"

load test_helper.bash

skipIfDockerUnavailableAndNotRunAsRoot() {
	if [ "$DOCKER" = podman -a $(id -u) -ne 0 ]; then
		skip "run by unprivileged user and DOCKER=podman"
	fi
}

@test "rootful podman - internet connectivity (CNI networking)" {
	skipIfDockerUnavailableAndNotRunAsRoot
	$DOCKER run --rm --privileged --entrypoint /bin/sh -u root:root \
		-v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" \
		"${PODMAN_IMAGE}" \
		-c 'podman run --rm alpine:3.14 wget -O /dev/null http://example.org'
}

@test "rootful podman - build image from dockerfile" {
	skipIfDockerUnavailableAndNotRunAsRoot
	$DOCKER run --rm --privileged --entrypoint /bin/sh -u root:root \
		-v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" \
		"${PODMAN_IMAGE}" \
		-c 'set -e;
			podman build -t podmantestimage -f - . <<-EOF
				FROM alpine:latest
				RUN echo hello world > /hello
				CMD ["/bin/cat", "/hello"]
			EOF'
}

@test "rootful podman - port mapping" {
	skipIfDockerUnavailableAndNotRunAsRoot
	testPortMapping -u root:root -v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" "${PODMAN_IMAGE}"
}
