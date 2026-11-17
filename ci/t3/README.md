# T3 Code builds

T3 Code downloads the C API library from this fork's releases for local speech synthesis.
Upstream's release builds do not fit it:

- Linux builds run on `ubuntu-latest`, so they need the newest glibc (2.43 as of v0.9.4) and
  fail to load on Ubuntu 24.04, Debian 12, and older.
- The Windows Vulkan build links `vulkan-1.dll`, so it fails to load on machines without a GPU
  driver instead of falling back to the CPU.
- OpenMP adds `libgomp`, which minimal Linux installs lack.

The `T3 release` workflow builds the library the way transcribe.cpp builds its own:

- Linux x64 and arm64 inside `manylinux_2_28`, so the library loads on glibc 2.28 and newer.
  `build-linux-lib.sh` fails the build if any library needs a newer glibc, or links
  `libgomp` or `libatomic`.
- Linux and Windows x64 with `ENGINE_ENABLE_CPU_ALL_VARIANTS`, which builds ggml's Vulkan backend
  and one CPU backend per CPU generation as plugins. Hosts without a Vulkan loader or GPU skip
  the Vulkan plugin and run on the CPU.
- Windows ARM64 with clang, which ggml requires for ARM CPU kernels. ggml has no Windows ARM
  variant list, so the fork's `ENGINE_ENABLE_BACKEND_PLUGINS` option keeps Vulkan a plugin with one
  CPU backend targeting `armv8.2-a+dotprod+fp16`, which every Windows 11 ARM CPU supports.
- OpenMP off everywhere.
- eSpeak-ng linked in (`AUDIOCPP_STATIC_ESPEAK`) for Kokoro. Its data package and source archive
  are published once per release; T3 Code downloads the data with Kokoro and points
  `AUDIOCPP_ESPEAK_DATA` and `AUDIOCPP_ESPEAK_CACHE` at its own state directory. Windows ARM64
  builds eSpeak with MSVC, since eSpeak's static build is only validated with it on Windows.

To release, run the `T3 release` workflow with a tag such as `t3-2026.11.15`, then pin the
published archives and their SHA-256 hashes in T3 Code's `packages/audio-cpp/src/runtime.ts`.

To try a Linux build locally:

```sh
docker run --rm -v "$PWD":/src -w /src quay.io/pypa/manylinux_2_28_aarch64 \
  bash ci/t3/build-linux-lib.sh 0.0.0-local audio-local-lib-linux-arm64-vulkan.tar.gz
```
