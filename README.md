# podman binaries and container images ![GitHub workflow badge](https://github.com/mgoltzsche/podman-static/workflows/Release/badge.svg)

This project provides alpine-based podman container images and statically linked (rootless) podman binaries for linux/amd64 and linux/arm64/v8 machines along with its dependencies _(without systemd support)_:
* [podman](https://github.com/containers/podman)
* [runc](https://github.com/opencontainers/runc/) or [crun](https://github.com/containers/crun)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs) and [libfuse](https://github.com/libfuse/libfuse)
* [slirp4netns](https://github.com/rootless-containers/slirp4netns) (with [libslirp](https://gitlab.freedesktop.org/slirp/libslirp))
* [CNI plugins](https://github.com/containernetworking/plugins): loopback, bridge, host-local, portmap, firewall, tuning
* [catatonit](https://github.com/openSUSE/catatonit)

## Container image

The following image tags are supported:

| Tag | Description |
| --- | ----------- |
| `latest`, `<VERSION>` | podman with both rootless and rootful dependencies: runc, conmon, fuse-overlayfs, slirp4netns, CNI plugins, catatonit. |
| `minimal`, `<VERSION>-minimal` | podman, crun, fuse-overlayfs and conmon binaries, configured to use the host's existing namespaces (low isolation level). |
| `remote`, `<VERSION>-remote` | the podman remote binary. |

By default containers are run as user `root`.
However the `podman` (uid/gid 1000) user can be used instead for which also a subuid/gid mapping is configured with the image (as described within the binary installation section below).  

Please note that, when running non-remote podman within a docker container, the docker container needs to be `--privileged`.

### Container usage example

Run podman in docker:
```sh
docker run --privileged -u podman:podman mgoltzsche/podman:minimal docker run alpine:latest echo hello from nested container
```
_Within the container `docker` is linked to `podman` to support applications that use the `docker` command._

## Binary installation on a host

_In case you're using an arm64 machine (e.g. a Raspberry Pi), you need to substitute "amd64" with "arm64" within the commands below to make the installation work for you._  

Download the statically linked binaries of podman and its dependencies:
```sh
curl -fsSL -o podman-linux-amd64.tar.gz https://github.com/mgoltzsche/podman-static/releases/latest/download/podman-linux-amd64.tar.gz
```

Verify the archive's signature (optional):
```sh
curl -fsSL -o podman-linux-amd64.tar.gz.asc https://github.com/mgoltzsche/podman-static/releases/latest/download/podman-linux-amd64.tar.gz.asc
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0CCF102C4F95D89E583FF1D4F8B5AF50344BB503
gpg --batch --verify podman-linux-amd64.tar.gz.asc podman-linux-amd64.tar.gz
```
_This may fail every now and then due to desync/unavailable key servers. In that case please retry._  

Download a specific version:
```sh
VERSION=<VERSION>
curl -fsSL -o podman-linux-amd64.tar.gz https://github.com/mgoltzsche/podman-static/releases/download/$VERSION/podman-linux-amd64.tar.gz
```

Install the binaries and configuration on your host after you've inspected the archive:
```sh
tar -xzf podman-linux-amd64.tar.gz
sudo cp -r podman-linux-amd64/usr podman-linux-amd64/etc /
```

_If you have docker installed on the same host it might be broken until you remove the newly installed `/usr/local/bin/runc` binary since older docker versions are not compatible with the latest runc version provided here while podman is also compatible with the older runc version that comes e.g. with docker 1.19 on Ubuntu._

To install podman on a host without having any root privileges, you need to copy the binaries and configuration into your home directory and adjust the binary paths within the configuration correspondingly.
For more information see [podman's rootless installation instructions](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md).

### Host configuration

The following binaries should be installed on your host:
* `iptables`
* `nsenter`
* `uidmap` (for rootless mode)

In order to run rootless containers that use multiple uids/gids you may want to set up a uid/gid mapping for your user on your host:
```
sudo sh -c "echo $(id -un):100000:200000 >> /etc/subuid"
sudo sh -c "echo $(id -gn):100000:200000 >> /etc/subgid"
```
_Please make sure you don't add the mapping multiple times._  

To support applications that use the `docker` command you may want to link it to `podman` as follows:
```sh
sudo ln -s /usr/local/bin/podman /usr/local/bin/docker
```

Before updating binaries on your host please terminate all corresponding processes.  

### Restart containers on boot

To restart containers with restart-policy=always on boot, enable the `podman-restart` systemd service:
```sh
systemctl enable podman-restart
```

### Binary usage example

```sh
podman run alpine:latest echo hello from podman
```

## Default persistent storage location

The default storage location depends on the user:
* For `root` storage is located at `/var/lib/containers/storage`.
* For unprivileged users storage is located at `~/.local/share/containers/storage`.

## Local build & test

```sh
make images test
```
