PODMAN_IMAGE_NAME ?= mgoltzsche/podman
PODMAN_IMAGE ?= $(PODMAN_IMAGE_NAME):latest
PODMAN_IMAGE_TARGET ?= podmanall
PODMAN_MINIMAL_IMAGE ?= $(PODMAN_IMAGE)-minimal
PODMAN_REMOTE_IMAGE ?= $(PODMAN_IMAGE)-remote
PODMAN_SSH_IMAGE ?= mgoltzsche/podman-ssh
PODMAN_BUILD_OPTS ?= -t $(PODMAN_IMAGE)
PODMAN_MINIMAL_BUILD_OPTS ?= -t $(PODMAN_MINIMAL_IMAGE)
PODMAN_REMOTE_BUILD_OPTS ?= -t $(PODMAN_REMOTE_IMAGE)

GPG_IMAGE = gpg-signer

BUILD_DIR = ./build

BATS_VERSION = v1.11.0
BATS_DIR := $(BUILD_DIR)/bats-$(BATS_VERSION)
BATS = $(BATS_DIR)/bin/bats
BATS_TEST ?= test

# TODO: Make the tests work with podman in podman (GitHub's workflow runner also supports podman)
#DOCKER ?= $(if $(shell podman -v),podman,docker)
DOCKER ?= docker
export DOCKER
PLATFORM ?= linux/amd64
ARCH = $(shell echo "$(PLATFORM)" | sed -E 's!linux/([^/]+).*!\1!')
IMAGE_EXPORT_DIR = $(BUILD_DIR)/images/$@
BUILDX_BUILDER ?= podman-builder
# TODO: just push the other image and build tar files from output, skip tests for other platforms for now
BUILDX_OUTPUT ?= type=docker
BUILDX_OPTS ?= --builder=$(BUILDX_BUILDER) --output=$(BUILDX_OUTPUT) --platform=$(PLATFORM)

ASSET_NAME := podman-linux-$(ARCH)
ASSET_DIR := $(BUILD_DIR)/asset/$(ASSET_NAME)


images: podman podman-remote podman-minimal

multiarch-tar multiarch-images: PLATFORM = linux/arm64/v8,linux/amd64
multiarch-tar: BUILDX_OUTPUT = type=local,dest=$(IMAGE_EXPORT_DIR)
multiarch-tar: TAR_TARGET ?= tar
multiarch-tar: images tar-all

multiarch-images: BUILDX_OUTPUT = type=image
multiarch-images: images

# Single arch builds don't have nested arch directory, thus set path as for multiarch
singlearch-tar: BUILDX_OUTPUT = type=local,dest=$(IMAGE_EXPORT_DIR)/linux_$(ARCH)
singlearch-tar: TAR_TARGET ?= tar
singlearch-tar: images
singlearch-tar:
	make $(TAR_TARGET) PLATFORM="$(PLATFORM)" BUILDX_BUILDER="$(BUILDX_BUILDER)"

tar-all:
	@{ \
	set -e ;\
	for PLATFORM in `echo "$(PLATFORM)" | sed 's/,/ /g'`; do \
		printf '\nBuilding podman for %s...\n\n' "$$PLATFORM" ;\
		make $(TAR_TARGET) PLATFORM="$$PLATFORM" BUILDX_BUILDER="$(BUILDX_BUILDER)" ;\
	done ;\
	}

podman: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm $(PODMAN_BUILD_OPTS) --target $(PODMAN_IMAGE_TARGET) .

podman-minimal: create-builder
	make podman PODMAN_IMAGE_TARGET=rootlesspodmanminimal BUILDX_OPTS="$(BUILDX_OPTS)" PODMAN_BUILD_OPTS="$(PODMAN_MINIMAL_BUILD_OPTS)"

podman-remote: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm $(PODMAN_REMOTE_BUILD_OPTS) -f Dockerfile-remote .

podman-ssh: podman
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm -t $(PODMAN_SSH_IMAGE) -f Dockerfile-ssh --build-arg BASEIMAGE=$(PODMAN_IMAGE) .

create-builder:
	$(DOCKER) buildx inspect $(BUILDX_BUILDER) >/dev/null 2<&1 || $(DOCKER) buildx create --name=$(BUILDX_BUILDER) >/dev/null

delete-builder:
	$(DOCKER) buildx rm $(BUILDX_BUILDER)

register-qemu-binfmt: ## Enable multiarch support on the host
	$(DOCKER) run --rm --privileged multiarch/qemu-user-static:7.0.0-7 --reset -p yes

test: test-use-cases test-minimal-image

test-use-cases: $(BATS)
	DOCKER=$(DOCKER) \
	PODMAN_IMAGE=$(PODMAN_IMAGE) \
	PODMAN_REMOTE_IMAGE=$(PODMAN_REMOTE_IMAGE) \
	$(BATS) -T $(BATS_TEST)

test-minimal-image: $(BATS)
	DOCKER=$(DOCKER) \
	PODMAN_IMAGE=$(PODMAN_MINIMAL_IMAGE) \
	TEST_PREFIX=minimal \
	TEST_SKIP_PORTMAPPING=true \
	TEST_SKIP_PLAYKUBE=true \
	$(BATS) -T test/rootless.bats

install:
	cp -r $(ASSET_DIR)/usr $(ASSET_DIR)/etc /

tar: .podman-from-container
	rm -f $(ASSET_DIR).tar.gz
	mkdir -p $(ASSET_DIR)/usr/lib/systemd/system
	mkdir -p $(ASSET_DIR)/usr/lib/systemd/user
	cp -f conf/systemd/podman-restart.service $(ASSET_DIR)/usr/lib/systemd/system/podman-restart.service
	cp -f conf/systemd/podman.service $(ASSET_DIR)/usr/lib/systemd/system/podman.service
	cp -f conf/systemd/podman.socket $(ASSET_DIR)/usr/lib/systemd/system/podman.socket
	cp -f conf/systemd/podman.service $(ASSET_DIR)/usr/lib/systemd/user/podman.service
	cp -f conf/systemd/podman.socket $(ASSET_DIR)/usr/lib/systemd/user/podman.socket
	tar -C $(ASSET_DIR)/.. -czvf $(ASSET_DIR).tar.gz $(ASSET_NAME)

.podman-from-container: IMAGE_ROOTFS = $(BUILD_DIR)/images/podman/linux_$(ARCH)
.podman-from-container: podman
	rm -rf $(ASSET_DIR)
	mkdir -p $(ASSET_DIR)/etc $(ASSET_DIR)/usr/local
	mkdir -p $(ASSET_DIR)/etc $(ASSET_DIR)/usr/lib/systemd/user-generators/
	mkdir -p $(ASSET_DIR)/etc $(ASSET_DIR)/usr/lib/systemd/system-generators/
	cp -r $(IMAGE_ROOTFS)/etc/containers $(ASSET_DIR)/etc/containers
	cp -r $(IMAGE_ROOTFS)/usr/local/lib $(ASSET_DIR)/usr/local/lib
	cp -r $(IMAGE_ROOTFS)/usr/local/libexec $(ASSET_DIR)/usr/local/libexec
	ln -s ../../../local/libexec/podman/quadlet $(ASSET_DIR)/usr/lib/systemd/user-generators/podman-user-generator
	ln -s ../../../local/libexec/podman/quadlet $(ASSET_DIR)/usr/lib/systemd/system-generators/podman-system-generator
	cp -r $(IMAGE_ROOTFS)/usr/local/bin $(ASSET_DIR)/usr/local/bin
	cp README.md $(ASSET_DIR)/

signed-tar: tar .gpg
	@echo Running gpg signing container with GPG_SIGN_KEY and GPG_SIGN_KEY_PASSPHRASE
	export GPG_SIGN_KEY
	export GPG_SIGN_KEY_PASSPHRASE
	@$(DOCKER) run --rm -v "`pwd`/build:/build" \
		-e GPG_SIGN_KEY="$$GPG_SIGN_KEY" \
		-e GPG_SIGN_KEY_PASSPHRASE="$$GPG_SIGN_KEY_PASSPHRASE" \
		$(GPG_IMAGE) /bin/sh -c ' \
			set -e; \
			[ "$$GPG_SIGN_KEY" -a "$$GPG_SIGN_KEY_PASSPHRASE" ] || (echo Missing GPG_SIGN_KEY or GPG_SIGN_KEY_PASSPHRASE >&2; false); \
			echo "$$GPG_SIGN_KEY" | gpg --batch --import -; \
			rm -f $(ASSET_DIR).tar.gz.asc; \
			echo "$$GPG_SIGN_KEY_PASSPHRASE" | (set -x; gpg --pinentry-mode loopback --command-fd 0 -a -o $(ASSET_DIR).tar.gz.asc --detach-sign $(ASSET_DIR).tar.gz)'

verify-signature:
	( \
		for _ in `seq 1 10`; do \
			TMPDIR=$$(mktemp -d); \
			export GNUPGHOME=$$TMPDIR; \
			gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0CCF102C4F95D89E583FF1D4F8B5AF50344BB503 && \
			gpg --list-keys && \
			gpg --batch --verify $(ASSET_DIR).tar.gz.asc $(ASSET_DIR).tar.gz && \
			rm -rf $$TMPDIR && \
			exit 0 || \
			sleep 1; \
			rm -rf $$TMPDIR; \
		done; \
		exit 1; \
	)

.gpg:
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm -t $(GPG_IMAGE) --target gpg .

run:
	$(DOCKER) run -ti --rm --privileged \
		-v "`pwd`/test/storage/user":/podman/.local/share/containers/storage \
		$(PODMAN_IMAGE) /bin/sh

clean:
	$(DOCKER) run --rm -v "`pwd`:/work" alpine:3.20 rm -rf /work/build

run-server: podman-ssh
	# TODO: make sshd log to stdout (while still ensuring that we know when it is available)
	$(DOCKER) run --rm --privileged --network=host \
		-v "`pwd`/storage/user":/podman/.local/share/containers/storage \
		-v "`pwd`/test:/build" \
		-w /build \
		"${PODMAN_SSH_IMAGE}" \
		sh -c 'set -x; \
			ssh-keygen -b 2048 -t rsa -N "" -f /podman/.ssh/ssh_host_rsa_key; \
			ssh-keygen -b 521 -t ecdsa -N "" -f /podman/.ssh/ssh_host_ecdsa_key; \
			[ -f /build/storage/user/client_rsa ] || ssh-keygen -b 2048 -t rsa -N "" -f /build/storage/user/client_rsa; \
			cat /build/storage/user/client_rsa.pub > /podman/.ssh/authorized_keys; \
			/usr/sbin/sshd -eD -f ~/.ssh/sshd_config & \
			mkdir /tmp/podman; \
			podman system service -t 0 unix:///tmp/podman/podman.sock'

# TODO: fix build run for external client
# see ssh connection: https://github.com/containers/podman/blob/v2.0.4/pkg/bindings/connection.go#L73
run-client: podman-remote
	$(DOCKER) run --rm -it --network=host \
		-v "`pwd`/test:/build" \
		-w /build \
		-e PODMAN_URL=ssh://podman@127.0.0.1:2222/tmp/podman/podman.sock?secure=True \
		-e CONTAINER_SSHKEY=/build/storage/user/client_rsa \
		"${PODMAN_REMOTE_IMAGE}" \
		/bin/sh -c 'set -ex; \
			podman --url=$$PODMAN_URL --log-level=info build /build/test'
#ssh -o "StrictHostKeyChecking no" -i /build/client_rsa podman@127.0.0.1 -p 2222 echo hello

$(BATS):
	@echo Downloading bats
	@{ \
	set -e ;\
	rm -rf $(BATS_DIR).tmp ;\
	mkdir -p $(BATS_DIR).tmp ;\
	git clone -c 'advice.detachedHead=false' --depth=1 --branch $(BATS_VERSION) https://github.com/bats-core/bats-core.git $(BATS_DIR).tmp >/dev/null ;\
	$(BATS_DIR).tmp/install.sh "$(BATS_DIR)" ;\
	rm -rf $(BATS_DIR).tmp ;\
	}
