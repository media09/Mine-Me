cmake_minimum_required(VERSION 3.18)
project(mine_me_randomx LANGUAGES C CXX)

include(FetchContent)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ARCH "default" CACHE STRING "Portable RandomX architecture" FORCE)
FetchContent_Declare(
  randomx_upstream
  URL https://github.com/tevador/RandomX/archive/refs/tags/v1.2.1.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_GetProperties(randomx_upstream)
if(NOT randomx_upstream_POPULATED)
  FetchContent_Populate(randomx_upstream)
endif()
add_subdirectory(${randomx_upstream_SOURCE_DIR} ${randomx_upstream_BINARY_DIR} EXCLUDE_FROM_ALL)

add_library(mine_me_randomx SHARED randomx_bridge.cpp)
target_include_directories(mine_me_randomx PRIVATE ${randomx_upstream_SOURCE_DIR}/src)
target_link_libraries(mine_me_randomx PRIVATE randomx)
set_target_properties(mine_me_randomx PROPERTIES
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED ON
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mine_me_randomx
)
