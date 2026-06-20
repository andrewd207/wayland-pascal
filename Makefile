# Makefile for the wayl project.
#
# Prefers pasbuild (the project's normal build tool). If pasbuild is not on
# PATH, it falls back to invoking fpc directly with the same unit search paths
# pasbuild would configure (each module's src/main/pascal, so fpc compiles the
# dependency units from source on demand).
#
#   make            # build the runtime libraries + demo (pasbuild, or fpc)
#   make examples   # build the standalone examples (not built by default)
#   make clean      # remove build output
#
# Override the compiler with `make FPC=/path/to/fpc`.

ROOT     := $(CURDIR)
FPC      ?= fpc
PASBUILD := $(shell command -v pasbuild 2>/dev/null)

# Module source directories — the fpc fallback's unit search path. This mirrors
# the -Fu list pasbuild passes (it points at each dependency's target/units; we
# point at the sources so a from-scratch fpc build needs no prebuilt units).
COMMON_SRC   := $(ROOT)/wayland-common/src/main/pascal
RT_SRC       := $(ROOT)/wayland-client/rt/src/main/pascal
STABLE_SRC   := $(ROOT)/wayland-client/stable/src/main/pascal
UNSTABLE_SRC := $(ROOT)/wayland-client/unstable/src/main/pascal
STAGING_SRC  := $(ROOT)/wayland-client/staging/src/main/pascal
CLASSES_SRC  := $(ROOT)/wayland-client/classes/src/main/pascal
DEMO_SRC     := $(ROOT)/wayland-demo/src/main/pascal
EX_SRC       := $(ROOT)/wayland-examples/src/main/pascal

# Unit search paths for the library stack (common -> rt -> stable/unstable/staging -> classes).
UNITPATHS := -Fu$(COMMON_SRC) -Fu$(RT_SRC) -Fu$(STABLE_SRC) -Fu$(UNSTABLE_SRC) -Fu$(STAGING_SRC) -Fu$(CLASSES_SRC)
# Match pasbuild's default flags (mode objfpc, long strings, -O1).
FPCFLAGS  := -Mobjfpc -Sh -O1

DEMO_OUT := $(ROOT)/wayland-demo/target
EX_OUT   := $(ROOT)/wayland-examples/target

.PHONY: all examples clean

# ---- Default build: runtime libraries + demo -------------------------------
all:
ifneq ($(PASBUILD),)
	@echo ">> building with pasbuild"
	$(PASBUILD) compile
else
	@echo ">> pasbuild not found — building the demo with fpc directly"
	@mkdir -p $(DEMO_OUT)/units
	$(FPC) $(FPCFLAGS) $(UNITPATHS) -Fu$(DEMO_SRC) \
	  -FU$(DEMO_OUT)/units -FE$(DEMO_OUT) -owayland-demo \
	  $(DEMO_SRC)/Main.pas
endif

# ---- Examples (not active by default) --------------------------------------
# pasbuild's application module builds a single executable, so we fpc-build each
# example program here (same paths). When pasbuild is available we first let it
# build/refresh the library dependencies.
examples:
ifneq ($(PASBUILD),)
	@echo ">> building library deps with pasbuild"
	$(PASBUILD) compile
endif
	@mkdir -p $(EX_OUT)/units
	@for f in $(EX_SRC)/*.pas; do \
	  b=$$(basename $$f .pas); \
	  echo ">> fpc $$b"; \
	  $(FPC) $(FPCFLAGS) $(UNITPATHS) -Fu$(EX_SRC) \
	    -FU$(EX_OUT)/units -FE$(EX_OUT) -o$$b $$f || exit 1; \
	done
	@echo ">> examples built in $(EX_OUT)"

# ---- Clean -----------------------------------------------------------------
clean:
ifneq ($(PASBUILD),)
	-$(PASBUILD) clean
endif
	rm -rf $(ROOT)/wayland-common/target \
	       $(ROOT)/wayland-client/rt/target $(ROOT)/wayland-client/stable/target \
	       $(ROOT)/wayland-client/unstable/target $(ROOT)/wayland-client/staging/target \
	       $(ROOT)/wayland-client/classes/target \
	       $(ROOT)/wayland-server/rt/target $(DEMO_OUT) $(EX_OUT)
