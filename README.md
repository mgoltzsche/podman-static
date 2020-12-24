# podman binaries and container image ![GitHub workflow badge](https://github.com/mgoltzsche/podman-static/workflows/Release/badge.svg)

This project provides alpine-based podman container image variants and statically linked (rootless) podman binaries for linux-amd64 along with its dependencies _(without systemd support)_:
* [podman](https://github.com/containers/libpod)
* [runc](https://github.com/opencontainers/runc/) or [crun](https://github.com/containers/crun)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs) and [libfuse](https://github.com/libfuse/libfuse)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns) (with [libslirp](https://gitlab.freedesktop.org/slirp/libslirp))
* [CNI plugins](https://github.com/containernetworking/plugins): loopback, bridge, host-local, portmap

## Container image

The following image tags are supported:
* `latest`, `<VERSION>` - podman with both rootless and rootful dependencies: runc, conmon, fuse-overlayfs, slirp4netns, CNI plugins.
* `rootless`, `<VERSION>-rootless` - podman with crun (configured to use host cgroup), fuse-overlayfs, slirp4netns and conmon.
* `remote`, `<VERSION>-remote` - the podman remote binary.

Please note that, when running podman within a docker container, the docker container needs to be `--privileged`.  

As a workaround for docker the entrypoint script changes the owner of the storage volume mount point (`$HOME/.local/share/containers/storage`) to the unprivileged user `podman` (100000, `HOME=/podman`) before it runs the provided command.  
Though the entrypoint script can be omitted and a container can be run with any unprivileged user explicitly since the image is user agnostic - though the default uid/gid map only supports the `podman` user.

### Container usage example

Run podman in docker:
```sh
docker run --privileged mgoltzsche/podman:rootless docker run alpine:latest echo hello from nested container
```
_Within the container `docker` is linked to `podman` to support applications that require `docker`._

## Binary installation on a host

Download the statically linked binaries of podman and its dependencies:
```sh
curl -fsSL -o podman-linux-amd64.tar.gz https://github.com/mgoltzsche/podman-static/releases/latest/download/podman-linux-amd64.tar.gz
```

Verify the archive's signature (optional):
```sh
curl -fsSL -o podman-linux-amd64.tar.gz.asc https://github.com/mgoltzsche/podman-static/releases/latest/download/podman-linux-amd64.tar.gz.asc
gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 0CCF102C4F95D89E583FF1D4F8B5AF50344BB503
gpg --batch --verify podman-linux-amd64.tar.gz.asc podman-linux-amd64.tar.gz
```
_This may fail every now and then due to desync/unavailable key servers. Please retry in that case._  

Install the binaries and configuration on your host after you've inspected the archive:
```sh
tar -xzf podman-linux-amd64.tar.gz
sudo cp -r podman-linux-amd64/usr podman-linux-amd64/etc /
```

To support applications that require the `docker` command you may want to link it to `podman` as follows:
```sh
sudo ln -s /usr/local/bin/podman /usr/bin/docker
```

### Binary usage example

```sh
podman run alpine:latest echo hello from podman
```

## Local build & test

```sh
make
make test
```
