
#[=======================================================================[

Result Variables
^^^^^^^^^^^^^^^^

This module will set the following variables in your project:

``BROTLI_FOUND``

``BROTLI_INCLUDE_DIRS``
``BROTLI_LIBRARIES``
Hints
^^^^^

#]=======================================================================]

set(BROTLI_FOUND FALSE)

find_path(BROTLI_INCLUDE_DIRS 
    NAMES brotli/decode.h brotli/encode.h
    PATH_SUFFIXES include
)
if (NOT BROTLI_INCLUDE_DIRS)
    message(FATAL_ERROR "Can't find brotli include files(decode.h, encode.h)!")
else()
    message("-- Found Brotli include dir: " ${BROTLI_INCLUDE_DIRS})
endif()

include(GNUInstallDirs)

find_library(BROTLI_COMMON
    NAMES brotlicommon
    PATH_SUFFIXES ${CMAKE_INSTALL_LIBDIR} lib
)
if (NOT BROTLI_COMMON)
    message(FATAL_ERROR "Can't find brotli common lib!")
endif()

find_library(BROTLI_DEC
    NAMES brotlidec
    PATH_SUFFIXES ${CMAKE_INSTALL_LIBDIR} lib
)
if (NOT BROTLI_DEC)
    message(FATAL_ERROR "Can't find brotli dec lib!")
endif()

find_library(BROTLI_ENC
    NAMES brotlienc
    PATH_SUFFIXES ${CMAKE_INSTALL_LIBDIR} lib
)
if (NOT BROTLI_ENC)
    message(FATAL_ERROR "Can't find brotli enc lib!")
endif()

set(BROTLI_FOUND TRUE)
list(APPEND BROTLI_LIBRARIES ${BROTLI_ENC} ${BROTLI_DEC} ${BROTLI_COMMON})
message("-- Found Brotli libs: " ${BROTLI_LIBRARIES})
