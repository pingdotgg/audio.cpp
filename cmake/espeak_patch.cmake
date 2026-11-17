# Upstream 1.52 fetches Sonic even when USE_LIBSONIC=OFF. Respect that option
# so a phonemizer-only build has no unnecessary transitive network dependency.
set(path "${SOURCE_DIR}/cmake/deps.cmake")
file(READ "${path}" contents)
string(REPLACE "else()\n  FetchContent_Declare(sonic-git" "elseif(USE_LIBSONIC)\n  FetchContent_Declare(sonic-git" contents "${contents}")
file(WRITE "${path}" "${contents}")
set(path "${SOURCE_DIR}/src/CMakeLists.txt")
file(READ "${path}" contents)
if(NOT contents MATCHES "ARCHIVE_OUTPUT_NAME espeak-ng-tool")
    string(APPEND contents "\n# Avoid colliding with the static espeak-ng library on MSVC.\nset_target_properties(espeak-ng-bin PROPERTIES ARCHIVE_OUTPUT_NAME espeak-ng-tool)\n")
    file(WRITE "${path}" "${contents}")
endif()
# Newer MSVC rejects the GCC extension __has_include_next in #if; treat it as absent there.
foreach(header unistd.h getopt.h endian.h)
    set(path "${SOURCE_DIR}/src/include/compat/${header}")
    file(READ "${path}" contents)
    if(NOT contents MATCHES "define __has_include_next")
        string(REPLACE "#if __has_include_next("
            "#if defined(_MSC_VER) && !defined(__clang__) && !defined(__has_include_next)\n#define __has_include_next(x) 0\n#endif\n#if __has_include_next("
            contents "${contents}")
        file(WRITE "${path}" "${contents}")
    endif()
endforeach()
if(BROWSER_BUILD)
    # Musl's wchar.h declares isw* too. Include it before eSpeak redirects those
    # names to UCD, so the macros do not rewrite libc function declarations.
    set(path "${SOURCE_DIR}/src/include/compat/wctype.h")
    file(READ "${path}" contents)
    if(NOT contents MATCHES "#include <wchar.h>")
        string(REPLACE "#include <ucd/ucd.h>" "#include <ucd/ucd.h>\n#include <wchar.h>" contents "${contents}")
        file(WRITE "${path}" "${contents}")
    endif()
endif()
