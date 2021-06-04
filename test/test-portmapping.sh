#!/bin/sh

set -eux

podman run -p 8081:8080 --rm alpine:3.13 /bin/sh -c "echo \$'#!/bin/sh\ntimeout 1 cat - >/dev/null; echo -e \\\"HTTP/1.1 200 OK\n\nup\\\"' > /tmp/healthy && chmod +x /tmp/healthy && timeout 9 nc -l -p 8080 -e /tmp/healthy" &
sleep 5
wget -O - localhost:8081
