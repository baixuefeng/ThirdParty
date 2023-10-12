include_guard(GLOBAL)
include(GNUInstallDirs)
include(CMakePrintHelpers)

# --------------------------------------------------------------------------------------

# 查找代码文件，非递归
# @param[in] directory
# @param[out] fileList
macro(thirdparty_find_cpp_files directory fileList)
    file(
        GLOB ${fileList}
        LIST_DIRECTORIES false
        ${directory}/*.h ${directory}/*.inl ${directory}/*.hpp ${directory}/*.c ${directory}/*.cc ${directory}/*.cpp)
endmacro()

# 查找代码文件，递归
# @param[in] directory
# @param[out] fileList
function(thirdparty_find_cpp_files_recursively directory fileList)
    # cmake本身提供了递归遍历的方法，如下，但cmake会对文件进行排序。有的ide(比如QtCreator)生成项目树
    # (source_group)时，文件列表必须是层序的，因此手工实现一个层序的递归遍历。
    # macro(thirdparty_find_cpp_files_recursively  directory fileList)
    #     file(GLOB_RECURSE ${fileList}
    #          LIST_DIRECTORIES false
    #          ${directory}/*.h ${directory}/*.inl ${directory}/*.hpp ${directory}/*.c ${directory}/*.cc ${directory}/*.cpp)
    # endmacro()
    file(
        GLOB files
        LIST_DIRECTORIES false
        ${directory}/*.h ${directory}/*.inl ${directory}/*.hpp ${directory}/*.c ${directory}/*.cc ${directory}/*.cpp)

    file(
        GLOB tmplist
        LIST_DIRECTORIES true
        ${directory}/*)
    foreach(item ${tmplist})
        if(IS_DIRECTORY ${item})
            thirdparty_find_cpp_files_recursively(${item} subfiles)
            list(APPEND files ${subfiles})
        endif()
    endforeach()
    set(${fileList}
        ${files}
        PARENT_SCOPE)
endfunction()

# 查找qt5, 参数：qt5的组件
# 前提：设置 CMAKE_PREFIX_PATH 环境变量到 Qt5的根目录，注意不是qtcreator的根目录。
# 比如：qtcreator安装在D:\Qt, 使用MSVC编译器，则Qt5根目录：D:\Qt\Qt5.14.1\5.14.1\msvc2017_64
# qtcreator中不必额外设置环境变量
macro(thirdparty_use_qt5)
    find_package(Qt5 COMPONENTS ${ARGV})
    if(Qt5_FOUND)
        set(CMAKE_AUTOMOC ON)
        set(CMAKE_AUTORCC ON)
        set(CMAKE_AUTOUIC ON)
        foreach(var ${ARGV})
            if(${Qt5${var}_FOUND})
                message("-- Found Qt5: ${Qt5${var}_LIBRARIES} (found version: ${Qt5${var}_VERSION})")
                include_directories(${Qt5${var}_INCLUDE_DIRS})
                add_compile_definitions(${Qt5${var}_COMPILE_DEFINITIONS})
            endif()
        endforeach()
    endif()
endmacro()

# 链接python3
function(thirdparty_target_link_python3 target)
    find_package(Python3 REQUIRED COMPONENTS Development)
    target_include_directories(${target} PRIVATE ${Python3_INCLUDE_DIRS})
    target_link_libraries(${target} PRIVATE ${Python3_LIBRARIES})
    if(UNIX)
        # execute_process(COMMAND python3-config --extension-suffix
        #                 OUTPUT_VARIABLE so_name_tmp)
        # string(STRIP ${so_name_tmp} SO_NAME)
        # message("--python module suffix : " ${SO_NAME})
        # set_target_properties(${target} PROPERTIES PREFIX "" SUFFIX ${SO_NAME})
        set_target_properties(${target} PROPERTIES PREFIX "")
    else()
        set_target_properties(${target} PROPERTIES SUFFIX .pyd)
    endif()
endfunction()

# thirdparty_set_imported_location
# @param[options] APPEND if set this, append to existing property
# @param[multi_valua_keyword] PATH_SUFFIXES
# @param[multi_valua_keyword] LIB_PATHS  additional paths to search lib.
# @param[multi_valua_keyword] DLL_PATHS  additional paths to search dll, default: <dir>/bin and <dir> for each CMAKE_PREFIX_PATH.
function(thirdparty_set_imported_location target libNames dllGlobPatten)
    cmake_parse_arguments(MYARG "APPEND;" "" "PATH_SUFFIXES;LIB_PATHS;DLL_PATHS;" ${ARGN})
    message(
        STATUS
            "thirdparty_set_imported_location: target=${target}; libNames=${libNames}; dllGlobPatten=${dllGlobPatten}; MYARG_PATH_SUFFIXES=${MYARG_PATH_SUFFIXES}; MYARG_LIB_PATHS=${MYARG_LIB_PATHS}; MYARG_DLL_PATHS=${MYARG_DLL_PATHS}; MYARG_APPEND=${MYARG_APPEND}"
    )
    if(MYARG_LIB_PATHS)
        set(oldPath ${CMAKE_LIBRARY_PATH})
        list(APPEND CMAKE_LIBRARY_PATH ${MYARG_LIB_PATHS})
    endif()
    list(GET libNames 0 libPath)
    set(libPath "${libPath}_LIBRARY")
    if(MYARG_PATH_SUFFIXES)
        find_library(
            ${libPath}
            NAMES ${libNames}
            PATH_SUFFIXES ${MYARG_PATH_SUFFIXES} REQUIRED)
    else()
        find_library(${libPath} NAMES ${libNames} REQUIRED)
    endif()
    if(MYARG_LIB_PATHS)
        set(CMAKE_LIBRARY_PATH ${oldPath})
        unset(oldPath)
    endif()

    message(STATUS "Found target(${target}) lib: ${libPath}=${${libPath}}")
    if(MYARG_APPEND)
        set(appendOrNot "APPEND")
    else()
        set(appendOrNot "")
    endif()
    if(WIN32 AND dllGlobPatten)
        set_property(TARGET ${target} ${appendOrNot} PROPERTY IMPORTED_IMPLIB ${${libPath}})
        if(MYARG_DLL_PATHS)
            list(PREPEND MYARG_DLL_PATHS ${CMAKE_PREFIX_PATH})
        else()
            set(MYARG_DLL_PATHS ${CMAKE_PREFIX_PATH})
        endif()
        foreach(dir ${MYARG_DLL_PATHS})
            file(GLOB dllPath ${dir}/bin/${dllGlobPatten})
            if(dllPath)
                break()
            endif()
            file(GLOB dllPath ${dir}/${dllGlobPatten})
            if(dllPath)
                break()
            endif()
        endforeach()
        list(LENGTH dllPath dllCount)
        if(dllCount EQUAL 0)
            message(FATAL_ERROR "Can't find target(${target}) dll: ${dllGlobPatten}")
        else()
            message(STATUS "Found target(${target}) dll: ${dllPath}")
        endif()
        set_property(TARGET ${target} ${appendOrNot} PROPERTY IMPORTED_LOCATION ${dllPath})
    else()
        set_property(TARGET ${target} ${appendOrNot} PROPERTY IMPORTED_LOCATION ${${libPath}})
    endif()
endfunction()

# 安装 dependency set , 只安装指定的目录下(递归)的文件。通常用来过滤掉系统本身的依赖文件
# @param[one_value_keywords] DESTINATION
# @param[multi_value_keywords] PATHS 如果没有指定该参数，则默认为 ${CMAKE_SOURCE_DIR}
function(thirdparty_install_dependency_under_dir dependencySet)
    cmake_parse_arguments(MYARG "" "DESTINATION" "PATHS;" ${ARGN})
    if(NOT MYARG_PATHS)
        set(MYARG_PATHS ${CMAKE_SOURCE_DIR})
    endif()
    foreach(dir ${MYARG_PATHS})
        string(REPLACE [[.]] [[\.]] pathRegex ${dir})
        string(REPLACE [[\]] [[\\]] pathRegex ${pathRegex})
        list(APPEND includeRegexList "${pathRegex}.*")
    endforeach()
    cmake_print_variables(includeRegexList)
    if(MYARG_DESTINATION)
        list(APPEND args "DESTINATION" "${MYARG_DESTINATION}")
    endif()
    install(
        RUNTIME_DEPENDENCY_SET
        ${dependencySet}
        ${args}
        POST_INCLUDE_REGEXES
        ${includeRegexList}
        POST_EXCLUDE_REGEXES
        ".*")
endfunction()

# 安装dll(so)到指定文件夹
# @param[options] ONLY_CHECK if has this param, only check, no install
# @param[one_value_keywords] DESTINATION
# @param[multi_value_keywords] TARGETS
function(thirdparty_install_imported_targets)
    cmake_parse_arguments(MYARG "ONLY_CHECK" "DESTINATION;" "TARGETS;" ${ARGN})
    if(NOT MYARG_DESTINATION)
        if(WIN32)
            set(MYARG_DESTINATION "bin")
        else()
            set(MYARG_DESTINATION "lib")
        endif()
    endif()
    file(REAL_PATH ${MYARG_DESTINATION} MYARG_DESTINATION BASE_DIRECTORY ${CMAKE_INSTALL_PREFIX} EXPAND_TILDE)
    if(MYARG_ONLY_CHECK)
        set(msgType STATUS)
    else()
        set(msgType DEPRECATION)
    endif()
    message(
        ${msgType}
        "thirdparty_install_imported_targets: MYARG_TARGETS=${MYARG_TARGETS}; MYARG_DESTINATION=${MYARG_DESTINATION}; MYARG_ONLY_CHECK=${MYARG_ONLY_CHECK};"
    )

    set(staticLibRegex [=[.*\.lib|.*\.a|.*\.a\..*]=])
    foreach(target ${MYARG_TARGETS})
        get_target_property(prop ${target} IMPORTED)
        if(NOT prop)
            message(WARNING "target(${target}) is not imported!")
            continue()
        endif()

        foreach(propName IMPORTED_LOCATION;IMPORTED_LOCATION_RELEASE;IMPORTED_LOCATION_DEBUG)
            get_target_property(prop ${target} ${propName})
            if(prop)
                cmake_path(GET prop FILENAME fileName)
                if(fileName MATCHES ${staticLibRegex})
                    message(STATUS "skip target(${target}) ${propName}: ${prop}")
                else()
                    message(STATUS "installing target(${target}) ${propName}: ${prop}")
                    if(NOT MYARG_ONLY_CHECK)
                        file(
                            INSTALL ${prop}
                            DESTINATION ${MYARG_DESTINATION}
                            FOLLOW_SYMLINK_CHAIN)
                        break()
                    endif()
                endif()
            endif()
        endforeach()

        # 递归安装依赖项
        get_target_property(deps ${target} INTERFACE_LINK_LIBRARIES_DIRECT)
        get_target_property(depsToAdd ${target} INTERFACE_LINK_LIBRARIES)
        if(deps)
            get_target_property(depsToRemove ${target} INTERFACE_LINK_LIBRARIES_DIRECT_EXCLUDE)
            if(depsToRemove)
                list(REMOVE_ITEM deps ${depsToRemove})
            endif()
            if(depsToAdd)
                list(APPEND deps ${depsToAdd})
            endif()
        elseif(depsToAdd)
            set(deps ${depsToAdd})
        endif()
        if(deps)
            list(REMOVE_DUPLICATES deps)
            message(STATUS "Recursive scanning target(${target}) dependency: ${deps}")
            foreach(oneDep ${deps})
                if(TARGET ${oneDep})
                    if(MYARG_ONLY_CHECK)
                        thirdparty_install_imported_targets(DESTINATION ${MYARG_DESTINATION} TARGETS ${oneDep}
                                                            ONLY_CHECK)
                    else()
                        thirdparty_install_imported_targets(DESTINATION ${MYARG_DESTINATION} TARGETS ${oneDep})
                    endif()
                elseif(EXISTS ${oneDep})
                    cmake_path(GET oneDep FILENAME fileName)
                    if(fileName MATCHES ${staticLibRegex})
                        message(STATUS "skip target(${target}) dependency: ${oneDep}")
                    else()
                        message(STATUS "installing target(${target}) dependency: ${oneDep}")
                        if(NOT MYARG_ONLY_CHECK)
                            file(
                                INSTALL ${oneDep}
                                DESTINATION ${MYARG_DESTINATION}
                                FOLLOW_SYMLINK_CHAIN)
                        endif()
                    endif()
                else()
                    message(STATUS "skip target(${target}) dependency: ${oneDep}")
                endif()
            endforeach()
        endif()
    endforeach()
endfunction()

#---------------------------------------------------------------------------------------
option(THIRD_PARTY_USE_VIDEO_AUDIO "Use video and audio libs" ON)
option(THIRD_PARTY_USE_MACHINE_LEARNING "Use machine learning libs" ON)

message(STATUS "CMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}")
if(ANDROID)
    # android.toolchain.cmake中设置 CMAKE_FIND_ROOT_PATH 到NDK根目录，并且只从这里查找
    # 会导致查找第三方库时find_library等类似API失败，因此添加该路径
    list(APPEND CMAKE_FIND_ROOT_PATH ${CMAKE_CURRENT_LIST_DIR})
endif()

set(G_3RD_PREFIX ${CMAKE_CURRENT_LIST_DIR}/3rd_root)
string(TOLOWER ${CMAKE_SYSTEM_NAME} OS_ROOT)
set(G_3RD_OS_PREFIX ${CMAKE_CURRENT_LIST_DIR}/3rd_root_${OS_ROOT})
include_directories(${G_3RD_PREFIX}/include ${G_3RD_PREFIX}/include_${OS_ROOT} ${G_3RD_OS_PREFIX}/include)
link_directories(${G_3RD_OS_PREFIX}/lib)
unset(OS_ROOT)

#---------------------------------------------------------------------------------------

# find_library, find_file等都要从CMAKE_PREFIX_PATH里面找
list(APPEND CMAKE_PREFIX_PATH ${G_3RD_OS_PREFIX})

# lua
add_library(thirdparty::lua SHARED IMPORTED)
thirdparty_set_imported_location(thirdparty::lua "lua" "lua.dll")
if(WIN32)
    target_compile_definitions(thirdparty::lua INTERFACE "LUA_BUILD_AS_DLL")
endif()

# fmt
find_package(fmt REQUIRED CONFIG)
add_library(thirdparty::fmt ALIAS fmt::fmt)

# spdlog
find_package(spdlog REQUIRED CONFIG)
add_library(thirdparty::spdlog ALIAS spdlog::spdlog)

# zlib
add_library(thirdparty::zlib SHARED IMPORTED)
thirdparty_set_imported_location(thirdparty::zlib "z" "zlib.dll")
target_compile_definitions(thirdparty::zlib INTERFACE "ZLIB_DLL")

# zstd
find_package(zstd REQUIRED CONFIG)
add_library(thirdparty::zstd ALIAS zstd::libzstd_shared)

# sqlite
add_library(thirdparty::sqlite SHARED IMPORTED)
thirdparty_set_imported_location(thirdparty::sqlite "sqlite3" "sqlite3.dll")
if(WIN32)
    target_compile_definitions(thirdparty::sqlite INTERFACE "SQLITE_API=__declspec(dllimport)")
endif()

# sqlite_cpp
find_package(SQLiteCpp REQUIRED CONFIG)
add_library(thirdparty::sqlite_cpp ALIAS SQLiteCpp)

# pugixml
find_package(pugixml REQUIRED CONFIG)
add_library(thirdparty::pugixml ALIAS pugixml::pugixml)

# openssl
add_library(thirdparty::openssl SHARED IMPORTED)
thirdparty_set_imported_location(thirdparty::openssl "ssl" "libssl*.dll")
add_library(thirdparty::openssl_crypto SHARED IMPORTED)
thirdparty_set_imported_location(thirdparty::openssl_crypto "crypto" "libcrypto*.dll")
target_link_libraries(thirdparty::openssl INTERFACE thirdparty::openssl_crypto)

# iconv
if(NOT WIN32)
    add_library(thirdparty::iconv SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::iconv "iconv" "")
endif()

# boost
set(Boost_NO_SYSTEM_PATHS ON)
file(
    GLOB Boost_ROOT
    LIST_DIRECTORIES TRUE
    "${G_3RD_OS_PREFIX}/boost_*/stage")
find_package(Boost REQUIRED COMPONENTS "ALL")
cmake_print_variables(Boost_VERSION Boost_INCLUDE_DIRS Boost_ALL_TARGETS)
include_directories(${Boost_INCLUDE_DIRS})
add_compile_definitions(
    # "BOOST_ASIO_DISABLE_STD_CHRONO"
    "BOOST_ASIO_NO_DEPRECATED" "BOOST_CHRONO_VERSION=2" "BOOST_FILESYSTEM_NO_DEPRECATED"
    "BOOST_FILESYSTEM_DISABLE_STATX" "BOOST_THREAD_VERSION=5" "BOOST_THREAD_QUEUE_DEPRECATE_OLD")
if(WIN32)
    # windows中ipc默认使用EventLog获取bootup time，基于此生成ipc的共享文件夹，但某些系统中可能获取失败。
    # 比如可能被某些清理软件清除掉了EventLog，也可能EventLog满了自动清除了。因此添加该宏定义，使用注册表中
    # HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters 下的BootId来读取bootup time。
    # 不过最推荐的做法是自己定义下面两个宏之一。注意：目录必须自己创建好，ipc对象的名称实质上就是文件名，必须合法。
    #   BOOST_INTERPROCESS_SHARED_DIR_PATH  //编译期可以固定下来的文件路径，末尾不要加'/'
    #   BOOST_INTERPROCESS_SHARED_DIR_FUNC  //运行期决定的路径，如果定义该宏，需要实现下面的函数。
    #   namespace boost {
    #       namespace interprocess {
    #           namespace ipcdetail {
    #               void get_shared_dir(std::string &shared_dir);
    #           }
    #       }
    #   }
    # bug参考: https://svn.boost.org/trac10/ticket/12137#no1
    # 文档参考: boost_1_69_0/doc/html/interprocess/acknowledgements_notes.html
    get_target_property(ZLIB_LIBRARIES thirdparty::zlib IMPORTED_IMPLIB)
    add_compile_definitions(
        "BOOST_INTERPROCESS_BOOTSTAMP_IS_SESSION_MANAGER_BASED"
        "BOOST_ZLIB_BINARY=${ZLIB_LIBRARIES}" #for "progma comment(lib, ...)"
    )
elseif(ANDROID)

else()
    # add_compile_definitions("BOOST_LOCALE_ENABLE_CHAR16_T" "BOOST_LOCALE_ENABLE_CHAR32_T")
endif()

if(THIRD_PARTY_USE_VIDEO_AUDIO)
    # jpeg
    find_package(libjpeg-turbo REQUIRED CONFIG)
    add_library(thirdparty::jpeg ALIAS libjpeg-turbo::turbojpeg)

    # yuv
    add_library(thirdparty::yuv SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::yuv "yuv" "yuv.dll")
    target_compile_definitions(thirdparty::yuv INTERFACE "LIBYUV_USING_SHARED_LIBRARY")

    # SDL2
    find_package(SDL2 REQUIRED CONFIG)
    add_library(thirdparty::sdl2 ALIAS SDL2::SDL2)

    # opus
    find_package(Opus REQUIRED CONFIG)
    add_library(thirdparty::opus ALIAS Opus::opus)

    # x264
    add_library(thirdparty::x264 SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::x264 "x264" "*x264*.dll")
    target_compile_definitions(thirdparty::x264 INTERFACE "X264_API_IMPORTS")

    if(NOT ANDROID)
        # x265
        add_library(thirdparty::x265 SHARED IMPORTED)
        thirdparty_set_imported_location(thirdparty::x265 "x265" "*x265*.dll")
    endif()

    if(NOT WIN32)
        # vpx
        add_library(thirdparty::vpx STATIC IMPORTED)
        thirdparty_set_imported_location(thirdparty::vpx "vpx" "")
    endif()

    # ffmpeg: FFMPEG_LIBRARIES
    if(WIN32)
        set(TEMP_VAR "${G_3RD_OS_PREFIX}/bin")
    else()
        set(TEMP_VAR "")
    endif()
    add_library(thirdparty::ffmpeg_avutil SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_avutil "avutil" "avutil*.dll" LIB_PATHS ${TEMP_VAR})

    add_library(thirdparty::ffmpeg_swscale SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_swscale "swscale" "swscale*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_swscale INTERFACE thirdparty::ffmpeg_avutil)

    add_library(thirdparty::ffmpeg_postproc SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_postproc "postproc" "postproc*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_postproc INTERFACE thirdparty::ffmpeg_avutil)

    add_library(thirdparty::ffmpeg_swresample SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_swresample "swresample" "swresample*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_swresample INTERFACE thirdparty::ffmpeg_avutil)

    add_library(thirdparty::ffmpeg_avcodec SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_avcodec "avcodec" "avcodec*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_avcodec INTERFACE thirdparty::ffmpeg_swresample thirdparty::opus
                                                               thirdparty::x264)
    if(NOT ANDROID)
        target_link_libraries(thirdparty::ffmpeg_avcodec INTERFACE thirdparty::x265)
    endif()
    if(NOT WIN32)
        target_link_libraries(thirdparty::ffmpeg_avcodec INTERFACE thirdparty::vpx thirdparty::iconv thirdparty::zlib)
    endif()

    add_library(thirdparty::ffmpeg_avformat SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_avformat "avformat" "avformat*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_avformat INTERFACE thirdparty::ffmpeg_avcodec thirdparty::openssl)

    add_library(thirdparty::ffmpeg_avfilter SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_avfilter "avfilter" "avfilter*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_avfilter INTERFACE thirdparty::ffmpeg_swscale thirdparty::ffmpeg_postproc
                                                                thirdparty::ffmpeg_avformat)

    add_library(thirdparty::ffmpeg_avdevice SHARED IMPORTED)
    thirdparty_set_imported_location(thirdparty::ffmpeg_avdevice "avdevice" "avdevice*.dll" LIB_PATHS ${TEMP_VAR})
    target_link_libraries(thirdparty::ffmpeg_avdevice INTERFACE thirdparty::ffmpeg_avfilter thirdparty::sdl2)

    add_library(thirdparty::ffmpeg ALIAS thirdparty::ffmpeg_avdevice)
    # if(CMAKE_SIZEOF_VOID_P EQUAL 8) # 目前没有编译32位的ffmpeg
    #     # ffmpeg
    #     list(
    #         APPEND
    #         FFMPEG_LIBS
    #         avdevice
    #         avfilter
    #         avformat
    #         avcodec
    #         postproc
    #         swscale
    #         swresample
    #         avutil)
    #     if(WIN32)
    #         # x264 x265 opus
    #     elseif(ANDROID)
    #         list(APPEND FFMPEG_LIBS x264 opus iconv)
    #     else()
    #         list(APPEND FFMPEG_LIBS x264 x265 opus)
    #     endif()

    #     foreach(VAR ${FFMPEG_LIBS})
    #         if(WIN32)
    #             set(ONE_LIB ${G_3RD_OS_PREFIX}/bin/${VAR}.lib)
    #             file(GLOB ONE_RUNTIME ${G_3RD_OS_PREFIX}/bin/${VAR}*.dll)
    #         else()
    #             set(ONE_LIB ${G_3RD_OS_PREFIX}/lib/lib${VAR}.so)
    #             set(ONE_RUNTIME ${ONE_LIB})
    #         endif()
    #         ensure_file_exists(${ONE_LIB})
    #         list(APPEND FFMPEG_LIBRARIES ${ONE_LIB})
    #         ensure_file_exists(${ONE_RUNTIME})
    #         list(APPEND FFMPEG_RUNTIME_LIBRARIES ${ONE_RUNTIME})
    #     endforeach()

    #     if(WIN32)
    #         unset(FFMPEG_LIBS)
    #         list(APPEND FFMPEG_LIBS libx264 libx265 opus)
    #         foreach(VAR ${FFMPEG_LIBS})
    #             set(ONE_LIB ${G_3RD_OS_PREFIX}/lib/${VAR}.lib)
    #             ensure_file_exists(${ONE_LIB})
    #             list(APPEND FFMPEG_LIBRARIES ${ONE_LIB})
    #             file(GLOB ONE_RUNTIME ${G_3RD_OS_PREFIX}/bin/${VAR}*.dll)
    #             ensure_file_exists(${ONE_RUNTIME})
    #             list(APPEND FFMPEG_RUNTIME_LIBRARIES ${ONE_RUNTIME})
    #         endforeach()
    #     endif()
    #     unset(ONE_LIB)
    #     unset(ONE_RUNTIME)
    #     unset(FFMPEG_LIBS)

    #     # sdl2
    #     find_library(SDL2_LIBRARIES NAMES SDL2 SDL2d REQUIRED)
    #     cmake_print_variables(SDL2_LIBRARIES)
    #     ensure_file_exists(${SDL2_LIBRARIES})
    #     if(ANDROID)
    #         find_library(
    #             SDL2_HIDAPI
    #             NAMES hidapi hidapid
    #             PATHS ${G_3RD_OS_PREFIX}/lib REQUIRED)
    #         if(SDL2_HIDAPI)
    #             list(APPEND SDL2_LIBRARIES ${SDL2_HIDAPI})
    #             unset(SDL2_HIDAPI)
    #         endif()
    #     endif()
    #     if(WIN32)
    #         file(GLOB SDL2_RUN_LIBRARIES ${G_3RD_OS_PREFIX}/bin/SDL2*.dll)
    #         ensure_file_exists(${SDL2_RUN_LIBRARIES})
    #     else()
    #         set(SDL2_RUN_LIBRARIES ${SDL2_LIBRARIES})
    #         if(ANDROID)
    #             find_path(
    #                 SDL2_JAVA
    #                 NAMES java
    #                 PATHS ${G_3RD_OS_PREFIX}/lib)
    #             ensure_file_exists(${SDL2_JAVA})
    #             list(APPEND SDL2_RUN_LIBRARIES ${SDL2_JAVA}/java)
    #             unset(SDL2_JAVA)
    #         endif()
    #     endif()
    #     if(ANDROID)
    #         # 添加依赖的系统库
    #         list(
    #             APPEND
    #             SDL2_LIBRARIES
    #             GLESv2
    #             GLESv1_CM
    #             android
    #             log
    #             c++_shared
    #             m
    #             dl
    #             c)
    #     endif()
    #     list(APPEND FFMPEG_LIBRARIES ${SDL2_LIBRARIES})
    #     list(APPEND FFMPEG_RUNTIME_LIBRARIES ${SDL2_RUN_LIBRARIES})
    #     unset(SDL2_HIDAPI)
    #     unset(SDL2_LIBRARIES)
    #     unset(SDL2_RUN_LIBRARIES)

    #     # 已经编译的其他依赖库openssl,zlib
    #     list(APPEND G_ALL_THIRD_PARTY_RUNTIME_LIBS ${FFMPEG_RUNTIME_LIBRARIES})
    #     list(APPEND FFMPEG_LIBRARIES ${OPENSSL_LIBRARIES} ${ZLIB_LIBRARIES})
    #     list(APPEND FFMPEG_RUNTIME_LIBRARIES ${OPENSSL_RUNTIME_LIBRARIES} ${ZLIB_RUNTIME_LIBRARIES})
    # endif()

    if(WIN32)
        # glew
        add_library(thirdparty::glew SHARED IMPORTED)
        thirdparty_set_imported_location(thirdparty::glew "glew32" "glew32.dll")
    endif()
endif(THIRD_PARTY_USE_VIDEO_AUDIO)

if(THIRD_PARTY_USE_MACHINE_LEARNING AND (NOT WIN32))
    if(WIN32)
        # MSVC enables FMA with /arch:AVX2; no separate flags for F16C, POPCNT
        # Ref. FMA (under /arch:AVX2): https://docs.microsoft.com/en-us/cpp/build/reference/arch-x64
        # Ref. F16C (2nd paragraph): https://walbourn.github.io/directxmath-avx2/
        # Ref. POPCNT: https://docs.microsoft.com/en-us/cpp/intrinsics/popcnt16-popcnt-popcnt64
        add_compile_options(/arch:AVX2)
    else()
        add_compile_options(-mavx2 -mfma -mf16c -mpopcnt)
    endif()

    # openblas
    find_package(OpenBLAS REQUIRED CONFIG)
    add_library(thirdparty::openblas ALIAS OpenBLAS::OpenBLAS)

    # superlu
    find_package(superlu REQUIRED CONFIG)
    add_library(thirdparty::superlu ALIAS superlu::superlu)

    # eigen3
    find_package(Eigen3 REQUIRED CONFIG)
    add_library(thirdparty::eigen3 ALIAS Eigen3::Eigen)

    # hdf5
    find_package(HDF5 REQUIRED CONFIG)
    add_library(thirdparty::hdf5 ALIAS hdf5-shared)
    add_library(thirdparty::hdf5_tools ALIAS hdf5_tools-shared)
    add_library(thirdparty::hdf5_hl ALIAS hdf5_hl-shared)

    # armadillo
    find_package(Armadillo REQUIRED CONFIG)
    add_library(thirdparty::armadillo ALIAS armadillo)

    # faiss
    find_package(OpenMP REQUIRED) # faiss 依赖 openmp
    find_package(faiss REQUIRED CONFIG)
    add_library(thirdparty::faiss ALIAS faiss_avx2)
endif()

# pybind11
if(POLICY CMP0148)
    cmake_policy(SET CMP0148 OLD)
endif()
find_package(pybind11 REQUIRED CONFIG)
add_library(thirdparty::pybind11 ALIAS pybind11::pybind11)

#----下面这些库以源代码方式使用-----------------------------------------------------------------

if(WIN32)
    # minhook: MINHOOK_SOURCE_CODE
    set(TEMP_VAR ${G_3RD_PREFIX}/src_code/minhook)
    include(${TEMP_VAR}/minhook.cmake)
    include_directories(${TEMP_VAR}/include)
    function(source_group_Minhook)
        source_group(TREE ${G_3RD_PREFIX}/src_code FILES ${MINHOOK_SOURCE_CODE})
    endfunction()
endif()

#------------------------------------------------------------------------------------------

unset(TEMP_VAR)
list(POP_BACK CMAKE_PREFIX_PATH)
