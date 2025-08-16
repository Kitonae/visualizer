cmake_minimum_required(VERSION 3.16)
project(NDITest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# NDI SDK path (adjust if needed)
set(NDI_SDK_ROOT "C:/Program Files/NDI/NDI 6 SDK")

# Find NDI library
find_library(NDI_LIB
    NAMES Processing.NDI.Lib.x64
    PATHS 
        "${NDI_SDK_ROOT}/Lib/x64"
        "${CMAKE_CURRENT_SOURCE_DIR}"
    NO_DEFAULT_PATH
)

if(NOT NDI_LIB)
    message(FATAL_ERROR "NDI library not found. Please ensure NDI SDK is installed or NDI DLL is in project directory.")
endif()

# Include directories
include_directories("${NDI_SDK_ROOT}/Include")

# Create executable
add_executable(ndi_test ndi_test.cpp)

# Link NDI library
target_link_libraries(ndi_test ${NDI_LIB})

# Copy NDI DLL to output directory
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/Processing.NDI.Lib.x64.dll")
    add_custom_command(TARGET ndi_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/Processing.NDI.Lib.x64.dll"
        $<TARGET_FILE_DIR:ndi_test>)
endif()

# Print configuration info
message(STATUS "NDI SDK Root: ${NDI_SDK_ROOT}")
message(STATUS "NDI Library: ${NDI_LIB}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

# Set output directory
set_target_properties(ndi_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/build"
)
