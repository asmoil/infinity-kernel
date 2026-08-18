# Infinity Kernel v4.0.0 - Makefile
# SPDX-License-Identifier: GPL-2.0-only

.PHONY: kernelsu apatch sukisu_ultra resukisu kowsu none clean mrproper ziponly help

.DEFAULT_GOAL := help

# Default variant can be overridden: make kernelsu VARIANT=hyperos
VARIANT ?= miui

kernelsu:
	@./build.sh kernelsu $(VARIANT)

apatch:
	@./build.sh apatch $(VARIANT)

sukisu_ultra:
	@./build.sh sukisu_ultra $(VARIANT)

resukisu:
	@./build.sh resukisu $(VARIANT)

kowsu:
	@./build.sh kowsu $(VARIANT)

none:
	@./build.sh none $(VARIANT)

clean:
	@./build.sh kernelsu $(VARIANT) clean

mrproper:
	rm -rf out/ kernel/ toolchain/ ccache/

ziponly:
	@./build.sh kernelsu $(VARIANT) ziponly

help:
	@echo ""
	@echo "Infinity Kernel v4.0.0 Build Targets"
	@echo "====================================="
	@echo ""
	@echo "Usage: make <target> [VARIANT=<variant>]"
	@echo ""
	@echo "Root targets:"
	@echo "  kernelsu      - Build with KernelSU-Next (default)"
	@echo "  apatch         - Build with APatch"
	@echo "  sukisu_ultra   - Build with SuKisu Ultra"
	@echo "  resukisu       - Build with ReSuKisu"
	@echo "  kowsu          - Build with KoWSU"
	@echo "  none           - Build without root solution"
	@echo ""
	@echo "Variants: VARIANT=miui|hyperos|aosp  (default: miui)"
	@echo ""
	@echo "Other targets:"
	@echo "  clean          - Clean build artifacts"
	@echo "  mrproper       - Remove everything (source, toolchain, ccache)"
	@echo "  ziponly        - Repackage ZIP from existing build"
	@echo ""
