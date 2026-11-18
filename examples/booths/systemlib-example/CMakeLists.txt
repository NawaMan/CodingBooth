cmake_minimum_required(VERSION 3.16)
project(linkcheck LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Two real system libraries, resolved from what apt installed:
#   libcurl4-openssl-dev -> find_package(CURL)    -> CURL::libcurl
#   libsqlite3-dev       -> find_package(SQLite3) -> SQLite::SQLite3
# This is the part header-only libraries let you skip — locating the headers AND
# linking the shared objects. If either -dev package is missing, configure fails here.
find_package(CURL REQUIRED)
find_package(SQLite3 REQUIRED)

add_executable(linkcheck src/linkcheck.cpp)
target_link_libraries(linkcheck PRIVATE CURL::libcurl SQLite::SQLite3)
