# runc
FROM golang:alpine3.8 AS runc
ARG RUNC_VERSION=v1.0.0-rc6
RUN set -eux; \
	apk add --no-cache --virtual .build-deps gcc musl-dev libseccomp-dev make git bash; \
	git clone --branch ${RUNC_VERSION} https://github.com/opencontainers/runc src/github.com/opencontainers/runc; \
	cd src/github.com/opencontainers/runc; \
	make static BUILDTAGS='seccomp selinux ambient'; \
	mv runc /usr/local/bin/runc; \
	rm -rf $GOPATH/src/github.com/opencontainers/runc; \
	apk del --purge .build-deps


# Golang build against musl libc (since libselinux is available in alpine >3.8; build like the official golang:alpine3.8 image)
FROM alpine:3.9 as golang
ENV GOLANG_VERSION 1.11.5
# Compile go against musl libc (see https://github.com/docker-library/golang/blob/2e795f515357c575359f0720acaf7f5490f8bcf5/1.11/alpine3.8/Dockerfile)
RUN set -eux; \
	mkdir /go; \
	apk add --no-cache --virtual .build-deps bash gcc musl-dev openssl ca-certificates go; \
	export \
# set GOROOT_BOOTSTRAP such that we can actually build Go
		GOROOT_BOOTSTRAP="$(go env GOROOT)" \
# ... and set "cross-building" related vars to the installed system's values so that we create a build targeting the proper arch
# (for example, if our build host is GOARCH=amd64, but our build env/image is GOARCH=386, our build needs GOARCH=386)
		GOOS="$(go env GOOS)" \
		GOARCH="$(go env GOARCH)" \
		GOHOSTOS="$(go env GOHOSTOS)" \
		GOHOSTARCH="$(go env GOHOSTARCH)" \
	; \
# also explicitly set GO386 and GOARM if appropriate
# https://github.com/docker-library/golang/issues/184
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		armhf) export GOARM='6' ;; \
		x86) export GO386='387' ;; \
	esac; \
	\
	wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz"; \
	echo 'bc1ef02bb1668835db1390a2e478dcbccb5dd16911691af9d75184bbe5aa943e *go.tgz' | sha256sum -c -; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	cd /usr/local/go/src; \
	./make.bash; \
	\
	rm -rf \
# https://github.com/golang/go/blob/0b30cf534a03618162d3015c8705dd2231e34703/src/cmd/dist/buildtool.go#L121-L125
		/usr/local/go/pkg/bootstrap \
# https://golang.org/cl/82095
# https://github.com/golang/build/blob/e3fe1605c30f6a3fd136b561569933312ede8782/cmd/release/releaselet.go#L56
		/usr/local/go/pkg/obj \
	; \
	apk del .build-deps; \
	export PATH="/usr/local/go/bin:$PATH"; \
	go version
ENV GOROOT=/usr/local/go GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
WORKDIR /go


# podman build base
FROM golang AS podmanbuildbase
RUN apk add --update --no-cache git make gcc pkgconf musl-dev btrfs-progs btrfs-progs-dev libassuan-dev lvm2-dev device-mapper glib-dev glib-static libc-dev gpgme-dev protobuf-dev protobuf-c-dev libseccomp-dev libselinux-dev ostree-dev openssl iptables bash


# podman
FROM podmanbuildbase AS podman
ARG PODMAN_VERSION=v1.0.0
RUN git clone --branch ${PODMAN_VERSION} https://github.com/containers/libpod src/github.com/containers/libpod
WORKDIR $GOPATH/src/github.com/containers/libpod
RUN make install.tools
RUN set -eux; \
	make LDFLAGS="-w -extldflags '-static'" BUILDTAGS='seccomp selinux varlink exclude_graphdriver_devicemapper containers_image_ostree_stub containers_image_openpgp'; \
	mv bin/podman /usr/local/bin/podman


# conmon
FROM podmanbuildbase AS conmon
ARG CRIO_VERSION=v1.13.0
WORKDIR $GOPATH
RUN git clone --branch ${CRIO_VERSION} https://github.com/kubernetes-sigs/cri-o $GOPATH/src/github.com/kubernetes-sigs/cri-o
WORKDIR $GOPATH/src/github.com/kubernetes-sigs/cri-o
RUN set -eux; \
	mkdir bin; \
	make bin/conmon CFLAGS='-std=c99 -Os -Wall -Wextra -static'; \
	install -D -m 755 bin/conmon /usr/libexec/podman/conmon


# CNI plugins
FROM podmanbuildbase AS cniplugins
ARG CNI_VERSION=0.6.0
RUN set -eux; \
	mkdir -p "${GOPATH}/src/github.com/containernetworking"; \
	wget -O - "https://github.com/containernetworking/plugins/archive/v${CNI_VERSION}.tar.gz" | tar -xzf - -C /tmp; \
	mv "/tmp/plugins-${CNI_VERSION}" "${GOPATH}/src/github.com/containernetworking/plugins"; \
	for TYPE in main ipam meta; do \
		for CNIPLUGIN in `ls ${GOPATH}/src/github.com/containernetworking/plugins/plugins/$TYPE`; do \
			go build -o /usr/libexec/cni/$CNIPLUGIN -ldflags "-extldflags '-static'" github.com/containernetworking/plugins/plugins/$TYPE/$CNIPLUGIN; \
		done \
	done


# skopeo
FROM podmanbuildbase AS skopeo
ARG SKOPEO_VERSION=v0.1.32
RUN git clone --branch ${SKOPEO_VERSION} https://github.com/containers/skopeo $GOPATH/src/github.com/containers/skopeo
WORKDIR $GOPATH/src/github.com/containers/skopeo
RUN go build -ldflags "-extldflags '-static'" -tags "exclude_graphdriver_devicemapper containers_image_ostree_stub containers_image_openpgp" \
	github.com/containers/skopeo/cmd/skopeo && \
	mv skopeo /usr/local/bin/skopeo


# fuse-overlay (taken from https://github.com/containers/fuse-overlayfs/blob/master/Dockerfile.static)
FROM fedora:29 AS fuse-overlayfs
WORKDIR /build
RUN dnf update -y && \
	dnf install -y git make automake autoconf gcc glibc-static meson ninja-build
ARG LIBFUSE_VERSION=fuse-3.4.1
RUN git clone --branch=${LIBFUSE_VERSION} https://github.com/libfuse/libfuse
WORKDIR libfuse
RUN set -eux; \
	mkdir build && \
	cd build && \
	LDFLAGS="-lpthread" meson --prefix /usr -D default_library=static .. && \
	ninja && \
	ninja install
#LDFLAGS="-lpthread" meson --prefix /usr -D default_library=static .. && \
ARG FUSEOVERLAYFS_VERSION=v0.3
RUN git clone --branch ${FUSEOVERLAYFS_VERSION} https://github.com/containers/fuse-overlayfs && \
	cd fuse-overlayfs && \
	sh autogen.sh && \
	LIBS="-ldl" LDFLAGS="-static" ./configure --prefix /usr && \
	make && \
	make install
USER 1000
ENTRYPOINT ["/usr/bin/fuse-overlayfs","-f"]


FROM alpine:3.9
RUN apk add --no-cache ca-certificates iptables ip6tables
COPY --from=runc   /usr/local/bin/runc   /usr/bin/runc
COPY --from=podman /usr/local/bin/podman /usr/bin/podman
COPY --from=conmon /usr/libexec/podman/conmon /usr/libexec/podman/conmon
COPY --from=cniplugins /usr/libexec/cni /usr/libexec/cni
COPY --from=skopeo /usr/local/bin/skopeo /usr/bin/skopeo
COPY --from=fuse-overlayfs /usr/bin/fuse-overlayfs /usr/bin/fuse-overlayfs
RUN set -eux; \
	echo 'nobody:65534:65534' > /etc/subuid; \
	echo 'nobody:65534:65534' > /etc/subgid; \
	ln -s /usr/bin/podman /usr/bin/docker; \
	mkdir -pm 775 /storage /etc/containers /.config/containers /etc/cni/net.d /.local/share/containers/storage/libpod; \
	chown root:nobody /storage /.local/share/containers/storage/libpod; \
	wget -O /etc/containers/registries.conf https://raw.githubusercontent.com/projectatomic/registries/master/registries.fedora; \
	wget -O /etc/containers/policy.json     https://raw.githubusercontent.com/containers/skopeo/master/default-policy.json; \
	wget -O /etc/cni/net.d/99-bridge.conflist https://raw.githubusercontent.com/containers/libpod/master/cni/87-podman-bridge.conflist
COPY ./rootless-storage.conf /.config/containers/storage.conf



# TODO: add buildah

# docker run -ti --rm --name podman --privileged -u nobody:nobody -v storage:/var/lib/containers/storage runc /bin/sh
# BUG: https://github.com/containers/libpod/issues/2231
