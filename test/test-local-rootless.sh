cd "$(dirname $0)"

TEST_PREDICATE="${TEST_PREDICATE}"

set -eu

echo
echo TEST ${TEST_PREDICATE} PODMAN AS UNPRIVILEGED USER - NETWORK CONNECTIVITY
echo
(set -x; docker run --rm --privileged -u podman:podman \
	-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
	"${IMAGE}" \
	docker run --rm alpine:3.12 wget -O /dev/null http://example.org)

echo
echo TEST ${TEST_PREDICATE} PODMAN AS UNPRIVILEGED USER - UID MAPPING '(using fuse-overlayfs)'
echo
(set -x; docker run --rm --privileged -u podman:podman \
	-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
	"${IMAGE}" \
	docker run --rm alpine:3.12 /bin/sh -c 'set -ex; touch /file; chown guest /file; [ $(stat -c %U /file) = guest ]')

echo
echo TEST ${TEST_PREDICATE} PODMAN AS UNPRIVILEGED USER WITH NON-DEFAULT UID '(no uid/gid mapping)'
echo
(set -x; docker run --rm --privileged --user 9000:9000 \
	"${IMAGE}" \
	docker run --rm alpine:3.12 wget -O /dev/null http://example.org)

echo
echo TEST ${TEST_PREDICATE} PODMAN BUILD DOCKERFILE AS UNPRIVILEGED USER
echo
(set -x; docker run --rm --privileged -u podman:podman --entrypoint /bin/sh \
	-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
	"${IMAGE}" \
	-c 'set -e;
		podman build -t podmantestimage -f - . <<-EOF
			FROM alpine:3.12
			RUN echo hello world > /hello
			CMD ["/bin/cat", "/hello"]
		EOF')

if [ ! "${SKIP_PORTMAPPING_TEST:-}" ]; then
echo
echo TEST ${TEST_PREDICATE} PODMAN AS UNPRIVILEGED USER - PORT MAPPING
echo
(set -x; docker run --rm --privileged -u podman:podman \
	-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
	--mount "type=bind,src=`pwd`/test-portmapping.sh,dst=/test-portmapping.sh" \
	"${IMAGE}" \
	/bin/sh -c /test-portmapping.sh)
fi
