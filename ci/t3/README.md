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
- Linux and Windows with `ENGINE_ENABLE_CPU_ALL_VARIANTS`, which builds ggml's Vulkan backend
  and one CPU backend per CPU generation as plugins. Hosts without a Vulkan loader or GPU skip
  the Vulkan plugin and run on the CPU.
- OpenMP off everywhere.

To release, run the `T3 release` workflow with a tag such as `t3-2026.11.15`, then pin the
published archives and their SHA-256 hashes in T3 Code's `packages/audio-cpp/src/runtime.ts`.

To try a Linux build locally:

```sh
docker run --rm -v "$PWD":/src -w /src quay.io/pypa/manylinux_2_28_aarch64 \
  bash ci/t3/build-linux-lib.sh 0.0.0-local audio-local-lib-linux-arm64-vulkan.tar.gz
```
