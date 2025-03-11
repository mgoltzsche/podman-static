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

@test "rootful podman - internet connectivity (using netavark + pasta)" {
	skipIfDockerUnavailableAndNotRunAsRoot
	$DOCKER run --rm --privileged --entrypoint /bin/sh -u root:root \
		-v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" \
		--pull=never "${PODMAN_IMAGE}" \
		-c 'podman run --rm alpine:3.17 wget -O /dev/null http://example.org'
}

@test "rootful podman - build dockerfile" {
	skipIfDockerUnavailableAndNotRunAsRoot
	$DOCKER run --rm --privileged --entrypoint /bin/sh -u root:root \
		-v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" \
		--pull=never "${PODMAN_IMAGE}" \
		-c 'set -e;
			podman build -t podmantestimage -f - . <<-EOF
				FROM alpine:latest
				RUN echo hello world > /hello
				CMD ["/bin/cat", "/hello"]
			EOF'
}

@test "rootful podman - port forwarding" {
	skipIfDockerUnavailableAndNotRunAsRoot
	testPortForwarding -u root:root -v "$PODMAN_ROOT_DATA_DIR:/var/lib/containers/storage" "${PODMAN_IMAGE}"
}

@test "$TEST_PREFIX quedlet - generate service" {
	if [ "${TEST_SKIP_QUADLET:-}" = true ]; then
		skip "TEST_SKIP_QUADLET=true"
	fi
	$DOCKER run --rm -u podman:podman \
		-v "$BATS_TEST_DIRNAME/quadlet/hello_world.container:/etc/containers/systemd/hello_world.container" \
		--pull=never "${PODMAN_IMAGE}" \
		/usr/local/libexec/podman/quadlet -dryrun > $PODMAN_ROOT_DATA_DIR/test.service

	expected_values=(
        "--name hello_world"
        "--publish 8080:8080"
        "--env HELLO=WORLD"
        "docker.io/hello-world"
    )

    for value in "${expected_values[@]}"; do
        run grep -q -- "$value" "$PODMAN_ROOT_DATA_DIR/test.service"
        [ "$status" -eq 0 ] || fail "Expected '$value' not found in $PODMAN_ROOT_DATA_DIR/test.service"
    done
}