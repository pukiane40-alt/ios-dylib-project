# Makefile — PoolHelperMenu.dylib
# Cross-compile for ARM64 iOS from a macOS host with Xcode installed.
#
# Targets:
#   make          — build the dylib
#   make clean    — remove build artefacts
#   make help     — show this message

ARCH        := arm64
MIN_IOS     := 14.0
SDK         := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
SRC         := src/PoolHelperMenu.m
OUT_DIR     := build
OUT_BIN     := $(OUT_DIR)/PoolHelperMenu.dylib

CLANG       := clang
CFLAGS      := \
    -arch $(ARCH) \
    -isysroot $(SDK) \
    -miphoneos-version-min=$(MIN_IOS) \
    -framework UIKit \
    -framework Foundation \
    -framework QuartzCore \
    -dynamiclib \
    -install_name @rpath/PoolHelperMenu.dylib \
    -fmodules \
    -fobjc-arc \
    -O2 \
    -Wall \
    -Wextra

.PHONY: all clean help

all: $(OUT_BIN)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(OUT_BIN): $(SRC) | $(OUT_DIR)
	$(CLANG) $(CFLAGS) -o $@ $<
	@echo "Built: $@"

clean:
	rm -rf $(OUT_DIR)

help:
	@echo "Usage:"
	@echo "  make        — compile PoolHelperMenu.dylib (ARM64, iOS $(MIN_IOS)+)"
	@echo "  make clean  — remove build directory"
	@echo "  make help   — this message"
	@echo ""
	@echo "Requires Xcode + iPhone SDK."
