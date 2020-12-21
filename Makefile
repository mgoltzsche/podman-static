PODMAN_IMAGE?=mgoltzsche/podman
PODMAN_REMOTE_IMAGE?=mgoltzsche/podman-remote
PODMAN_SSH_IMAGE?=mgoltzsche/podman-ssh

all: podman podman-remote podman-ssh

podman:
	docker build --force-rm -t $(PODMAN_IMAGE) .

podman-ssh:
	docker build --force-rm -t $(PODMAN_SSH_IMAGE) -f Dockerfile-ssh --build-arg BASEIMAGE=$(PODMAN_IMAGE) .

podman-remote:
	docker build --force-rm -t $(PODMAN_REMOTE_IMAGE) -f Dockerfile-remote .

test: test-local test-remote

test-local: podman
	IMAGE=$(PODMAN_IMAGE) ./test/test-local.sh

test-remote: podman podman-remote
	PODMAN_IMAGE=$(PODMAN_IMAGE) \
	PODMAN_REMOTE_IMAGE=$(PODMAN_REMOTE_IMAGE) \
		./test/test-remote.sh

run:
	docker run -ti --rm --privileged \
				-v "`pwd`/test/storage/user":/podman/.local/share/containers/storage \
				$(PODMAN_IMAGE) /bin/sh

clean:
	docker run -ti --rm -v "`pwd`/test:/test" alpine:3.12 rm -rf /test/storage

run-server:
	# TODO: make sshd log to stdout (while still ensuring that we know when it is available)
	docker run --rm --privileged --network=host \
		-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
		-v "`pwd`/test:/build" \
		-w /build \
		"${PODMAN_SSH_IMAGE}" \
		sh -c 'set -x; \
			ssh-keygen -b 2048 -t rsa -N "" -f /podman/.ssh/ssh_host_rsa_key; \
			ssh-keygen -b 521 -t ecdsa -N "" -f /podman/.ssh/ssh_host_ecdsa_key; \
			[ -f /build/storage/user/client_rsa ] || ssh-keygen -b 2048 -t rsa -N "" -f /build/storage/user/client_rsa; \
			cat /build/storage/user/client_rsa.pub > /podman/.ssh/authorized_keys; \
			/usr/sbin/sshd -eD -f ~/.ssh/sshd_config & \
			mkdir /tmp/podman; \
			podman system service -t 0 unix:///tmp/podman/podman.sock'

# TODO: fix build run for external client
# see ssh connection: https://github.com/containers/podman/blob/v2.0.4/pkg/bindings/connection.go#L73
run-client:
	docker run --rm -it --network=host \
		-v "`pwd`/test:/build" \
		-w /build \
		-e PODMAN_URL=ssh://podman@127.0.0.1:2222/tmp/podman/podman.sock?secure=True \
		-e CONTAINER_SSHKEY=/build/storage/user/client_rsa \
		"${PODMAN_REMOTE_IMAGE}" \
		/bin/sh -c 'set -ex; \
			podman --url=$$PODMAN_URL --log-level=info build /build/test'
#ssh -o "StrictHostKeyChecking no" -i /build/client_rsa podman@127.0.0.1 -p 2222 echo hello
