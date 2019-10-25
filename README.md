# podman container image

This image provides an easy way to try out podman and a base for
nested containerization scenarios where the child container should
run as unprivileged user.

The alpine-based image contains the following statically linked binaries
_(without systemd support)_:
* [podman](https://github.com/containers/libpod)
* [runc](https://github.com/opencontainers/runc/)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns)
* [buildah](https://github.com/containers/buildah)


Containers need to be `--privileged`.  


Before the entrypoint script runs the provided command as unprivileged
user `podman` (100000) it does some workarounds:
* Change the owner of the storage volume mount point
  (`/podman/.local/share/containers/storage`) to the unprivileged
  `podman` user.
* Create cgroup from `/proc/1/cgroup` within `/sys/fs/cgroup` if it does
  not exist because inside the container this cgroup is the cgroup root.


## Usage example

```
docker run --privileged mgoltzsche/podman:latest docker run alpine:latest echo hello from podman
```


## Local build, test & run

```
./make.sh build test run
```
