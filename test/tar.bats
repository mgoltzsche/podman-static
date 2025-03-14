#!/usr/bin/env bats

: ${DOCKER:=docker}
: ${PODMAN_TAR_IMAGE:=mgoltzsche/podman:latest-tar}

@test "tar - quadlet - generate service" {
	if [ "${TEST_SKIP_QUADLET:-}" = true ]; then
		skip "TEST_SKIP_QUADLET=true"
	fi
	$DOCKER run --rm -u podman:podman \
		-v "$BATS_TEST_DIRNAME/quadlet/hello_world.container:/etc/containers/systemd/hello_world.container" \
		--pull=never "${PODMAN_TAR_IMAGE}" \
		/usr/local/libexec/podman/quadlet -dryrun > /tmp/test.service # this goes to tmp because we are not root below

	expected_values=(
        "--name hello_world"
        "--publish 8080:8080"
        "--env HELLO=WORLD"
        "docker.io/hello-world"
    )

    for value in "${expected_values[@]}"; do
        run grep -q -- "$value" "/tmp/test.service"
        [ "$status" -eq 0 ] || fail "Expected '$value' not found in /tmp/test.service"
    done
}
