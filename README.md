# podman container image

This image provides an easy way to try out podman and a base for
nested containerization scenarios where the child container should
run as unprivileged user.

The alpine-based image contains the following statically linked binaries:
* [podman](https://github.com/containers/libpod)
* [runc](https://github.com/opencontainers/runc/)
* [conmon](https://github.com/kubernetes-sigs/cri-o)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns)
* [buildah](https://github.com/containers/buildah)

Containers must be run as `--privileged`.
The container process is still started with the root user to allow
the entrypoint script to change the storage volume mount point's
(`/podman/.local/share/containers/storage`) owner to the unprivileged
`podman` user.


## Usage example

```
docker run --privileged mgoltzsche/podman docker run alpine:3.9 echo hello from nested podman container
```


## Local image build & run

```
./make.sh build run
```
