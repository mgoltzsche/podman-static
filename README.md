# podman binaries and container images ![GitHub workflow badge](https://github.com/mgoltzsche/podman-static/workflows/Build/badge.svg)

This project provides alpine-based podman container images and statically linked (rootless) podman binaries for linux/amd64 and linux/arm64/v8 machines along with its dependencies _(without systemd support)_:
* [podman](https://github.com/podman-container-tools/podman)
* [crun](https://github.com/containers/crun)
* [runc](https://github.com/opencontainers/runc/)
* [conmon](https://github.com/containers/conmon)
* [fuse-overlayfs](https://github.com/containers/fuse-overlayfs) and [libfuse](https://github.com/libfuse/libfuse)
* [Netavark](https://github.com/containers/netavark): container network stack and default in podman 5 or later
  * [passt/pasta](https://passt.top/passt/)
  * [aardvark-dns](https://github.com/containers/aardvark-dns)
* [catatonit](https://github.com/openSUSE/catatonit)

CNI networking has been replaced with Netavark since Podman version 5.

## Container image

The following image tags are supported:

| Tag | Description |
| --- | ----------- |
| `latest`, `<VERSION>` | podman with all dependencies: runc, crun, conmon, fuse-overlayfs, netavark, pasta, aardvark-dns, catatonit. |
| `minimal`, `<VERSION>-minimal` | podman, crun, conmon, fuse-overlayfs and netavark binaries, configured to use the host's existing namespaces (low isolation level). |
| `remote`, `<VERSION>-remote` | the podman remote binary. |

By default containers are run as user `root`.
However the `podman` (uid/gid 1000) user can be used instead for which also a subuid/gid mapping is configured with the image (as described within the binary installation section below).  

Please note that, when running non-remote podman within another container, the parent container needs to be run with `--device=/dev/fuse`.

### Container usage examples

Run podman in docker (or podman):
```sh
docker run --device=/dev/fuse -u podman:podman mgoltzsche/podman:minimal docker run alpine:latest echo hello from nested container
```
_Within the container `docker` is linked to `podman` to support applications that use the `docker` command._

To allow the container to write to a shared volume using your host UID, add the `--userns=keep-id` option.

To be able to build images within a nested container, mount a volume at the storage directory, e.g. `--tmpfs /podman/.local/share/containers/storage:mode=1777`.
(This is because fuse-overlayfs file systems cannot be nested.)

If you want the nested containers to run with stronger isolation, you must use the regular (non-minimal) podman image and sacrifice the outer container's isolation by running it in `--privileged` mode:
```sh
docker run --privileged -u podman:podman mgoltzsche/podman:latest docker run alpine:latest echo hello from nested container
```

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

_If you have docker installed on the same host it might be broken until you remove the newly installed `/usr/local/bin/runc` binary since older docker versions may not be compatible with the latest runc version provided here._

To install podman on a host without having any root privileges, you need to copy the binaries and configuration into your home directory and adjust the binary paths within the configuration correspondingly.
For more information see [podman's rootless installation instructions](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/rootless_tutorial.md).

### Host configuration

#### Additional binaries

The following binaries should be installed on your host:
* `nftables` (with `iptables-nft` wrapper if `iptables` compatibility is needed)
* `nsenter`
* `shadow` / `shadow-utils` providing `newuidmap` and `newgidmap` (for rootless mode, package `uidmap` on Debian/Ubuntu)  

#### UID/GID mapping

In order to run rootless containers that use multiple uids/gids you may want to set up a uid/gid mapping for your user on your host:
```sh
sudo sh -c "echo $(id -un):100000:200000 >> /etc/subuid"
sudo sh -c "echo $(id -gn):100000:200000 >> /etc/subgid"
```
_Please make sure you don't add the mapping multiple times._  

#### apparmor profile

On an apparmor-enabled host such as Ubuntu >=23.10, podman may fail with `reexec: Permission denied` the first time it is run.
In that case you have to change your podman apparmor profile at `/etc/apparmor.d/podman` so that it also applies to `/usr/local/bin/podman` as follows (also see [here](https://github.com/podman-container-tools/podman/issues/24642#issuecomment-2582629496)):
```sh
sudo sed -Ei 's!^profile podman /usr/bin/podman !profile podman /usr/{bin,local/bin}/podman !' /etc/apparmor.d/podman
```

#### docker link

To support applications that rely on the `docker` command, a quick option is to link `podman` as follows:
```sh
sudo ln -s /usr/local/bin/podman /usr/local/bin/docker
```

Before updating binaries on your host please terminate all corresponding processes.  

#### Restart containers on boot

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

## Binary uninstallation

Before uninstalling the binaries, you may remove containers, pods, images, volumes, and so on to free up space:

```sh
sudo podman system reset
```

Next, remove all the copied binaries and support files from the following folders:

```sh
sudo rm -rf /etc/containers/*
sudo rm -rf /usr/local/bin/{crun,fuse-overlayfs,fusermount3,pasta,pasta.avx2,podman,runc}
sudo rm -rf /usr/local/{lib,libexec}/podman
sudo rm -rf /usr/local/lib/systemd/{system,user}/{netavark,podman}*
sudo rm /usr/local/lib/systemd/{system,user}-generators/podman-*-generator
sudo rm /usr/local/share/{bash-completion/completions/podman,zsh/site-functions/_podman,fish/vendor_completions.d/podman.fish}
```
