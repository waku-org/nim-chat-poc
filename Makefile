export BUILD_SYSTEM_DIR := vendor/nimbus-build-system
export EXCLUDED_NIM_PACKAGES := vendor/nwaku/vendor/nim-dnsdisc/vendor \
								vendor/nwaku/vendor/nimbus-build-system \
								vendor/nwaku/vendor/nim-ffi \
								vendor/nim-sds/vendor
LINK_PCRE := 0
FORMAT_MSG := "\\x1B[95mFormatting:\\x1B[39m"
# we don't want an error here, so we can handle things later, in the ".DEFAULT" target
-include $(BUILD_SYSTEM_DIR)/makefiles/variables.mk

ifeq ($(NIM_PARAMS),)
# "variables.mk" was not included, so we update the submodules.
GIT_SUBMODULE_UPDATE := git submodule update --init --recursive
.DEFAULT:
	+@ echo -e "Git submodules not found. Running '$(GIT_SUBMODULE_UPDATE)'.\n"; \
		$(GIT_SUBMODULE_UPDATE); \
		echo
# Now that the included *.mk files appeared, and are newer than this file, Make will restart itself:
# https://www.gnu.org/software/make/manual/make.html#Remaking-Makefiles
#
# After restarting, it will execute its original goal, so we don't have to start a child Make here
# with "$(MAKE) $(MAKECMDGOALS)". Isn't hidden control flow great?

else # "variables.mk" was included. Business as usual until the end of this file.

# Determine the OS
detected_OS := $(shell uname -s)
ifneq (,$(findstring MINGW,$(detected_OS)))
  detected_OS := Windows
endif


##########
## Main ##
##########
.PHONY: all update clean

# default target, because it's the first one that doesn't start with '.'
all: | bot_echo pingpong liblogoschat

test_file := $(word 2,$(MAKECMDGOALS))
define test_name
$(shell echo '$(MAKECMDGOALS)' | cut -d' ' -f3-)
endef

logos_chat.nims:
	ln -s logos_chat.nimble $@

update: | update-common
	rm -rf logos_chat.nims && \
		$(MAKE) logos_chat.nims $(HANDLE_OUTPUT)

clean:
	rm -rf build
	cd vendor/libchat && cargo clean

# must be included after the default target
-include $(BUILD_SYSTEM_DIR)/makefiles/targets.mk

### Create nimble links (used when building with Nix)
.PHONY: nimbus-build-system-nimble-dir
nimbus-build-system-nimble-dir:
	NIMBLE_DIR="$(CURDIR)/$(NIMBLE_DIR)" \
	PWD_CMD="$(PWD)" \
	$(CURDIR)/vendor/nwaku/scripts/generate_nimble_links.sh

## Possible values: prod; debug
TARGET ?= prod

## Git version
GIT_VERSION ?= $(shell git describe --abbrev=6 --always --tags)
## Compilation parameters. If defined in the CLI the assignments won't be executed
NIM_PARAMS := $(NIM_PARAMS) -d:git_version=\"$(GIT_VERSION)\" -d:libp2p_mix_experimental_exit_is_dest

##################
## Dependencies ##
##################

CARGO_TARGET_DIR ?= rust-bundle/target
RUST_BUNDLE_LIB := $(CARGO_TARGET_DIR)/release/liblogoschat_rust_bundle.a

# Mix RLN spam protection library (zerokit v2.0.2, stateless, for the
# mix-rln-spam-protection-plugin).
#
# liblogoschat also statically links libchat's Rust bundle; embedding librln
# statically too would put two copies of the Rust runtime in one image and
# collide at link time (`_rust_eh_personality`, `_ffi_c_string_free`).
#
# On darwin we link librln as a cdylib (librln.dylib) so its Rust runtime stays
# in its own image — nothing collides and no symbol surgery is needed. The
# shared lib is staged into build/ beside liblogoschat.dylib with an @rpath
# install name. On other platforms we keep the static archive and let the linker
# take the first copy of the duplicate runtime symbols via
# --allow-multiple-definition.
MIX_LIBRLN_VERSION ?= v2.0.2

ifeq ($(detected_OS),Darwin)
  MIX_LIBRLN_DYLIB := $(CURDIR)/build/librln.dylib
  MIX_LIBRLN_NIM_PARAMS := --passL:-L$(CURDIR)/build --passL:-lrln --passL:-Wl,-rpath,@loader_path

.PHONY: mix-librln
mix-librln: | $(MIX_LIBRLN_DYLIB)

$(MIX_LIBRLN_DYLIB):
	echo -e $(BUILD_MSG) "$@" && \
		mkdir -p $(CURDIR)/build && \
		$(CURDIR)/scripts/fetch_mix_librln_dylib.sh $(MIX_LIBRLN_DYLIB) $(MIX_LIBRLN_VERSION)
else
  MIX_LIBRLN_SRC  := $(CURDIR)/vendor/nwaku/librln_$(MIX_LIBRLN_VERSION).a
  MIX_LIBRLN_FILE := $(CURDIR)/build/librln_mix_$(MIX_LIBRLN_VERSION).a
  MIX_LIBRLN_NIM_PARAMS := --passL:$(MIX_LIBRLN_FILE) --passL:"-Wl,--allow-multiple-definition"

.PHONY: mix-librln
mix-librln: | $(MIX_LIBRLN_FILE)

$(MIX_LIBRLN_FILE): $(MIX_LIBRLN_SRC)
	echo -e $(BUILD_MSG) "$@" && \
		mkdir -p $(CURDIR)/build && \
		cp $(MIX_LIBRLN_SRC) $(MIX_LIBRLN_FILE)
endif

# libchat and rln each embed Rust std when built as staticlibs; linking both
# causes duplicate-symbol errors. rust-bundle/ links them as rlibs so std
# is emitted once. [1]
# [1] https://doc.rust-lang.org/reference/linkage.html#mixed-rust-and-foreign-codebases
.PHONY: build-rust-bundle
build-rust-bundle:
	@echo "Building Rust bundle (libchat + rln)"
	$(MAKE) -C vendor/nwaku librln
	CARGO_TARGET_DIR=$(CARGO_TARGET_DIR) cargo build --release --manifest-path rust-bundle/Cargo.toml
	@echo "Bundle library: $(RUST_BUNDLE_LIB)"

build-waku-nat:
	@echo "Start building waku nat-libs"
	$(MAKE) -C vendor/nwaku nat-libs
	@echo "Completed building nat-libs"

.PHONY: tests
tests: | build-rust-bundle build-waku-nat logos_chat.nims
	echo -e $(BUILD_MSG) "build/$@" && \
		$(ENV_SCRIPT) nim tests $(NIM_PARAMS) \
		--passL:$(RUST_BUNDLE_LIB) --passL:-lm \
		logos_chat.nims


##########
## Example ##
##########

# Ensure there is a nimble task with a name that matches the target
tui bot_echo pingpong: | build-rust-bundle build-waku-nat mix-librln logos_chat.nims
	echo -e $(BUILD_MSG) "build/$@" && \
	$(ENV_SCRIPT) nim $@ $(NIM_PARAMS) $(MIX_LIBRLN_NIM_PARAMS) \
		--passL:$(RUST_BUNDLE_LIB) --passL:-lm \
		--path:src logos_chat.nims

###########
## Library ##
###########

# Determine shared library extension based on OS
ifeq ($(shell uname -s),Darwin)
  LIBLOGOSCHAT_EXT := dylib
else ifeq ($(shell uname -s),Linux)
  LIBLOGOSCHAT_EXT := so
else
  LIBLOGOSCHAT_EXT := dll
endif

LIBLOGOSCHAT := build/liblogoschat.$(LIBLOGOSCHAT_EXT)

.PHONY: liblogoschat
liblogoschat: | build-rust-bundle build-waku-nat mix-librln logos_chat.nims
	echo -e $(BUILD_MSG) "$(LIBLOGOSCHAT)" && \
	$(ENV_SCRIPT) nim liblogoschat $(NIM_PARAMS) $(MIX_LIBRLN_NIM_PARAMS) \
		--passL:$(RUST_BUNDLE_LIB) --passL:-lm \
		--path:src logos_chat.nims && \
	echo -e "\n\x1B[92mLibrary built successfully:\x1B[39m" && \
	echo "  $(shell pwd)/$(LIBLOGOSCHAT)"

### Nix-only: dependencies are pre-built Nix derivations, not built here
.PHONY: liblogoschat-nix
liblogoschat-nix: | logos_chat.nims
	echo -e $(BUILD_MSG) "$(LIBLOGOSCHAT)" && \
	$(ENV_SCRIPT) nim liblogoschat $(NIM_PARAMS) --path:src logos_chat.nims

endif


