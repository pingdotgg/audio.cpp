#!/usr/bin/env bash
# Builds the C API library inside a quay.io/pypa/manylinux_2_28 container, so it loads on
# glibc 2.28 and newer. ggml loads Vulkan and the per-CPU-generation kernels as plugins, so
# hosts without a Vulkan loader or GPU run on the CPU instead of failing to load.
#
# Usage: ci/t3/build-linux-lib.sh <version> <archive-name.tar.gz>

set -euo pipefail

VERSION="$1"
ARCHIVE="$2"
MAX_GLIBC="2.28"
BUILD="${BUILD_DIR:-build-t3}"
DIST="${DIST_DIR:-dist-lib}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

PYBIN=$(ls -d /opt/python/cp312-cp312/bin 2>/dev/null || ls -d /opt/python/cp3*/bin | head -1)
"$PYBIN/pip" install --quiet cmake ninja
export PATH="$PYBIN:$PATH"

bash ci/t3/vulkan-toolchain.sh

cmake -S . -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DCMAKE_SHARED_LINKER_FLAGS='-Wl,--as-needed' \
    -DAUDIOCPP_BUILD_C_API=ON \
    -DAUDIOCPP_VERSION="$VERSION" \
    -DENGINE_ENABLE_CUDA=OFF \
    -DENGINE_ENABLE_VULKAN=ON \
    -DENGINE_ENABLE_NATIVE_CPU=OFF \
    -DENGINE_ENABLE_CPU_ALL_VARIANTS=ON \
    -DENGINE_ENABLE_LLAMAFILE=ON \
    -DENGINE_ENABLE_OPENMP=OFF -DGGML_OPENMP=OFF
cmake --build "$BUILD" --target audiocpp --parallel "$(nproc)"

rm -rf "$DIST" && mkdir -p "$DIST/libs" "$DIST/include"
cp include/audiocpp.h "$DIST/include/"
cp LICENSE "$DIST/"
find "$BUILD/bin" -maxdepth 1 -name '*.so*' -exec cp -P {} "$DIST/libs/" \;

# Fail rather than publish a build that would not load where it is meant to.
status=0
for lib in "$DIST"/libs/*.so*; do
    [[ -L "$lib" ]] && continue
    newest=$(objdump -T "$lib" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)
    if [[ -n "$newest" && "$(printf '%s\n%s\n' "$newest" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]]; then
        echo "error: $lib needs glibc $newest, newer than $MAX_GLIBC" >&2
        status=1
    fi
    # Minimal hosts lack libgomp and libatomic. Only the Vulkan plugin may link the loader;
    # ggml skips the plugin when the loader is missing.
    forbidden='libgomp|libatomic'
    [[ "$(basename "$lib")" == libggml-vulkan* ]] || forbidden="libvulkan|$forbidden"
    if readelf -d "$lib" | grep -Eq "NEEDED.*($forbidden)"; then
        echo "error: $lib links $(readelf -d "$lib" | grep -Eo "($forbidden)[^]]*")" >&2
        status=1
    fi
done
[[ $status -eq 0 ]] || exit $status

tar -czf "$ARCHIVE" -C "$DIST" .
echo "built $ARCHIVE"
ls -la "$DIST/libs"
