# global version parameters
ARG ALPINE_VERSION=3.22
ARG GOLANG_VERSION=1.25.1-alpine3.22
ARG RUST_VERSION=1.89-alpine3.22

# component versions
ARG PODMAN_VERSION=v5.6.1
ARG CRUN_VERSION=1.23.1
ARG RUNC_VERSION=v1.3.1
ARG CONMON_VERSION=v2.1.13
ARG NETAVARK_VERSION=v1.16.1
ARG AARDVARKDNS_VERSION=v1.16.0
ARG PASST_VERSION=2025_08_05.309eefd
ARG FUSEOVERLAYFS_VERSION=v1.15
ARG LIBFUSE_VERSION=fuse-3.16.2
ARG CATATONIT_VERSION=v0.2.1

# build parameters
ARG JOBS=1
ARG PODMAN_BUILDTAGS='seccomp selinux apparmor exclude_graphdriver_devicemapper containers_image_openpgp'
ARG RUNC_DOWNLOAD=1
ARG CRUN_DOWNLOAD=1

# build base for go
FROM golang:${GOLANG_VERSION} AS buildbase_go
RUN apk add --update --no-cache \
    libcap-dev libcap-static libc-dev libseccomp-dev libseccomp-static libselinux-dev \
    argp-standalone autoconf automake bash btrfs-progs btrfs-progs-dev clang coreutils \
    curl device-mapper eudev-dev fuse3-dev g++ git glib-static go-md2man gpgme-dev \
    gcc iptables linux-headers libtool llvm libassuan-dev lvm2-dev make meson musl-dev \
    ninja ostree-dev openssl pkgconf pcre2-static protobuf-c-dev protobuf-dev \
    shadow-uidmap tzdata

# build base for rust
FROM rust:${RUST_VERSION} AS buildbase_rust
RUN apk add --update --no-cache git make musl-dev protobuf-c-dev protobuf-dev

# download or build runc (Position Independent Executable)
FROM buildbase_go AS runc
ARG JOBS
ARG RUNC_VERSION
ARG RUNC_DOWNLOAD
RUN set -ex; \
    if [ "$RUNC_DOWNLOAD" -eq 1 ]; then \
        ARCH="$(uname -m)"; \
        if [ "$ARCH" = "x86_64" ]; then \
            curl -RL --create-dirs -o /runc/runc https://github.com/opencontainers/runc/releases/download/"$RUNC_VERSION"/runc.amd64; \
        elif [ "$ARCH" = "aarch64" ]; then \
            curl -RL --create-dirs -o /runc/runc https://github.com/opencontainers/runc/releases/download/"$RUNC_VERSION"/runc.arm64; \
        else \
            echo "Unsupported architecture $ARCH" && exit 1; \
        fi && \
        chmod +x /runc/runc; \
    else \
        git clone -c 'advice.detachedHead=false' --depth=1 --branch="$RUNC_VERSION" https://github.com/opencontainers/runc /runc && \
        cd /runc && \
        CGO_ENABLED=1 make -j "$JOBS" static-bin EXTRA_LDFLAGS="-s -w"; \
    fi && \
    cd /runc && \
    ./runc --version >/dev/null;

# build runc (classic static binary)
FROM buildbase_go AS runc_classic
ARG JOBS
ARG RUNC_VERSION
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$RUNC_VERSION" https://github.com/opencontainers/runc /runc
WORKDIR /runc
RUN set -ex; \
    CGO_ENABLED=1 make -j "$JOBS" static-bin EXTRA_LDFLAGS="-extldflags=-static -s -w" && \
    ./runc --version >/dev/null && \
    ! ldd ./runc >/dev/null 2>&1;

# build crun
FROM buildbase_go AS crun
ARG JOBS
ARG CRUN_VERSION
ARG CRUN_DOWNLOAD
RUN set -ex; \
    if [ "$CRUN_DOWNLOAD" -eq 1 ]; then \
        ARCH="$(uname -m)"; \
        if [ "$ARCH" = "x86_64" ]; then \
            curl -RL --create-dirs -o /crun/crun https://github.com/containers/crun/releases/download/"$CRUN_VERSION"/crun-"$CRUN_VERSION"-linux-amd64-disable-systemd; \
        elif [ "$ARCH" = "aarch64" ]; then \
            curl -RL --create-dirs -o /crun/crun https://github.com/containers/crun/releases/download/"$CRUN_VERSION"/crun-"$CRUN_VERSION"-linux-arm64-disable-systemd; \
        else \
            echo "Unsupported architecture $ARCH" && exit 1; \
        fi && \
        cd /crun && \
        chmod +x crun; \
    else \
        git clone -c 'advice.detachedHead=false' --depth=1 --branch="$CRUN_VERSION" https://github.com/containers/crun /crun && \
        cd /crun && \
        ./autogen.sh && \
        ./configure --disable-systemd --enable-embedded-yajl && \
        make -j "$JOBS" LDFLAGS="-static-libgcc -all-static"; \
    fi && \
    ./crun --version && \
    ! ldd ./crun >/dev/null 2>&1;

# build podman
FROM buildbase_go AS podman
ARG JOBS
ARG PODMAN_VERSION
ARG PODMAN_BUILDTAGS
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch "$PODMAN_VERSION" https://github.com/containers/podman /podman
WORKDIR /podman
RUN set -ex; \
    mkdir -p /etc/containers && cp -a vendor/github.com/containers/common/pkg/seccomp/seccomp.json /etc/containers/seccomp.json && \
    CGO_ENABLED=1 make -j "$JOBS" bin/podman LDFLAGS_PODMAN="-s -w -extldflags=-static" BUILDTAGS="$PODMAN_BUILDTAGS" && \
    ! ldd bin/podman >/dev/null 2>&1 && \
    CGO_ENABLED=0 make -j "$JOBS" bin/quadlet LDFLAGS_PODMAN="-s -w -extldflags=-static" BUILDTAGS="$PODMAN_BUILDTAGS" && \
    ! ldd bin/quadlet >/dev/null 2>&1 && \
    CGO_ENABLED=0 make -j "$JOBS" bin/rootlessport LDFLAGS_PODMAN="-s -w -extldflags=-static" BUILDFLAGS="-mod=vendor" && \
    ! ldd bin/rootlessport >/dev/null 2>&1 && \
    strip bin/rootlessport;

# build conmon
FROM buildbase_go AS conmon
ARG JOBS
ARG CONMON_VERSION
RUN git clone -c advice.detachedHead=false --depth=1 --branch "$CONMON_VERSION" https://github.com/containers/conmon /conmon
WORKDIR /conmon
RUN set -ex; \
    make -j "$JOBS" LDFLAGS='-s -w -static' && \
    bin/conmon --help >/dev/null;

# build netavark
FROM buildbase_rust AS netavark
ARG JOBS
ARG NETAVARK_VERSION
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$NETAVARK_VERSION" https://github.com/containers/netavark /netavark
WORKDIR /netavark
RUN RUSTFLAGS="-C link-arg=-Wl,-s" cargo build -j "$JOBS" --release

# build aardvark-dns
FROM buildbase_rust AS aardvark-dns
ARG JOBS
ARG AARDVARKDNS_VERSION
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$AARDVARKDNS_VERSION" https://github.com/containers/aardvark-dns /aardvark-dns
WORKDIR /aardvark-dns
RUN RUSTFLAGS="-C link-arg=-Wl,-s" cargo build -j "$JOBS" --release

# build passt
FROM buildbase_go AS passt
ARG JOBS
ARG PASST_VERSION
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$PASST_VERSION" https://passt.top/passt /passt
WORKDIR /passt
RUN set -ex; \
    make -j "$JOBS" LDFLAGS="-s -w -static" && \
    make install && \
    ! ldd /usr/local/bin/passt >/dev/null 2>&1;

# build fuse-overlayfs
FROM buildbase_go AS fuse-overlayfs
ARG JOBS
ARG LIBFUSE_VERSION
ARG FUSEOVERLAYFS_VERSION

RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$LIBFUSE_VERSION" https://github.com/libfuse/libfuse /libfuse
WORKDIR /libfuse
RUN set -ex; \
    mkdir build && cd build && \
    LDFLAGS="-lpthread -s -w -static" meson setup -Ddefault_library=static .. && \
    ninja -j "$JOBS" && \
    mkdir -p /dev/fuse && \
    ninja install && \
    fusermount3 -V >/dev/null && \
    ! ldd /usr/local/bin/fusermount3 >/dev/null 2>&1;

RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch="$FUSEOVERLAYFS_VERSION" https://github.com/containers/fuse-overlayfs /fuse-overlayfs
WORKDIR /fuse-overlayfs
RUN set -ex; \
    ./autogen.sh && \
    ./configure && \
    make -j "$JOBS" CFLAGS="-Wno-format" LDFLAGS="-s -w -static" && \
    ./fuse-overlayfs --help >/dev/null && \
    ! ldd ./fuse-overlayfs >/dev/null 2>&1;

# build catatonit
FROM buildbase_go AS catatonit
ARG JOBS
ARG CATATONIT_VERSION
RUN git clone -c 'advice.detachedHead=false' --branch="$CATATONIT_VERSION" https://github.com/openSUSE/catatonit /catatonit
WORKDIR /catatonit
RUN set -ex; \
    ./autogen.sh && \
    ./configure --prefix=/ --bindir=/bin && \
    make -j "$JOBS" LDFLAGS="-s -w -static" && \
    ./catatonit --version >/dev/null && \
    ! ldd ./catatonit >/dev/null 2>&1;

# build podman base image
FROM alpine:${ALPINE_VERSION} AS podmanbase
LABEL maintainer="Max Goltzsche <max.goltzsche@gmail.com>"

RUN set -ex; \
    apk add --no-cache tzdata ca-certificates && \
    adduser -D podman -h /podman -u 1000 && \
    echo 'podman:1:999' > /etc/subuid && \
    echo 'podman:1001:64535' >> /etc/subuid && \
    cp /etc/subuid /etc/subgid && \
    mkdir -p -m1777 /podman/.local /podman/.config /podman/.cache && \
    mkdir -p -m1777 /podman/.local/share/containers/storage /var/lib/containers/storage && \
    chown -R podman:podman /podman && \
    cd /usr/local/bin/ && cp -s podman docker;

COPY conf/containers /etc/containers
COPY --from=conmon /conmon/bin/conmon /usr/local/lib/podman/conmon
COPY --from=podman /podman/bin/rootlessport /usr/local/lib/podman/rootlessport
COPY --from=podman /podman/bin/podman /usr/local/bin/podman
COPY --from=passt /usr/local/bin/ /usr/local/bin/
COPY --from=netavark /netavark/target/release/netavark /usr/local/lib/podman/netavark

RUN set -ex; \
    /usr/local/bin/podman --help >/dev/null && \
    /usr/local/lib/podman/conmon --help >/dev/null;
ENV _CONTAINERS_USERNS_CONFIGURED=""

# build rootless podman base
FROM podmanbase AS rootlesspodmanbase
ENV BUILDAH_ISOLATION=chroot container=oci
RUN apk add --no-cache shadow-uidmap
COPY --from=fuse-overlayfs /usr/local/bin/fusermount3 /usr/local/bin/fusermount3
COPY --from=fuse-overlayfs /fuse-overlayfs/fuse-overlayfs /usr/local/bin/fuse-overlayfs
COPY --from=crun /crun/crun /usr/local/bin/crun

# build minimal rootless podman
FROM rootlesspodmanbase AS rootlesspodmanminimal
COPY conf/crun-containers.conf /etc/containers/containers.conf

# build podman with all binaries
FROM rootlesspodmanbase AS podmanall
RUN apk add --no-cache iptables ip6tables
COPY --from=runc /runc/runc /usr/local/bin/runc
COPY --from=catatonit /catatonit/catatonit /usr/local/lib/podman/catatonit
COPY --from=netavark /netavark/target/release/netavark-dhcp-proxy-client /usr/local/lib/podman/netavark-dhcp-proxy-client
COPY --from=aardvark-dns /aardvark-dns/target/release/aardvark-dns /usr/local/lib/podman/aardvark-dns
COPY --from=podman /etc/containers/seccomp.json /etc/containers/seccomp.json

FROM podmanall AS tar-archive
COPY --from=podman /podman/bin/quadlet /usr/local/libexec/podman/quadlet

FROM podmanall
