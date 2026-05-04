cmake_minimum_required(VERSION 3.16)
project(primes LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(primes src/primes.cpp)

enable_testing()
add_test(NAME primes_default COMMAND primes 20)
set_tests_properties(primes_default PROPERTIES
    PASS_REGULAR_EXPRESSION "2, 3, 5, 7, 11, 13, 17, 19"
)
