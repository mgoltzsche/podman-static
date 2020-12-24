#!/bin/sh

cd "$(dirname $0)"

set -eu

echo
echo TEST PODMAN AS ROOT '(using CNI)'
echo
(set -x; docker run --rm --privileged --entrypoint /bin/sh \
	-u root:root \
	-v "`pwd`/storage/root":/var/lib/containers/storage \
	"${IMAGE}" \
	-c 'podman run --rm alpine:3.12 wget -O /dev/null http://example.org')

echo
echo TEST PODMAN AS ROOT - PORT MAPPING
echo
(set -x; docker run --rm --privileged --entrypoint /bin/sh \
	-u root:root \
	-v "`pwd`/storage/root":/var/lib/containers/storage \
	--mount "type=bind,src=`pwd`/test-portmapping.sh,dst=/test-portmapping.sh" \
	"${IMAGE}" \
	-c /test-portmapping.sh)

echo
echo TEST PODMAN DOCKERFILE BUILD AS ROOT
echo
(set -x; docker run -ti --rm --privileged --entrypoint /bin/sh \
	-u root:root \
	-v "`pwd`/storage/root":/podman/.local/share/containers/storage \
	"${IMAGE}" \
	-c 'set -e;
		podman build -t podmantestimage -f - . <<-EOF
			FROM alpine:latest
			RUN echo hello world > /hello
			CMD ["/bin/cat", "/hello"]
		EOF')
