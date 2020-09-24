# runc
FROM docker.io/library/golang:1.14-alpine3.12 AS runc
ARG RUNC_VERSION=v1.0.0-rc91
RUN set -eux; \
	apk add --no-cache --virtual .build-deps gcc musl-dev libseccomp-dev make git bash; \
	git clone --branch ${RUNC_VERSION} https://github.com/opencontainers/runc src/github.com/opencontainers/runc; \
	cd src/github.com/opencontainers/runc; \
	make static BUILDTAGS='seccomp selinux ambient'; \
	mv runc /usr/local/bin/runc; \
	rm -rf $GOPATH/src/github.com/opencontainers/runc; \
	apk del --purge .build-deps; \
	[ "$(ldd /usr/local/bin/runc | wc -l)" -eq 0 ] || (ldd /usr/local/bin/runc; false)


# podman build base
FROM docker.io/library/golang:1.14-alpine3.12 AS podmanbuildbase
RUN apk add --update --no-cache git make gcc pkgconf musl-dev \
	btrfs-progs btrfs-progs-dev libassuan-dev lvm2-dev device-mapper \
	glib-static libc-dev gpgme-dev protobuf-dev protobuf-c-dev \
	libseccomp-dev libselinux-dev ostree-dev openssl iptables bash \
	go-md2man


# podman (without systemd support)
FROM podmanbuildbase AS podman
RUN apk add --update --no-cache curl
ARG PODMAN_VERSION=v2.0.4
RUN git clone --branch ${PODMAN_VERSION} https://github.com/containers/podman src/github.com/containers/podman
WORKDIR $GOPATH/src/github.com/containers/podman
RUN make install.tools
RUN set -eux; \
	make bin/podman LDFLAGS_PODMAN="-s -w -extldflags '-static'" BUILDTAGS='seccomp selinux apparmor exclude_graphdriver_devicemapper containers_image_ostree_stub containers_image_openpgp'; \
	mv bin/podman /usr/local/bin/podman; \
	podman --help >/dev/null; \
	[ "$(ldd /usr/local/bin/podman | wc -l)" -eq 0 ] || (ldd /usr/local/bin/podman; false)


# conmon (without systemd support)
FROM podmanbuildbase AS conmon
# conmon 2.0.19 cannot be built currently since alpine does not provide nix package yet
ARG CONMON_VERSION=v2.0.18
RUN git clone --branch ${CONMON_VERSION} https://github.com/containers/conmon.git /conmon
WORKDIR /conmon
RUN set -eux; \
	make static; \
	bin/conmon --help >/dev/null


# CNI plugins
FROM podmanbuildbase AS cniplugins
ARG CNI_PLUGIN_VERSION=v0.8.5
RUN git clone --branch=${CNI_PLUGIN_VERSION} https://github.com/containernetworking/plugins /go/src/github.com/containernetworking/plugins
WORKDIR /go/src/github.com/containernetworking/plugins
RUN set -ex; \
	for PLUGINDIR in plugins/ipam/host-local plugins/main/loopback plugins/main/bridge plugins/meta/portmap plugins/meta/firewall plugins/meta/tuning; do \
		PLUGINBIN=/usr/libexec/cni/$(basename $PLUGINDIR); \
		CGO_ENABLED=0 go build -o $PLUGINBIN -ldflags "-s -w -extldflags '-static'" ./$PLUGINDIR; \
		[ "$(ldd $PLUGINBIN | grep -Ev '^\s+ldd \(0x[0-9a-f]+\)$' | wc -l)" -eq 0 ] || (ldd $PLUGINBIN; false); \
	done


# slirp4netns
FROM podmanbuildbase AS slirp4netns
WORKDIR /
RUN apk add --update --no-cache autoconf automake meson ninja linux-headers libcap-static libcap-dev
# Build libslirp
ARG LIBSLIRP_VERSION=v4.3.1
RUN git clone --branch=${LIBSLIRP_VERSION} https://gitlab.freedesktop.org/slirp/libslirp.git
WORKDIR /libslirp
RUN set -ex; \
	LDFLAGS="-s -w -static" meson --prefix /usr -D default_library=static build; \
	ninja -C build install
# Build slirp4netns
WORKDIR /
ARG SLIRP4NETNS_VERSION=v1.1.4
RUN git clone --branch $SLIRP4NETNS_VERSION https://github.com/rootless-containers/slirp4netns.git
WORKDIR /slirp4netns
RUN set -eux; \
	./autogen.sh; \
	LDFLAGS=-static ./configure --prefix=/usr; \
	make


# fuse-overlayfs (derived from https://github.com/containers/fuse-overlayfs/blob/master/Dockerfile.static)
FROM podmanbuildbase AS fuse-overlayfs
RUN apk add --update --no-cache autoconf automake meson ninja clang g++ eudev-dev fuse3-dev
ARG LIBFUSE_VERSION=fuse-3.9.1
RUN git clone --branch=${LIBFUSE_VERSION} https://github.com/libfuse/libfuse /libfuse
WORKDIR /libfuse
RUN set -eux; \
	mkdir build; \
	cd build; \
	LDFLAGS="-lpthread -s -w -static" meson --prefix /usr -D default_library=static .. || (cat /libfuse/build/meson-logs/meson-log.txt; false); \
	ninja; \
	ninja install; \
	fusermount3 -V
# Requires version >1.1.2 with fix for https://github.com/containers/fuse-overlayfs/issues/174
ARG FUSEOVERLAYFS_VERSION=421c64db788688469a6c41e14dddce22fefc26ed
RUN git clone https://github.com/containers/fuse-overlayfs /fuse-overlayfs \
	&& cd /fuse-overlayfs \
	&& git checkout ${FUSEOVERLAYFS_VERSION}
WORKDIR /fuse-overlayfs
RUN set -eux; \
	sh autogen.sh; \
	LIBS="-ldl" LDFLAGS="-s -w -static" ./configure --prefix /usr; \
	make; \
	make install; \
	fuse-overlayfs --help >/dev/null

# Download gosu
FROM docker.io/library/alpine:3.12 AS downloads
RUN apk add --no-cache gnupg
ARG GOSU_VERSION=1.11
RUN set -eux; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64"; \
	wget -O /tmp/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64.asc"; \
	gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /tmp/gosu.asc /usr/local/bin/gosu; \
	chmod +x /usr/local/bin/gosu; \
	gosu nobody true


# Build final image
FROM docker.io/library/alpine:3.12
LABEL maintainer="Max Goltzsche <max.goltzsche@gmail.com>"
# Install iptables & new-uidmap
RUN apk add --no-cache ca-certificates iptables ip6tables shadow-uidmap
# Copy binaries from other images
COPY --from=conmon /conmon/bin/conmon /usr/libexec/podman/conmon
COPY --from=cniplugins /usr/libexec/cni /usr/libexec/cni
COPY --from=fuse-overlayfs /usr/bin/fuse-overlayfs /usr/local/bin/fuse-overlayfs
COPY --from=fuse-overlayfs /usr/bin/fusermount3 /usr/local/bin/fusermount3
COPY --from=slirp4netns /slirp4netns/slirp4netns /usr/local/bin/slirp4netns
COPY --from=podman /go/src/github.com/containers/podman/cni/87-podman-bridge.conflist /etc/cni/net.d/
COPY --from=podman /usr/local/bin/podman /usr/local/bin/podman
COPY --from=downloads /usr/local/bin/gosu /usr/local/bin/gosu
COPY --from=runc   /usr/local/bin/runc   /usr/local/bin/runc
COPY containers.conf storage.conf /etc/containers/
RUN set -eux; \
	adduser -D podman -h /podman -u 100000; \
	echo 'podman:100001:65536' > /etc/subuid; \
	echo 'podman:100001:65536' > /etc/subgid; \
	ln -s /usr/local/bin/podman /usr/bin/docker; \
	mkdir -pm 775 /etc/containers /podman/.config/containers /etc/cni/net.d /podman/.local/share/containers/storage; \
	cp /etc/containers/containers.conf /podman/.config/containers/; \
	chown -R podman:podman /podman; \
	wget -O /etc/containers/registries.conf https://raw.githubusercontent.com/projectatomic/registries/master/registries.fedora; \
	wget -O /etc/containers/policy.json     https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json; \
	runc --help >/dev/null; \
	podman --help >/dev/null; \
	/usr/libexec/podman/conmon --help >/dev/null; \
	slirp4netns --help >/dev/null; \
	fuse-overlayfs --help >/dev/null;
COPY entrypoint.sh /
VOLUME /podman/.local/share/containers/storage
WORKDIR /podman
ENV HOME=/podman
ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "sh" ]
