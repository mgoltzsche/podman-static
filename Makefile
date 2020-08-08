IMAGE?=mgoltzsche/podman

image:
	docker build --force-rm -t $(IMAGE) .

test: image
	IMAGE=$(IMAGE) ./test.sh

run:
	docker run -ti --rm --name podman --privileged \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				$(IMAGE) /bin/sh
