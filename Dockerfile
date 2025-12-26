# Download gpg
FROM alpine:3.22 AS gpg
RUN apk add --no-cache gnupg


# golang build base
FROM golang:1.25-alpine3.22 AS golangbuildbase
RUN apk add --update --no-cache git make gcc pkgconf musl-dev \
	btrfs-progs btrfs-progs-dev libassuan-dev lvm2-dev device-mapper \
	glib-static libc-dev gpgme-dev protobuf-dev protobuf-c-dev \
	libseccomp-dev libseccomp-static libselinux-dev ostree-dev openssl iptables \
	bash go-md2man


# runc
FROM golangbuildbase AS runc
ARG RUNC_VERSION=v1.4.0
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch ${RUNC_VERSION} https://github.com/opencontainers/runc src/github.com/opencontainers/runc
WORKDIR $GOPATH/src/github.com/opencontainers/runc
RUN set -eux; \
	make static EXTRA_LDFLAGS="-s -w"; \
	make install; \
	runc --version; \
	ldd /usr/local/sbin/runc


# podman (without systemd support)
FROM golangbuildbase AS podman
RUN apk add --update --no-cache tzdata curl
ARG PODMAN_VERSION=v5.7.1
ARG PODMAN_BUILDTAGS='seccomp selinux apparmor exclude_graphdriver_devicemapper containers_image_openpgp'
ARG PODMAN_CGO=1
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch ${PODMAN_VERSION} https://github.com/containers/podman src/github.com/containers/podman
WORKDIR $GOPATH/src/github.com/containers/podman
RUN set -eux; \
	COMMON_VERSION=$(grep -Eom1 'github.com/containers/common [^ ]+' go.mod | sed 's!github.com/containers/common !!'); \
	mkdir -p /etc/containers; \
	curl -fsSL "https://raw.githubusercontent.com/containers/common/${COMMON_VERSION}/pkg/seccomp/seccomp.json" > /etc/containers/seccomp.json
RUN set -ex; \
	export CGO_ENABLED=$PODMAN_CGO; \
	make bin/podman LDFLAGS_PODMAN="-s -w -extldflags '-static'" BUILDTAGS='${PODMAN_BUILDTAGS}'; \
	mv bin/podman /usr/local/bin/podman; \
	podman --help >/dev/null; \
	! ldd /usr/local/bin/podman
RUN set -ex; \
# overwrites the default bin directory so quadlet looks for the podman binary in /usr/local/bin
	export LDFLAGS_QUADLET="-X github.com/containers/podman/v5/pkg/systemd/quadlet._binDir=/usr/local/bin"; \
	CGO_ENABLED=0 make bin/quadlet LDFLAGS_PODMAN="-s -w -extldflags '-static' ${LDFLAGS_QUADLET}" BUILDTAGS='${PODMAN_BUILDTAGS}'; \
	mkdir -p /usr/local/libexec/podman; \
	mv bin/quadlet /usr/local/libexec/podman/quadlet; \
	! ldd /usr/local/libexec/podman/quadlet
RUN set -ex; \
	CGO_ENABLED=0 make bin/rootlessport BUILDFLAGS=" -mod=vendor -ldflags=\"-s -w -extldflags '-static'\""; \
	mkdir -p /usr/local/lib/podman; \
	mv bin/rootlessport /usr/local/lib/podman/rootlessport; \
	! ldd /usr/local/lib/podman/rootlessport
# copying completions to /comp instead of /usr/local/share to avoid copying potentially other unwanted stuff in the final stage
RUN set -eux; \
	install -Dm644 -t /comp/bash-completion/completions/ completions/bash/podman; \
	install -Dm644 -t /comp/zsh/site-functions/ completions/zsh/_podman; \
	install -Dm644 -t /comp/fish/vendor_completions.d/ completions/fish/podman.fish


# conmon (without systemd support)
FROM golangbuildbase AS conmon
ARG CONMON_VERSION=v2.1.13
RUN apk add --update --no-cache pcre2-static
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch ${CONMON_VERSION} https://github.com/containers/conmon.git /conmon
WORKDIR /conmon
RUN set -ex; \
	make git-vars bin/conmon PKG_CONFIG='pkg-config --static' CFLAGS='-std=c99 -Os -Wall -Wextra -Werror -static' LDFLAGS='-s -w -static'; \
	bin/conmon --help >/dev/null


FROM rust:1.91-alpine3.22 AS rustbase
RUN apk add --update --no-cache git make musl-dev


# netavark
FROM rustbase AS netavark
RUN apk add --update --no-cache protoc
ARG NETAVARK_VERSION=v1.17.0
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch=$NETAVARK_VERSION https://github.com/containers/netavark
WORKDIR /netavark
ENV RUSTFLAGS='-C link-arg=-s'
RUN cargo build --release


# aardvark-dns
FROM rustbase AS aardvark-dns
ARG AARDVARKDNS_VERSION=v1.17.0
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch=$AARDVARKDNS_VERSION https://github.com/containers/aardvark-dns
WORKDIR /aardvark-dns
ENV RUSTFLAGS='-C link-arg=-s'
RUN cargo build --release


# passt
FROM golangbuildbase AS passt
WORKDIR /
RUN apk add --update --no-cache autoconf automake meson ninja linux-headers libcap-static libcap-dev clang llvm coreutils
ARG PASST_VERSION=2025_12_10.d04c480
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch=$PASST_VERSION git://passt.top/passt
WORKDIR /passt
RUN set -ex; \
	make static; \
	mkdir bin; \
	cp pasta bin/; \
	[ ! -f pasta.avx2 ] || cp pasta.avx2 bin/; \
	! ldd /passt/bin/pasta


# fuse-overlayfs (derived from https://github.com/containers/fuse-overlayfs/blob/master/Dockerfile.static)
FROM golangbuildbase AS fuse-overlayfs
RUN apk add --update --no-cache autoconf automake meson ninja clang g++ eudev-dev fuse3-dev
ARG LIBFUSE_VERSION=fuse-3.17.4
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch=$LIBFUSE_VERSION https://github.com/libfuse/libfuse /libfuse
WORKDIR /libfuse
RUN set -ex; \
	mkdir build; \
	cd build; \
	LDFLAGS="-lpthread -s -w -static" meson --prefix /usr -D default_library=static -D examples=false .. || (cat /libfuse/build/meson-logs/meson-log.txt; false); \
	ninja; \
	touch /dev/fuse; \
	ninja install; \
	fusermount3 -V
ARG FUSEOVERLAYFS_VERSION=v1.16
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch=$FUSEOVERLAYFS_VERSION https://github.com/containers/fuse-overlayfs /fuse-overlayfs
WORKDIR /fuse-overlayfs
RUN set -ex; \
	sh autogen.sh; \
	LIBS="-ldl" LDFLAGS="-s -w -static" ./configure --prefix /usr; \
	make; \
	make install; \
	fuse-overlayfs --help >/dev/null


# catatonit
FROM golangbuildbase AS catatonit
RUN apk add --update --no-cache autoconf automake libtool
ARG CATATONIT_VERSION=v0.2.1
RUN git clone -c 'advice.detachedHead=false' --branch=$CATATONIT_VERSION https://github.com/openSUSE/catatonit.git /catatonit
WORKDIR /catatonit
RUN set -ex; \
	./autogen.sh; \
	./configure LDFLAGS="-static" --prefix=/ --bindir=/bin; \
	make; \
	./catatonit --version


# crun
FROM golangbuildbase AS crun
RUN apk add --update --no-cache autoconf automake argp-standalone libtool libcap-dev libcap-static
ARG CRUN_VERSION=1.25.1
RUN git clone -c 'advice.detachedHead=false' --depth=1 --branch ${CRUN_VERSION} https://github.com/containers/crun src/github.com/containers/crun
WORKDIR $GOPATH/src/github.com/containers/crun
RUN set -ex; \
	./autogen.sh; \
	./configure --disable-systemd --enable-embedded-yajl; \
	make LDFLAGS='-static-libgcc -all-static' EXTRA_LDFLAGS='-s -w'; \
	make install; \
	! ldd /usr/local/bin/crun


# Build podman base image
FROM alpine:3.22 AS podmanbase
LABEL maintainer="Max Goltzsche <max.goltzsche@gmail.com>"
RUN apk add --no-cache tzdata ca-certificates
COPY --from=conmon /conmon/bin/conmon /usr/local/lib/podman/conmon
COPY --from=podman /usr/local/lib/podman/rootlessport /usr/local/lib/podman/rootlessport
COPY --from=podman /usr/local/bin/podman /usr/local/bin/podman
COPY --from=podman /comp /usr/local/share
COPY --from=passt /passt/bin/ /usr/local/bin/
COPY --from=netavark /netavark/target/release/netavark /usr/local/lib/podman/netavark
COPY conf/containers /etc/containers
RUN set -ex; \
	adduser -D podman -h /podman -u 1000; \
	echo 'podman:1:999' > /etc/subuid; \
	echo 'podman:1001:64535' >> /etc/subuid; \
	cp /etc/subuid /etc/subgid; \
	ln -s /usr/local/bin/podman /usr/bin/docker; \
	mkdir -p /podman/.local/share/containers/storage /var/lib/containers/storage; \
	chown -R podman:podman /podman; \
	mkdir -m1777 /.local /.config /.cache; \
	podman --help >/dev/null; \
	/usr/local/lib/podman/conmon --help >/dev/null
ENV _CONTAINERS_USERNS_CONFIGURED=""

# Build rootless podman base image (without OCI runtime)
FROM podmanbase AS rootlesspodmanbase
ENV BUILDAH_ISOLATION=chroot container=oci
RUN apk add --no-cache shadow-uidmap
COPY --from=fuse-overlayfs /usr/bin/fuse-overlayfs /usr/local/bin/fuse-overlayfs
COPY --from=fuse-overlayfs /usr/bin/fusermount3 /usr/local/bin/fusermount3
COPY --from=crun /usr/local/bin/crun /usr/local/bin/crun

# Build minimal rootless podman
FROM rootlesspodmanbase AS rootlesspodmanminimal
COPY conf/crun-containers.conf /etc/containers/containers.conf

# Build podman image with all binaries
FROM rootlesspodmanbase AS podmanall
RUN apk add --no-cache iptables ip6tables
COPY --from=catatonit /catatonit/catatonit /usr/local/lib/podman/catatonit
COPY --from=runc   /usr/local/sbin/runc   /usr/local/bin/runc
COPY --from=aardvark-dns /aardvark-dns/target/release/aardvark-dns /usr/local/lib/podman/aardvark-dns
COPY --from=podman /etc/containers/seccomp.json /etc/containers/seccomp.json

FROM podmanall AS tar-archive
COPY --from=podman /usr/local/libexec/podman/quadlet /usr/local/libexec/podman/quadlet

FROM podmanall
