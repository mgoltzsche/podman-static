#!/bin/bash

# ARGS: DOCKER_RUN_OPTS
testPortMapping() {
	$DOCKER run --rm -i --privileged --entrypoint /bin/sh --pull=never $@ - <<-EOF
		set -ex
		podman pull nginxinc/nginx-unprivileged:1.20-alpine
		podman run -p 8182:8080 --entrypoint=/bin/sh nginxinc/nginx-unprivileged:1.20-alpine -c 'timeout 15 nginx -g "daemon off;"' &
		sleep 5
		wget -O - localhost:8182
	EOF
}
