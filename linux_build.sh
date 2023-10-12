#!/bin/bash
set -e
set -x

G_BASE_PATH=$(cd `dirname $0`; pwd)
cd ${G_BASE_PATH}
source set_env.sh
set -x

# 音视频
BUILD_VIDEO_AUDIO=1

# 机器学习
BUILD_MACHINE_LEARNING=1

#--------------------------------------------------------------------------------------------

if ((${BUILD_VIDEO_AUDIO})) ; then
    read -p "Build SDL2 Video?[y/N]" G_SDL2_VIDEO
    if [ "${G_SDL2_VIDEO}" != "y" ] && [ "${G_SDL2_VIDEO}" != "Y" ] ; then
        G_SDL2_VIDEO="-DSDL_VIDEO=OFF"
    else
        G_SDL2_VIDEO="-DSDL_VIDEO=ON"
    fi
fi

#============================================================================================

\rm -rf build_tmp
mkdir -p build_tmp

# 设置 CFLAGS, CXXFLAGS, LDFLAGS, G_CMAKE_PLATFORM_CONFIG, 编译时查找依赖库
G_INSTALL_ROOT="${G_BASE_PATH}/3rd_root_${G_TARGET_OS}"
export CFLAGS="${CFLAGS} -I${G_BASE_PATH}/3rd_root/include -I${G_INSTALL_ROOT}/include"
export CXXFLAGS="${CXXFLAGS} -I${G_BASE_PATH}/3rd_root/include -I${G_INSTALL_ROOT}/include"
LIB_PATH="${G_INSTALL_ROOT}/lib"
mkdir -p ${LIB_PATH}
cd ${G_INSTALL_ROOT}
ln -fs lib lib64  # some libs install to lib64
if [ -n "${LDFLAGS}" ]; then
    export LDFLAGS="${LDFLAGS} -L${LIB_PATH}"
else
    export LDFLAGS="-L${LIB_PATH}"
fi

# CMAKE_FIND_ROOT_PATH: 优先从自己的目录中查找。如果是安卓交叉编译，android.toolchain.cmake中设置 CMAKE_FIND_ROOT_PATH 到NDK根目录，并且只从这里查找会导致查找第三方库时find_library等类似API失败。
# CMAKE_INSTALL_RPATH: 设置rpath, 避免编译时找不到间接依赖库。
G_INSTALL_RPATH="\$ORIGIN:\$ORIGIN/lib:${G_INSTALL_ROOT}/lib"
G_CMAKE_COMMON="${G_CMAKE_PLATFORM_CONFIG} -D CMAKE_FIND_ROOT_PATH=${G_INSTALL_ROOT} -D CMAKE_BUILD_TYPE=${G_BUILD_TYPE} -D CMAKE_INSTALL_PREFIX=${G_INSTALL_ROOT} -D CMAKE_INSTALL_RPATH=${G_INSTALL_RPATH} -D CMAKE_EXPORT_COMPILE_COMMANDS=ON"

# 修改CMakeLists.txt中的Version
function ChangeCmakeVersion() {
    perl -pi -e 's/(CMAKE_MINIMUM_REQUIRED\(VERSION)\s+[\d\.]+/$1 3.14/ig' CMakeLists.txt
}

# pkg-config 是从环境变量 PKG_CONFIG_PATH 里面找.pc文件配置参数
export PKG_CONFIG_PATH="${G_INSTALL_ROOT}/lib/pkgconfig"

# pdg-config中 private 的libs加到 Libs 中，避免ffmpeg链接时会报找不到依赖库
function PkgconigAddPrivLibsToPubLibs() {
    PRIVE_LIBS=$(perl -n -e 'm/Libs.private:(.*)/; if($1){print $1; last;}' $1)
    PRIVE_LIBS=$(echo $PRIVE_LIBS | perl -n -e 's/\//\\\//g; print;')
    perl -pi -e "s/(Libs:.*)/$& ${PRIVE_LIBS} /ig" $1
    unset PRIVE_LIBS
}

# ---- lua --------------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xf src_package/lua*.tar.gz -C build_tmp/
    cd build_tmp/lua*/
    \cp -rf ${G_BASE_PATH}/my_conf/lua_CMakeLists.txt ./CMakeLists.txt
    mkdir build && cd build
    cmake ${G_CMAKE_COMMON} ..
    make -j${G_CPU_CORE}
    make install
fi

# ---- zlib ------------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    unzip -qu src_package/zlib*.zip -d build_tmp
    cd build_tmp/zlib*
    mkdir build
    cd build
    cmake ${G_CMAKE_COMMON} ..
    make -j${G_CPU_CORE}
    make install
    \rm -rf ${LIB_PATH}/lib
fi

# ---- brotli ---------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xf src_package/brotli*.tar.gz -C build_tmp/
    cd build_tmp/brotli*/
    mkdir out
    cd out
    cmake ${G_CMAKE_COMMON} ..
    cmake --build . --config ${G_BUILD_TYPE} --target "install/strip"
fi

# ---- sqlite3 -----------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    unzip -qu src_package/sqlite*.zip -d build_tmp
    cd build_tmp/sqlite*/
    \cp -rf ${G_BASE_PATH}/my_conf/sqlite_CMakeLists.txt ./CMakeLists.txt
    mkdir build
    cd build
    cmake ${G_CMAKE_COMMON} ..
    make
    make install
fi

# ---- SQLiteCPP -----------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    unzip -qu src_package/SQLiteCpp*.zip -d build_tmp
    cd build_tmp/SQLiteCpp*/
    mkdir build
    cd build
    cmake ${G_CMAKE_COMMON} -D SQLITECPP_INTERNAL_SQLITE=OFF ..
    make
    make install
fi

# ---- pugixml -----------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xf src_package/pugixml*.tar.gz -C build_tmp
    cd build_tmp/pugixml*/
    mkdir build
    cd build
    cmake ${G_CMAKE_COMMON} ..
    make
    make install
fi

# ---- openssl ---------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xf src_package/openssl*.tar.gz -C build_tmp/
    cd build_tmp/openssl*/
    if [ "$G_TARGET_OS" = "android" ] ; then
        OPENSSL_CONFIG="perl Configure android-arm64"
    else
        OPENSSL_CONFIG="./config"
    fi
    OLD_CPPFLAGS=${CPPFLAGS}
    export CPPFLAGS="${CPPFLAGS} -D__ANDROID_API__=${ANDROID_NATIVE_API_LEVEL}"
    ${OPENSSL_CONFIG} --${G_BUILD_TYPE,,} --prefix="${G_INSTALL_ROOT}" --libdir="lib" --openssldir=./SSL shared -DOPENSSL_NO_ASYNC
    make -j${G_CPU_CORE}
    # 不安装doc，生成doc太慢了
    make install_sw install_ssldirs
    export CPPFLAGS=${OLD_CPPFLAGS}
    unset OLD_CPPFLAGS
fi

# ---- maria -----------------------------------
if ((1)) ; then
    if [ "${G_TARGET_OS}" = "linux" ] ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/mariadb-connector-c-*.tar.gz -C build_tmp/
        cd build_tmp/mariadb-connector-c-*/
        ChangeCmakeVersion
        # plugin改为静态库，集成到libmariadb.so中，方便使用
        perl -pi -e 's/DEFAULT DYNAMIC/DEFAULT STATIC/g' plugins/auth/CMakeLists.txt
        perl -pi -e 's/DEFAULT DYNAMIC/DEFAULT STATIC/g' plugins/pvio/CMakeLists.txt
        mkdir build
        cd build
        OLD_CFLAGS=${CFLAGS}
        export CFLAGS="${CFLAGS} -DMYSQL_CLIENT=1"
        cmake ${G_CMAKE_COMMON} -D WITH_EXTERNAL_ZLIB=ON -D ZLIB_ROOT=${G_INSTALL_ROOT} -D WITH_SSL=OPENSSL -D OpenSSL_ROOT=${G_INSTALL_ROOT} ..
        make -j${G_CPU_CORE}
        make install
        export CFLAGS="${OLD_CFLAGS}"
        unset OLD_CFLAGS
        # patchelf --set-rpath ${G_INSTALL_RPATH} ${G_INSTALL_ROOT}/lib/mariadb/*.so
        # patchelf --set-rpath ${G_INSTALL_RPATH} ${G_INSTALL_ROOT}/lib/mariadb/plugin/*.so
    fi
fi

# ---- maria-cpp -----------------------------------
if ((1)) ; then
    if [ ${G_TARGET_OS} = "linux" ] ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/mariadb-connector-cpp-*.tar.gz -C build_tmp/
        cd build_tmp/mariadb-connector-cpp-*/
        \rm -rf libmariadb test
        mkdir build
        cd build
        OLD_CXXFLAGS=${CXXFLAGS}
        OLD_LDFLAGS=${LDFLAGS}
        export CXXFLAGS="${CXXFLAGS} -I${G_INSTALL_ROOT}/include/mariadb"
        export LDFLAGS="${LDFLAGS} -L${G_INSTALL_ROOT}/lib/mariadb"
        cmake ${G_CMAKE_COMMON} -DINSTALL_LIB_SUFFIX="lib" -DMARIADB_LINK_DYNAMIC=ON ..
        make -j${G_CPU_CORE}
        make install
        export CXXFLAGS="${OLD_CXXFLAGS}"
        export LDFLAGS="${OLD_LDFLAGS}"
        unset OLD_CXXFLAGS
        unset OLD_LDFLAGS
    fi
fi

# ---- iconv ---------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xf src_package/libiconv*.tar.gz -C build_tmp/
    cd build_tmp/libiconv*
    if [ "${G_TARGET_OS}" = "android" ] ; then
        ./configure --host=aarch64-linux-android --prefix=${G_INSTALL_ROOT}
    else
        ./configure --prefix=${G_INSTALL_ROOT}
    fi
    make -j${G_CPU_CORE}
    make install
fi

# ---- boost ----------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    for old_boost in ${G_INSTALL_ROOT}/boost_*
    do
        \rm -rf $old_boost
    done
    tar -xf src_package/boost_*.tar.gz -C ${G_INSTALL_ROOT}
    cd ${G_INSTALL_ROOT}/boost_*

    if [ "$G_TARGET_OS" = "android" ] ; then
        # 生成构建工具b2，b2运行在linux上，不是android
        CROSS_CC=${CC}
        CROSS_CXX=${CXX}
        export CC=""
        export CXX=""
        bash bootstrap.sh
        export CC=${CROSS_CC}
        export CXX=${CROSS_CXX}
        unset CROSS_CC CROSS_CXX
        # compiler
        echo "using clang : arm64 : ${CXX} : ;" > user-config.jam
        BOOST_TOOLSET="toolset=clang-arm64 target-os=android architecture=arm binary-format=elf abi=aapcs "
        BOOST_LOCALE_CONFIG="-sICONV_PATH=${ICONV_ROOT}"
    else
        bash bootstrap.sh
        # compiler
        echo "" > user-config.jam
        if [ "${CC}" = "clang" ] ; then
            BOOST_TOOLSET="toolset=clang "
        else
            BOOST_TOOLSET=""
        fi
        BOOST_LOCALE_CONFIG="define=BOOST_LOCALE_ENABLE_CHAR16_T define=BOOST_LOCALE_ENABLE_CHAR32_T "

        # statx 是linux kernel 4.11才加入的，如果在centos7上的ubuntu docker中运行，能编译但运行就会出错。
        DISABLE_STATX="Y"
        if [ "${G_NATIVE_BUILD}" = 'Y' ]; then
            KERNEL_VERSION=$(cat /proc/version | perl -p -e 's/^Linux\s+version\s+(\d+\.\d+).*/$1/ig')
            if (($(echo "$KERNEL_VERSION >= 4.11" | bc))) ; then
                DISABLE_STATX="N"
            fi
            unset KERNEL_VERSION
        fi
        if [ "${DISABLE_STATX}" = "Y" ]; then
            echo '#error "disable statx"' >> libs/filesystem/config/has_statx.cpp
            echo '#error "disable statx_syscall"' >> libs/filesystem/config/has_statx_syscall.cpp
        fi
        unset DISABLE_STATX
    fi

    # zlib
    echo "using zlib : 1.2.11 : <include>${G_INSTALL_ROOT}/include <search>${G_INSTALL_ROOT}/lib ;" >> user-config.jam

    # python
    if command_exists python3 ; then
        PYTHON=python3
    fi
    BOOST_PYTHON_CONFIG="--without-python"
    # BOOST_PYTHON_CONFIG=""
    if [ -z "${BOOST_PYTHON_CONFIG}" ] && [ ${PYTHON} ] ; then
        PYTHON_VER=$(${PYTHON} -V)
        PYTHON_INCLUDE_DIR=$(${PYTHON} -c '
    import sysconfig
    print(sysconfig.get_path("include"), end="")
        ')
        PYTHON_LIB_DIR=$(${PYTHON} -c '
    import sysconfig
    print(sysconfig.get_path("stdlib"), end="")
        ')
        PYTHON_CONFIG="using python : ${PYTHON_VER:7:3} : ${PYTHON} : ${PYTHON_INCLUDE_DIR} : ${PYTHON_LIB_DIR} ;"
        echo ${PYTHON_CONFIG}
        echo ${PYTHON_CONFIG} >> user-config.jam
        unset PYTHON PYTHON_VER PYTHON_INCLUDE_DIR PYTHON_LIB_DIR
    fi

    # define=BOOST_THREAD_VERSION=5 指定了这个宏之后，必须指定 BOOST_THREAD_USES_DATETIME, 否则boost_log编译失败。
    BOOST_COMMON_DEFINE="define=BOOST_NO_AUTO_PTR define=BOOST_ASIO_DISABLE_STD_CHRONO define=BOOST_CHRONO_VERSION=2 define=BOOST_FILESYSTEM_NO_DEPRECATED define=BOOST_THREAD_VERSION=5 define=BOOST_THREAD_USES_DATETIME define=BOOST_THREAD_QUEUE_DEPRECATE_OLD "
    ./b2 stage ${BOOST_TOOLSET} -d 2 --debug-configuration --user-config=./user-config.jam --layout=system --hash threading=multi link=static address-model=64 variant=${G_BUILD_TYPE,,} ${BOOST_COMMON_DEFINE} ${BOOST_LOCALE_CONFIG} ${BOOST_PYTHON_CONFIG} cflags="${CFLAGS}" cxxflags="${CXXFLAGS}" linkflags="${LDFLAGS}"
    # boost 1.78 bug, fiber,tacktrace 没有安装
    # cp -n ./bin.v2/libs/*/build/*/libboost*.a ./stage/lib
    \rm -rf ./bin.v2
fi
BOOST_ROOT=$(cd ${G_INSTALL_ROOT}/boost_*;pwd)
G_CMAKE_BOOST_CONFIG="-D BOOST_ROOT=${BOOST_ROOT} -D BOOST_INCLUDEDIR=${BOOST_ROOT}/boost -D BOOST_LIBRARYDIR=${BOOST_ROOT}/stage/lib"
unset BOOST_ROOT

if ((${BUILD_VIDEO_AUDIO})) ; then
    # ---- jpeg -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/libjpeg-turbo*.tar.gz -C build_tmp
        cd build_tmp/libjpeg-turbo*
        ChangeCmakeVersion
        perl -pi -e "s/\{CMAKE_INSTALL_INCLUDEDIR\}/$&\/libjpeg/g" CMakeLists.txt
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D ENABLE_STATIC=OFF ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- yuv -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        unzip -qu src_package/libyuv*.zip -d build_tmp
        cd build_tmp/libyuv*
        \cp -rf ${G_BASE_PATH}/my_conf/yuv_CMakeLists.txt ./CMakeLists.txt
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- SDL2 ----------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/SDL2*.tar.gz -C build_tmp
        cd build_tmp/SDL2*
        ChangeCmakeVersion
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D BUILD_SHARED_LIBS=ON "${G_SDL2_VIDEO}" ..
        make -j${G_CPU_CORE}
        make install
        if [ "${G_TARGET_OS}" = "android" ] ; then
            # android上必须通过java层初始化jni环境，否则无法使用。因此拷贝官方提供的java初始化代码。
            if [ -d ${G_INSTALL_ROOT}/lib/java ] ; then
                \rm -rf ${G_INSTALL_ROOT}/lib/java
            fi
            cp -rf ../android-project/app/src/main/java ${G_INSTALL_ROOT}/lib
        fi
        if [ "${G_BUILD_TYPE}" = "Debug" ] ; then
            # SDL2 debug模式生成的pkgconfig是错误的
            perl -pi -e "s/-lSDL2/-lSDL2d/g" ${PKG_CONFIG_PATH}/sdl2.pc
        fi
    fi

    #----x264-------------------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        if [ "${G_BUILD_TYPE}" = "Debug" ] ; then
            X264_BUILD_CONFIG="--enable-debug"
        else
            X264_BUILD_CONFIG=""
        fi
        if [ "${G_TARGET_OS}" = "android" ] ; then
            X264_COMPILE_CONFIG="--host=aarch64-linux-android --cross-prefix=aarch64-linux-android- --sysroot=${ANDROID_NDK_SYSROOT}"
        else
            X264_COMPILE_CONFIG=""
        fi
        tar -xf src_package/x264*.tar.bz2 -C build_tmp
        cd build_tmp/x264*
        # --enable-pic 必须，汇编代码不受-fPIC影响
        ./configure --prefix=${G_INSTALL_ROOT} --enable-shared --enable-pic ${X264_BUILD_CONFIG} ${X264_COMPILE_CONFIG}
        unset X264_BUILD_CONFIG X264_COMPILE_CONFIG
        make -j${G_CPU_CORE}
        make install
        PkgconigAddPrivLibsToPubLibs ${PKG_CONFIG_PATH}/x264.pc
    fi

    #----x265-------------------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        # 汇编代码不支持android平台，性能差，不编译了；
        if [ "${G_TARGET_OS}" = "linux" ] ; then
            tar -xf src_package/x265*.tar.gz -C build_tmp
            cd build_tmp/x265*
            mkdir cmake_build
            cd cmake_build
            cmake ${G_CMAKE_COMMON} ../source
            make -j${G_CPU_CORE}
            make install
        fi
    fi

    #----libvpx-------------------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        unzip -qu src_package/libvpx-*.zip -d build_tmp
        cd build_tmp/libvpx-*/build
        if [ "${G_BUILD_TYPE}" = "Debug" ] ; then
            LIBVPX_BUILD_CONFIG="--enable-debug"
        else
            LIBVPX_BUILD_CONFIG="--enable-optimizations"
        fi
        if [ "${G_TARGET_OS}" = "android" ] ; then
            LIBVPX_BUILD_CONFIG="${LIBVPX_BUILD_CONFIG} --target=arm64-android-gcc"
        else
            LIBVPX_BUILD_CONFIG="${LIBVPX_BUILD_CONFIG} --target=x86_64-linux-gcc"
        fi
        # android都不支持动态库 --enable-runtime-cpu-detect 
        ../configure --prefix=${G_INSTALL_ROOT} --log=yes --enable-pic ${LIBVPX_BUILD_CONFIG} --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth --enable-vp9-postproc --enable-onthefly-bitpacking --enable-vp9-temporal-denoising
        make -j${G_CPU_CORE}
        make install
        PkgconigAddPrivLibsToPubLibs ${PKG_CONFIG_PATH}/vpx.pc
    fi

    #----libopus-------------------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/opus*.tar.gz -C build_tmp
        cd build_tmp/opus*
        printf '%s\n' \
            "set(BUILD_SHARED_LIBS ON)" \
            "set(CMAKE_INSTALL_LIBDIR lib)" \
            > opus_buildtype.cmake
        mkdir cmake_build
        cd cmake_build
        cmake ${G_CMAKE_COMMON} ..
        make -j${G_CPU_CORE}
        make install
        PkgconigAddPrivLibsToPubLibs ${PKG_CONFIG_PATH}/opus.pc
    fi

    #----ffmpeg-------------------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/ffmpeg*.tar.xz -C build_tmp
        cd build_tmp/ffmpeg*
        if [ "${G_BUILD_TYPE}" = "Debug" ] ; then
            FFMPEG_BUILD_CONFIG="--enable-debug --disable-optimizations --disable-stripping "
        else
            FFMPEG_BUILD_CONFIG="--disable-debug "
        fi

        if [ "${G_TARGET_OS}" = "android" ] ; then
            FFMPEG_COMPILE_CONFIG="--cc=${CC} --cxx=${CXX} --enable-cross-compile --arch=aarch64 --target-os=android --cross-prefix=aarch64-linux-android- --sysroot=${ANDROID_NDK_SYSROOT}"
            # android sdl2的pkgconfig写的是错的，且sdl2对于ffmpeg主要是开发辅助的作用
            FFMPEG_3RD_LIB_CONFIG="--disable-sdl2 --enable-libx264 --enable-libopus --enable-libvpx --enable-openssl "
        else
            FFMPEG_COMPILE_CONFIG="--cc=${CC} --cxx=${CXX}"
            FFMPEG_3RD_LIB_CONFIG="--enable-libx264 --enable-libx265 --enable-libopus --enable-libvpx --enable-openssl "
        fi

        # ffmpeg交叉编译时默认使用${cross-prefix}-pkg-config，不一定存在，存在也可能有bug(ubuntu20中mingw的pkg-config工具)，
        # 因此明确指明pkg-config工具
        ./configure --pkg-config=pkg-config --prefix=${G_INSTALL_ROOT} ${FFMPEG_BUILD_CONFIG} --enable-shared --disable-static --enable-pic ${FFMPEG_COMPILE_CONFIG} --extra-cflags="${CFLAGS}" --extra-cxxflags="${CXXFLAGS}" --extra-ldflags="${LDFLAGS}" --enable-gpl --enable-nonfree ${FFMPEG_3RD_LIB_CONFIG}
        make -j${G_CPU_CORE}
        make install
        if [ "${G_TARGET_OS}" = "linux" ] ; then
            cd ${G_INSTALL_ROOT}/lib
            # 优化软连接：
            # 原本的状态：比如 
            # libavcodec.so -> libavcodec.so.58.91.100 
            # libavcodec.so.58 -> libavcodec.so.58.91.100
            # libavformat.so 依赖 libavcodec.so.58
            # 编译的时候 -lavformat -lavcodec，安装时候递归拷贝libavcodec.so,libavformat.so，运行就会报找不到so。因为libavformat.so
            # 依赖的是libavcodec.so.58，不是libavcodec.so或libavcodec.so.58.91.100，还必须把libavcodec.so.58这个软连接单独拷贝。
            for item in avutil swresample swscale postproc avcodec avformat avfilter avdevice
            do
                \rm -rf lib${item}.so
                TARGET_SO=$(find . -regex ".*lib${item}\.so\.\w+")
                ln -s ${TARGET_SO#*/} lib${item}.so
            done
            unset TARGET_SO
        fi
    fi
fi

if ((${BUILD_MACHINE_LEARNING})) && [ "$G_TARGET_OS" = "linux" ]; then
    # ---- OpenBLAS -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/OpenBLAS*.tar.gz -C build_tmp
        cd build_tmp/OpenBLAS*
        ChangeCmakeVersion
        perl -pi -e "s/set_target_properties.*?LIBRARY_OUTPUT_NAME_DEBUG.*/# $&/ig" CMakeLists.txt
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D BUILD_SHARED_LIBS=ON -D NUM_THREADS=64 ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- superlu -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        unzip -qu src_package/superlu*.zip -d build_tmp
        cd build_tmp/superlu*
        ChangeCmakeVersion
        perl -pi -e "s/\{CMAKE_INSTALL_INCLUDEDIR\}/$&\/superlu/g" SRC/CMakeLists.txt
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D USE_XSDK_DEFAULTS_DEFAULT=TRUE -D BLA_VENDOR=OpenBLAS -D BUILD_SHARED_LIBS=ON ..
        make -j${G_CPU_CORE}
        make install
    fi
    
    # ---- hdf5 ----------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/hdf5*.tar.gz -C build_tmp
        cd build_tmp/hdf5*
        perl -pi -e 's/(set\s*?\(CMAKE_DEBUG_POSTFIX).*/$1 "")/ig' config/cmake_ext_mod/HDFMacros.cmake
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D HDF5_ENABLE_Z_LIB_SUPPORT=ON -D BUILD_TESTING=OFF -D ONLY_SHARED_LIBS=ON -D HDF5_INSTALL_INCLUDE_DIR="include/hdf5" ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- armadillo -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/armadillo-*.tar.xz -C build_tmp
        cd build_tmp/armadillo*
        ChangeCmakeVersion
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D CMAKE_INCLUDE_PATH=${G_INSTALL_ROOT}/include/superlu ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- ensmallen -------------------------------------------------
    # todo: header only
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/ensmallen*.tar.gz -C build_tmp
        cd build_tmp/ensmallen*
        ChangeCmakeVersion
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- cereal -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        unzip -qu src_package/cereal*.zip -d build_tmp
        cd build_tmp/cereal*
        ChangeCmakeVersion
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} ${G_CMAKE_BOOST_CONFIG} -D BUILD_SANDBOX=OFF -D BUILD_TESTS=OFF ..
        make -j${G_CPU_CORE}
        make install
    fi

    # ---- mlpack -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        tar -xf src_package/stb.tar.gz -C ${G_INSTALL_ROOT}/include
        mv ${G_INSTALL_ROOT}/include/stb/include/* ${G_INSTALL_ROOT}/include/stb/
        \rm -rf ${G_INSTALL_ROOT}/include/stb/include
        tar -xf src_package/mlpack*.tar.gz -C build_tmp
        cd build_tmp/mlpack*
        ChangeCmakeVersion
        # 删除 IMPLICIT_INCLUDE_DIRECTORIES 会导致误删除必要的include 目录
        perl -pi -e 's/list.*?REMOVE_ITEM.*?_IMPLICIT_INCLUDE_DIRECTORIES.*/# $&/ig' CMake/cotire.cmake
        mkdir build && cd build
        if [ "${G_BUILD_TYPE}" = "Debug" ] ; then
            cmake ${G_CMAKE_COMMON} ${G_CMAKE_BOOST_CONFIG} -D BUILD_TESTS=OFF -D DEBUG=ON -D PROFILE=ON ..
        else
            cmake ${G_CMAKE_COMMON} ${G_CMAKE_BOOST_CONFIG} -D BUILD_TESTS=OFF ..
        fi
        make -j$(echo ${G_CPU_CORE}/2 | bc) # 编译比较耗内存，减少个数避免出错
        make install
    fi

    # ---- faiss -------------------------------------------------
    if ((1)) ; then
        cd ${G_BASE_PATH}
        unzip -qu src_package/faiss*.zip -d build_tmp
        cd build_tmp/faiss*
        mkdir build && cd build
        cmake ${G_CMAKE_COMMON} -D FAISS_ENABLE_GPU=OFF -D FAISS_ENABLE_PYTHON=OFF -D FAISS_OPT_LEVEL=avx2 -D BLA_VENDOR=OpenBLAS -D BUILD_TESTING=OFF ..
        make -j${G_CPU_CORE}
        make install
    fi
fi

# ----设置runpath，避免开发或部署时找不到依赖库 ------------------------------------------------
if [ "${G_TARGET_OS}" = "linux" ] ; then
    patchelf --set-rpath ${G_INSTALL_RPATH} ${G_INSTALL_ROOT}/lib/*.so
fi
