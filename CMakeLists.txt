cmake_minimum_required(VERSION 3.15)

# Single source of truth for the product version (feeds .pkg name + release tag later).
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" MVD_VERSION LIMIT_COUNT 1)
project(mavericks_docker VERSION ${MVD_VERSION} LANGUAGES NONE)
# LANGUAGES NONE: nothing is compiled natively. The real 10.9/x86_64 enforcement is
# the go build flags below + the compat_guard gate, NOT CMake's compiler vars.
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9)
set(CMAKE_OSX_ARCHITECTURES x86_64)

# Build-mode detection at configure time. "iso" = Docker-driven boot2docker.iso build
# (its own preset; no Go/SDK, no native/cross). Otherwise: "native" = compiling ON
# Mavericks 10.9 (pkgsrc go126 present), "cross" = a modern host cross-compiling for 10.9.
if(MVD_EXPECTED_MODE STREQUAL "iso")
  set(MVD_MODE "iso")
else()
  set(MVD_MODE "cross")
  if(EXISTS "/opt/pkg/go126/bin/go")
    execute_process(COMMAND sw_vers -productVersion
      OUTPUT_VARIABLE _osv OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(_osv MATCHES "^10\\.9\\.")
      set(MVD_MODE "native")
    endif()
  endif()
endif()
message(STATUS "mavericks-docker ${MVD_VERSION} — build: ${MVD_MODE}")

# Require a per-mode preset: nothing may configure into an unqualified "build/" that
# can't tell native from cross (and would clobber the synced tree). The presets set
# MVD_EXPECTED_MODE + a distinct binaryDir (build-native / build-cross).
if(NOT DEFINED MVD_EXPECTED_MODE)
  message(FATAL_ERROR
    "Configure via a preset: 'cmake --preset native' on Mavericks, or "
    "'cmake --preset cross' on a modern host. Direct 'cmake -B <dir>' is disabled.")
endif()
# And fail fast if a preset is used on the wrong machine.
if(NOT MVD_EXPECTED_MODE STREQUAL MVD_MODE)
  message(FATAL_ERROR "preset expects a '${MVD_EXPECTED_MODE}' build but this machine "
    "does a '${MVD_MODE}' build — wrong preset for this host.")
endif()

if(NOT MVD_MODE STREQUAL "iso")
  # Shared 10.9 build machinery (SDK fetch + compat guard scripts). Resolved here, in the
  # non-iso path and BEFORE the SDK-fetch execute_process below, so a cross first-configure
  # (empty cache) has MavericksSharedCMake_DIR set. iso mode returns earlier and never needs it.
  find_package(MavericksSharedCMake REQUIRED)
  include(MavericksFetch)   # mavericks_fetch_10_9_sdk()

  # Pinned 10.9 SDK. native -> system SDK; cross -> fetch it.
  set(MVD_MACOSX_10_9_SDK "" CACHE PATH "MacOSX10.9 SDK root (cross build)")
  # Re-fetch when unset OR when the cached path went stale (TMPDIR-era caches
  # pointed into purgeable /var/folders and macOS eventually deleted the SDK).
  if(MVD_MODE STREQUAL "cross"
     AND (NOT MVD_MACOSX_10_9_SDK OR NOT EXISTS "${MVD_MACOSX_10_9_SDK}/usr/lib"))
    mavericks_fetch_10_9_sdk(_sdk)   # fetch+cache+verify (FATALs on failure); inherits MAVERICKS_SDK_CACHE
    set(MVD_MACOSX_10_9_SDK "${_sdk}" CACHE PATH "" FORCE)
  endif()

  # Per-mode toolchain + flags (mirrors the old build.sh host branches exactly).
  if(MVD_MODE STREQUAL "native")
    set(MVD_GO  "/opt/pkg/go126/bin/go")
    # System clang (no pkgsrc gcc dependency). Requires go126 built with the cgoclang
    # SUBST (lang/go126/Makefile) so runtime/cgo compiles under the 2014 system clang.
    set(MVD_CC  "/usr/bin/clang")
    set(MVD_LS_ARCHS  "")
    set(MVD_LS_CFLAGS "")
    set(MVD_DC_ARCH   "")
    set(MVD_DC_SDK    "")
  else()
    set(MVD_GO  "go")
    set(MVD_CC  "clang")
    set(MVD_LS_ARCHS  "x86_64")
    set(MVD_LS_CFLAGS "-isysroot ${MVD_MACOSX_10_9_SDK} -mmacosx-version-min=10.9")
    set(MVD_DC_ARCH   "-arch x86_64")
    set(MVD_DC_SDK    "-isysroot ${MVD_MACOSX_10_9_SDK}")
  endif()
endif()

# Read a component's REPO/REF pin from components/<name>/version.
function(mvd_read_pin dir out_repo out_ref)
  file(STRINGS "${dir}/version" _lines)
  foreach(_l IN LISTS _lines)
    if(_l MATCHES "^REPO=(.+)$")
      set(_repo "${CMAKE_MATCH_1}")
    elseif(_l MATCHES "^REF=(.+)$")
      set(_ref "${CMAKE_MATCH_1}")
    endif()
  endforeach()
  set(${out_repo} "${_repo}" PARENT_SCOPE)
  set(${out_ref}  "${_ref}"  PARENT_SCOPE)
endfunction()

include(ExternalProject)
enable_testing()

# --- iso mode: Docker-driven boot2docker.iso. No Go/SDK; requires a Docker daemon. ---
set(MVD_SRC_CACHE "${CMAKE_SOURCE_DIR}/.srccache" CACHE PATH
    "Shared cache dir for pinned dependency source clones")
if(MVD_MODE STREQUAL "iso")
  execute_process(COMMAND docker version
    RESULT_VARIABLE _dv OUTPUT_QUIET ERROR_QUIET)
  if(NOT _dv EQUAL 0)
    message(FATAL_ERROR "iso mode needs a reachable Docker daemon (`docker version` failed)")
  endif()

  mvd_read_pin("${CMAKE_SOURCE_DIR}/components/boot2docker" B2D_REPO B2D_REF)
  set(B2D_SRC "${MVD_SRC_CACHE}/boot2docker-${B2D_REF}")
  set(B2D_OUT "${CMAKE_BINARY_DIR}/boot2docker")
  set(B2D_ISO "${B2D_OUT}/boot2docker.iso")
  ExternalProject_Add(boot2docker
    SOURCE_DIR       "${B2D_SRC}"
    DOWNLOAD_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/clone_pinned.sh"
                       "${B2D_REPO}" "${B2D_REF}" "${B2D_SRC}"
    UPDATE_COMMAND   ""
    CONFIGURE_COMMAND ""
    BUILD_IN_SOURCE  TRUE
    BUILD_COMMAND    sh "${CMAKE_SOURCE_DIR}/cmake/build_boot2docker.sh"
                       <SOURCE_DIR> "${B2D_OUT}" "${B2D_REF}"
    INSTALL_COMMAND  ""
    BUILD_BYPRODUCTS "${B2D_ISO}"
  )

  # Gates.
  add_test(NAME iso_fetch_verify
    COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/iso_fetch_verify.sh"
               "${CMAKE_SOURCE_DIR}/components/boot2docker")
  add_test(NAME iso_fingerprint
    COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/iso_fingerprint.sh" compare
               "${CMAKE_SOURCE_DIR}/cmake/characterization/boot2docker" "${B2D_ISO}")
  add_test(NAME iso_boot_proof
    COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/iso_boot_proof.sh" "${B2D_ISO}")
  set_tests_properties(iso_boot_proof PROPERTIES SKIP_RETURN_CODE 77)

  # Self-contained unit tests for the iso scripts.
  foreach(t boot2docker_pin_test boot2docker_build_script_test iso_fingerprint_test
            iso_fetch_verify_test iso_boot_proof_test boot2docker_ci_test)
    add_test(NAME ${t} COMMAND sh "${CMAKE_SOURCE_DIR}/tests/${t}.sh")
  endforeach()

  return()  # iso mode defines nothing from the Mac pipeline below
endif()

# --- component builds, gates, and unit tests ---
mvd_read_pin("${CMAKE_SOURCE_DIR}/components/legacy-support" LS_REPO LS_REF)
set(LS_SRC "${MVD_SRC_CACHE}/legacy-support-${LS_REF}")
set(LS_OUT "${CMAKE_BINARY_DIR}/legacy-support")
set(LS_A   "${LS_OUT}/lib/libMacportsLegacySupport.a")
# Fetched once into the shared source cache like the docker components, but
# built from a per-build-dir copy: make compiles in-tree, so native and cross
# builds sharing one checkout would stomp each other's objects.
ExternalProject_Add(legacy_support
  SOURCE_DIR       "${CMAKE_BINARY_DIR}/legacy-support-src"
  DOWNLOAD_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/clone_pinned.sh"
                     "${LS_REPO}" "${LS_REF}" "${LS_SRC}"
           COMMAND "${CMAKE_COMMAND}" -E remove_directory <SOURCE_DIR>  # purge stale copy on REF bump
           COMMAND "${CMAKE_COMMAND}" -E copy_directory "${LS_SRC}" <SOURCE_DIR>
  UPDATE_COMMAND   ""
  BUILD_IN_SOURCE  TRUE
  CONFIGURE_COMMAND ""
  BUILD_COMMAND    sh "${CMAKE_SOURCE_DIR}/cmake/build_legacy_support.sh"
                     <SOURCE_DIR> "${LS_OUT}" "${MVD_CC}" "${MVD_LS_ARCHS}" "${MVD_LS_CFLAGS}"
  INSTALL_COMMAND  ""
  BUILD_BYPRODUCTS "${LS_A}"
)

mvd_read_pin("${CMAKE_SOURCE_DIR}/components/docker-cli" DC_REPO DC_REF)
set(DC_OUT     "${CMAKE_BINARY_DIR}/docker-cli")
set(DOCKER_BIN "${DC_OUT}/docker")
set(DC_SRC     "${MVD_SRC_CACHE}/docker-cli-${DC_REF}")
ExternalProject_Add(docker_cli
  DEPENDS          legacy_support
  SOURCE_DIR       "${DC_SRC}"
  DOWNLOAD_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/clone_pinned.sh"
                     "${DC_REPO}" "${DC_REF}" "${DC_SRC}"
  UPDATE_COMMAND   ""
  BUILD_IN_SOURCE  TRUE
  CONFIGURE_COMMAND ""
  BUILD_COMMAND    sh "${CMAKE_SOURCE_DIR}/cmake/build_docker_cli.sh"
                     <SOURCE_DIR> "${DC_OUT}" "${MVD_GO}" "${MVD_CC}"
                     "${MVD_DC_ARCH}" "${MVD_DC_SDK}" "${LS_A}" "${DC_REF}"
  INSTALL_COMMAND  ""
  BUILD_BYPRODUCTS "${DOCKER_BIN}"
)

# docker-machine (GOPATH/dep era: no go.mod, vendored). Cloned into a GOPATH-shaped path
# so GO111MODULE=off can build it; the shim is injected via -extldflags (its only cgo is
# stdlib). Same go/CC/mode flags as docker-cli, so native + cross both work.
mvd_read_pin("${CMAKE_SOURCE_DIR}/components/docker-machine" DM_REPO DM_REF)
set(DM_GOPATH   "${MVD_SRC_CACHE}/docker-machine-${DM_REF}")
set(DM_SRC      "${DM_GOPATH}/src/github.com/docker/machine")
set(DM_OUT      "${CMAKE_BINARY_DIR}/docker-machine")
set(MACHINE_BIN "${DM_OUT}/docker-machine")
ExternalProject_Add(docker_machine
  DEPENDS          legacy_support
  SOURCE_DIR       "${DM_SRC}"
  DOWNLOAD_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/clone_pinned.sh"
                     "${DM_REPO}" "${DM_REF}" "${DM_SRC}"
  UPDATE_COMMAND   ""
  BUILD_IN_SOURCE  TRUE
  CONFIGURE_COMMAND ""
  BUILD_COMMAND    sh "${CMAKE_SOURCE_DIR}/cmake/build_docker_machine.sh"
                     <SOURCE_DIR> "${DM_OUT}" "${MVD_GO}" "${MVD_CC}"
                     "${MVD_DC_ARCH}" "${MVD_DC_SDK}" "${LS_A}" "${DM_GOPATH}"
  INSTALL_COMMAND  ""
  BUILD_BYPRODUCTS "${MACHINE_BIN}"
)

# docker-compose (Compose v2; a go.mod module, not vendored). Simpler than docker-machine:
# a normal module build (deps from the shared module cache), shim via -extldflags.
mvd_read_pin("${CMAKE_SOURCE_DIR}/components/docker-compose" CO_REPO CO_REF)
set(CO_SRC      "${MVD_SRC_CACHE}/docker-compose-${CO_REF}")
set(CO_OUT      "${CMAKE_BINARY_DIR}/docker-compose")
set(COMPOSE_BIN "${CO_OUT}/docker-compose")
ExternalProject_Add(docker_compose
  DEPENDS          legacy_support
  SOURCE_DIR       "${CO_SRC}"
  DOWNLOAD_COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/clone_pinned.sh"
                     "${CO_REPO}" "${CO_REF}" "${CO_SRC}"
  UPDATE_COMMAND   ""
  BUILD_IN_SOURCE  TRUE
  CONFIGURE_COMMAND ""
  BUILD_COMMAND    sh "${CMAKE_SOURCE_DIR}/cmake/build_docker_compose.sh"
                     <SOURCE_DIR> "${CO_OUT}" "${MVD_GO}" "${MVD_CC}"
                     "${MVD_DC_ARCH}" "${MVD_DC_SDK}" "${LS_A}" "${CO_REF}"
  INSTALL_COMMAND  ""
  BUILD_BYPRODUCTS "${COMPOSE_BIN}"
)

# Fail-closed build-artifact gates (run after `cmake --build`).
add_test(NAME compat_guard
  COMMAND sh "${MavericksSharedCMake_SCRIPTS}/compat_guard.sh" "${DOCKER_BIN}")
add_test(NAME sdk_coverage
  COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/sdk_coverage.sh"
             --fetch-script "${MavericksSharedCMake_SCRIPTS}/fetch_10_9_sdk.sh"
             "${DOCKER_BIN}")
add_test(NAME characterize
  COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/characterize_build.sh" compare
             "${CMAKE_SOURCE_DIR}/cmake/characterization/docker-cli" "${DOCKER_BIN}")
# characterize reads the binary's gomod via `go version -m`; use the SAME go that
# built it (MVD_GO), not whatever `go` is on PATH.
set_tests_properties(characterize PROPERTIES ENVIRONMENT "GO=${MVD_GO}")

# docker-machine through the same 10.9-safety gates.
add_test(NAME compat_guard_machine
  COMMAND sh "${MavericksSharedCMake_SCRIPTS}/compat_guard.sh" "${MACHINE_BIN}")
add_test(NAME sdk_coverage_machine
  COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/sdk_coverage.sh"
             --fetch-script "${MavericksSharedCMake_SCRIPTS}/fetch_10_9_sdk.sh"
             "${MACHINE_BIN}")
# docker-compose through the same 10.9-safety gates.
add_test(NAME compat_guard_compose
  COMMAND sh "${MavericksSharedCMake_SCRIPTS}/compat_guard.sh" "${COMPOSE_BIN}")
add_test(NAME sdk_coverage_compose
  COMMAND sh "${CMAKE_SOURCE_DIR}/cmake/sdk_coverage.sh"
             --fetch-script "${MavericksSharedCMake_SCRIPTS}/fetch_10_9_sdk.sh"
             "${COMPOSE_BIN}")

# Unit tests (script behavior + output invariants). Output-asserting ones take the
# built artifact path; self-contained ones run from the source tree.
add_test(NAME legacy_support_unit
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/legacy_support_test.sh" "${LS_A}")
add_test(NAME docker_cli_unit
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/docker_cli_test.sh" "${DOCKER_BIN}")
# These exercise the gate scripts against the built binary -> pass DOCKER_BIN so they
# work with any build dir (cmake -B <dir>), not a hardcoded build/.
add_test(NAME compat_guard_test
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/compat_guard_test.sh" "${DOCKER_BIN}" "${MavericksSharedCMake_SCRIPTS}/compat_guard.sh")
add_test(NAME sdk_coverage_test
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/sdk_coverage_test.sh" "${DOCKER_BIN}"
             "${MavericksSharedCMake_SCRIPTS}/fetch_10_9_sdk.sh")
add_test(NAME characterize_test
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/characterize_test.sh" "${DOCKER_BIN}")
# Self-contained (no built binary needed).
foreach(t scaffold_test renovate_test docker_compose_test)
  add_test(NAME ${t} COMMAND sh "${CMAKE_SOURCE_DIR}/tests/${t}.sh")
endforeach()
add_test(NAME fetch_sdk_test
  COMMAND sh "${CMAKE_SOURCE_DIR}/tests/fetch_sdk_test.sh" "${MavericksSharedCMake_SCRIPTS}/fetch_10_9_sdk.sh")
set_tests_properties(characterize_test PROPERTIES ENVIRONMENT "GO=${MVD_GO}")
