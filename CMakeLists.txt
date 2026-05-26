cmake_minimum_required(VERSION 3.20)
project(clickhouse-matlab CXX)

# ── Library version (single source of truth: version.txt) ───────────────────
file(READ "${CMAKE_SOURCE_DIR}/version.txt" CLICKHOUSE_MATLAB_VERSION)
string(STRIP "${CLICKHOUSE_MATLAB_VERSION}" CLICKHOUSE_MATLAB_VERSION)
if(CLICKHOUSE_MATLAB_VERSION STREQUAL "")
    message(FATAL_ERROR "version.txt is empty")
endif()
message(STATUS "clickhouse-matlab version: ${CLICKHOUSE_MATLAB_VERSION}")
# Retrigger configure when version.txt changes so the -D flag updates.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/version.txt")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Compiler pinning ────────────────────────────────────────────────────────
# Use g++-9 to avoid GLIBCXX version mismatches with MATLAB's bundled libstdc++.
# Override on the cmake command line if your system differs:
#   cmake -DCMAKE_CXX_COMPILER=g++-11 ...
if(NOT CMAKE_CXX_COMPILER)
    find_program(GPP9 g++-9)
    if(GPP9)
        set(CMAKE_CXX_COMPILER "${GPP9}" CACHE FILEPATH "C++ compiler" FORCE)
    endif()
endif()

# ── Build flags ─────────────────────────────────────────────────────────────
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Static-link the C++ runtime so MATLAB's older libstdc++ is never used.
add_compile_options(-fPIC)
add_link_options(-static-libstdc++ -static-libgcc)

# ── External packages ───────────────────────────────────────────────────────

# Default to manual MATLAB detection. CMake's bundled FindMatlab.cmake (in newer
# versions) silently links libMatlabEngine / libMatlabDataArray into the MEX,
# which is the C++ Engine/Data API. Those libraries live in extern/bin/glnxa64
# and are NOT on the runtime library search path of consumer MATLAB sessions —
# so the resulting MEX fails to load on any other host with
# "libMatlabEngine.so: cannot open shared object file". The manual path below
# links only libmex + libmx, which is what a plain MEX actually needs and is
# portable across MATLAB versions. Set -DUSE_FINDMATLAB=ON to opt back in.
option(USE_FINDMATLAB "Use CMake's FindMatlab (may link libMatlabEngine.so, breaking portability)" OFF)
if(USE_FINDMATLAB)
    find_package(Matlab QUIET COMPONENTS MEX_COMPILER)
endif()

if(NOT Matlab_FOUND)
    if(NOT Matlab_ROOT_DIR)
        message(FATAL_ERROR
            "Could not find MATLAB automatically and Matlab_ROOT_DIR is not set.\n"
            "Pass -DMatlab_ROOT_DIR=/path/to/matlab to cmake.")
    endif()
    message(STATUS "FindMatlab failed — using manual detection at ${Matlab_ROOT_DIR}")

    # Detect platform arch and MEX extension
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set(MATLAB_ARCH "glnxa64")
        set(MEX_EXT    "mexa64")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
            set(MATLAB_ARCH "maca64")
            set(MEX_EXT    "mexmaca64")
        else()
            set(MATLAB_ARCH "maci64")
            set(MEX_EXT    "mexmaci64")
        endif()
    else()
        set(MATLAB_ARCH "win64")
        set(MEX_EXT    "mexw64")
    endif()

    set(Matlab_INCLUDE_DIRS "${Matlab_ROOT_DIR}/extern/include")
    find_library(Matlab_MEX_LIBRARY mex
        PATHS "${Matlab_ROOT_DIR}/bin/${MATLAB_ARCH}" NO_DEFAULT_PATH)
    find_library(Matlab_MX_LIBRARY  mx
        PATHS "${Matlab_ROOT_DIR}/bin/${MATLAB_ARCH}" NO_DEFAULT_PATH)

    if(NOT Matlab_MEX_LIBRARY OR NOT Matlab_MX_LIBRARY)
        message(FATAL_ERROR
            "Could not find libmex/libmx under ${Matlab_ROOT_DIR}/bin/${MATLAB_ARCH}.\n"
            "Check that Matlab_ROOT_DIR points to the MATLAB installation root.")
    endif()
    message(STATUS "Matlab_INCLUDE_DIRS: ${Matlab_INCLUDE_DIRS}")
    message(STATUS "Matlab_MEX_LIBRARY:  ${Matlab_MEX_LIBRARY}")
    message(STATUS "Matlab_MX_LIBRARY:   ${Matlab_MX_LIBRARY}")
    set(MATLAB_MANUAL TRUE)
endif()

set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)

# ── clickhouse-cpp submodule ────────────────────────────────────────────────
set(WITH_OPENSSL   ON  CACHE BOOL "Enable OpenSSL in clickhouse-cpp" FORCE)
set(WITH_ZSTD      ON  CACHE BOOL "Enable ZSTD in clickhouse-cpp"    FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libs only"         FORCE)

add_subdirectory(contrib/clickhouse-cpp)

# Collect every static archive that clickhouse-cpp pulls in,
# mirroring exactly what worked in the manual mex invocation.
set(CLICKHOUSE_STATIC_LIBS
    clickhouse-cpp-lib
    absl_int128
    cityhash
    lz4
    zstdstatic    # not zstd_static or zstd
)

# ── MEX target ──────────────────────────────────────────────────────────────
if(MATLAB_MANUAL)
    # Manual path: build as a plain shared library with the right extension
    add_library(clickhouse_mex SHARED src/clickhouse_mex.cpp)
    set_target_properties(clickhouse_mex PROPERTIES
        PREFIX ""
        SUFFIX ".${MEX_EXT}"
        LINK_FLAGS "-static-libstdc++ -static-libgcc"
    )
    target_compile_definitions(clickhouse_mex PRIVATE
        MATLAB_MEX_FILE
        MATLAB_DEFAULT_RELEASE=R2018a
    )
    target_include_directories(clickhouse_mex PRIVATE
        ${Matlab_INCLUDE_DIRS}
        ${CMAKE_SOURCE_DIR}/res/clickhouse-cpp
        ${CMAKE_SOURCE_DIR}/res/clickhouse-cpp/contrib/absl
    )
    target_link_libraries(clickhouse_mex
        ${Matlab_MEX_LIBRARY}
        ${Matlab_MX_LIBRARY}
        ${CLICKHOUSE_STATIC_LIBS}
        OpenSSL::SSL
        OpenSSL::Crypto
        Threads::Threads
    )
else()
    matlab_add_mex(
        NAME clickhouse_mex
        SRC  src/clickhouse_mex.cpp
        R2018a
    )
    target_include_directories(clickhouse_mex PRIVATE
        ${CMAKE_SOURCE_DIR}/res/clickhouse-cpp
        ${CMAKE_SOURCE_DIR}/res/clickhouse-cpp/contrib/absl   # absl headers
    )
    target_link_libraries(clickhouse_mex
        ${CLICKHOUSE_STATIC_LIBS}
        OpenSSL::SSL
        OpenSSL::Crypto
        Threads::Threads
    )
    # Force the static runtime flags onto the final link even for MEX targets
    # (matlab_add_mex may strip custom link options otherwise).
    set_target_properties(clickhouse_mex PROPERTIES
        LINK_FLAGS "-static-libstdc++ -static-libgcc"
    )
endif()

# ── Embed library version into the MEX as a compile-time string macro ───────
target_compile_definitions(clickhouse_mex PRIVATE
    CLICKHOUSE_MATLAB_VERSION="${CLICKHOUSE_MATLAB_VERSION}")
