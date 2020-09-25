# podman container image

This image provides an easy way to try out podman and a base for
nested and rootless containerization scenarios.  

The alpine-based image provides the following statically linked binaries
_(without systemd support)_:
* [podman](https://github.com/containers/libpod)
* [runc](https://github.com/opencontainers/runc/)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns)
* [CNI plugins](https://github.com/containernetworking/plugins): loopback, bridge, host-local, portmap

Containers need to be `--privileged`.  

As a workaround for docker the entrypoint script changes the owner of
the storage volume mount point (`/podman/.local/share/containers/storage`)
to the unprivileged user `podman` (100000) before it runs the provided command.


## Usage example

Run podman in docker (within the container `docker` links to `podman`):
```
docker run --privileged mgoltzsche/podman:latest docker run alpine:latest echo hello from podman
```


## Local build & test

```
make
make test
```
