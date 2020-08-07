# podman container image

This image provides an easy way to try out podman and a base for
nested containerization scenarios where the child container should
run as unprivileged user.

The alpine-based image contains the following statically linked binaries
_(without systemd support)_:
* [podman](https://github.com/containers/libpod)
* [crun](https://github.com/containers/crun)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns)
* [buildah](https://github.com/containers/buildah)


Containers need to be `--privileged`.  


As a workaround for docker the entrypoint script changes the owner of
the storage volume mount point (`/podman/.local/share/containers/storage`)
to the unprivileged `podman` user (100000)
before it runs the provided command.


## Usage example

```
docker run --privileged mgoltzsche/podman:latest docker run alpine:latest echo hello from podman
```


## Local build, test & run

```
./make.sh build test run
```
