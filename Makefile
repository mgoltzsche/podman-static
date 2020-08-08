PODMAN_IMAGE?=mgoltzsche/podman
PODMAN_REMOTE_IMAGE?=mgoltzsche/podman-remote

all: podman podman-remote

podman:
	docker build --force-rm -t $(PODMAN_IMAGE) .

podman-remote:
	docker build --force-rm -t $(PODMAN_REMOTE_IMAGE) -f Dockerfile-remote .

test: test-local test-remote

test-local: podman
	IMAGE=$(PODMAN_IMAGE) ./test-local.sh

test-remote: podman podman-remote
	PODMAN_IMAGE=$(PODMAN_IMAGE) \
	PODMAN_REMOTE_IMAGE=$(PODMAN_REMOTE_IMAGE) \
		./test-remote.sh

run:
	docker run -ti --rm --privileged \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				$(PODMAN_IMAGE) /bin/sh
