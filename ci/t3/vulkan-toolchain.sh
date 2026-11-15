#!/usr/bin/env bash
# Builds the Vulkan toolchain (headers, SPIR-V headers, loader, glslc) from pinned Khronos and
# Google tags inside a manylinux_2_28 container. LunarG's prebuilt SDK needs glibc 2.34 or newer,
# so it cannot run there. Adapted from transcribe.cpp's scripts/ci/manylinux-vulkan-toolchain.sh
# (MIT, Copyright (c) 2026 The transcribe.cpp authors).
#
# The loader is only for linking ggml's Vulkan plugin; at runtime the plugin resolves the host's
# own libvulkan.so.1, so this library never ships.

set -euo pipefail

VULKAN_SDK_TAG="vulkan-sdk-1.4.350.0"
SHADERC_TAG="v2026.2"
PREFIX=/usr/local
STAMP="${VULKAN_SDK_TAG}_shaderc-${SHADERC_TAG}"
CACHE_ROOT="${VK_TOOLCHAIN_CACHE:-}"

if [[ -n "$CACHE_ROOT" && -d "$CACHE_ROOT/$STAMP" ]]; then
    echo "vulkan-toolchain: restoring $STAMP from cache"
    cp -a "$CACHE_ROOT/$STAMP/." "$PREFIX/"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE"

clone() { git clone --quiet --depth 1 --branch "$1" "$2" "$3"; }

clone "$VULKAN_SDK_TAG" https://github.com/KhronosGroup/Vulkan-Headers "$WORK/headers"
cmake -S "$WORK/headers" -B "$WORK/headers/build" -G Ninja -DCMAKE_INSTALL_PREFIX="$STAGE" >/dev/null
cmake --install "$WORK/headers/build" >/dev/null

clone "$VULKAN_SDK_TAG" https://github.com/KhronosGroup/SPIRV-Headers "$WORK/spirv-headers"
cmake -S "$WORK/spirv-headers" -B "$WORK/spirv-headers/build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$STAGE" >/dev/null
cmake --install "$WORK/spirv-headers/build" >/dev/null

clone "$VULKAN_SDK_TAG" https://github.com/KhronosGroup/Vulkan-Loader "$WORK/loader"
cmake -S "$WORK/loader" -B "$WORK/loader/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$STAGE" \
    -DCMAKE_PREFIX_PATH="$STAGE" \
    -DBUILD_TESTS=OFF \
    -DBUILD_WSI_XCB_SUPPORT=OFF \
    -DBUILD_WSI_XLIB_SUPPORT=OFF \
    -DBUILD_WSI_WAYLAND_SUPPORT=OFF >/dev/null
cmake --build "$WORK/loader/build" -j >/dev/null
cmake --install "$WORK/loader/build" >/dev/null

# git-sync-deps pins glslang, SPIRV-Tools, and SPIRV-Headers to shaderc's DEPS file.
clone "$SHADERC_TAG" https://github.com/google/shaderc "$WORK/shaderc"
(cd "$WORK/shaderc" && ./utils/git-sync-deps >/dev/null 2>&1)
cmake -S "$WORK/shaderc" -B "$WORK/shaderc/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSHADERC_SKIP_TESTS=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON >/dev/null
cmake --build "$WORK/shaderc/build" --target glslc_exe -j >/dev/null
install -D -m 0755 "$WORK/shaderc/build/glslc/glslc" "$STAGE/bin/glslc"

cp -a "$STAGE/." "$PREFIX/"
if [[ -n "$CACHE_ROOT" ]]; then
    mkdir -p "$CACHE_ROOT/$STAMP"
    cp -a "$STAGE/." "$CACHE_ROOT/$STAMP/"
fi
glslc --version | head -1
