#!/bin/bash
set -e
set -x

# 前提条件：
# 1. windows上安装Visual Studio 2019, msys64, nasm(2.14以上)
# 2. 注意msys和代码路径中不要有空格、中文。打开msys命令行，安装编译工具，可以在 msys64\etc\pacman.d\mirrorlist.* 中
#    修改源的优先级，提高速度。
#    pacman -S automake autoconf libtool make pkg-config diffutils tar man
#    /usr/bin/link.exe 改名 msys-link.exe，否则会和msvc的link冲突
# 3. 打开vs2019命令行，执行 
#    set MSYS2_PATH_TYPE=inherit
#    cd 到msys目录，运行 msys2_shell.cmd -mingw64
# 4. cd 到该脚本目录，执行该脚本

    
G_BASE_PATH=$(cd `dirname $0`; pwd)
cd ${G_BASE_PATH}
G_CPU_CORE=$(cat /proc/cpuinfo | grep "processor" | wc -l)

G_INSTALL_ROOT=${G_BASE_PATH}/3rd_root_windows

# 路径中的/替换为\/，否则正则表达式中用不了
G_PKG_PREFIX=$(echo ${G_INSTALL_ROOT} | perl -n -e 's/\//\\\//g; print;')
function ChangePkgconfigPrefix() {
    perl -pi -e "s/^prefix.*/prefix=${G_PKG_PREFIX}/g" $1
}

#----x264-------------------------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    if [ ${G_BUILD_TYPE} = "Debug" ] ; then
        X264_BUILD_CONFIG="--enable-debug"
    else
        X264_BUILD_CONFIG=""
    fi

    tar -xjf src_package/x264*.tar.bz2 -C build_tmp
    cd build_tmp/x264*
    # --enable-pic 必须，汇编代码不受-fPIC影响
    ./configure --prefix=${G_INSTALL_ROOT} --enable-shared --enable-pic ${X264_BUILD_CONFIG} --host=x86_64-mingw64
    unset X264_BUILD_CONFIG
    make -j${G_CPU_CORE}
    make install
    mv -f ${G_INSTALL_ROOT}/lib/libx264.dll.lib ${G_INSTALL_ROOT}/lib/libx264.lib 
fi

#----ffmpeg-------------------------------------------------------------
if ((1)) ; then
    cd ${G_BASE_PATH}
    tar -xJf src_package/ffmpeg*.tar.xz -C build_tmp
    cd build_tmp/ffmpeg*
    if [ ${G_BUILD_TYPE} = "Debug" ] ; then
        FFMPEG_BUILD_CONFIG="--enable-debug --disable-optimizations --disable-stripping "
    else
        FFMPEG_BUILD_CONFIG="--disable-debug "
    fi
    # ffmpeg中自己定义了-utf-8
    CFLAGS=`echo $CFLAGS | perl -pe 's/-source-charset:utf-8//'`

    # ---- pkgconfig ------------------------------------------------------
    FFMPEG_3RD_LIB_CONFIG="--enable-libx264 --enable-libx265 --enable-libopus --enable-openssl"

    rm -rf ./3rd_config
    \cp -rf ${G_INSTALL_ROOT}/lib/pkgconfig    ./3rd_config #复制一份来修改
    \cp -rf ${G_BASE_PATH}/my_conf/pkgconfig/* ./3rd_config/
    export PKG_CONFIG_PATH="$(pwd)/3rd_config"
    
    # x264
    ChangePkgconfigPrefix ${PKG_CONFIG_PATH}/x264.pc
    perl -pi -e "s/-lx264/-llibx264/g" ${PKG_CONFIG_PATH}/x264.pc

    # x265
    ChangePkgconfigPrefix ${PKG_CONFIG_PATH}/x265.pc
    perl -pi -e "s/-lx265/-llibx265/g" ${PKG_CONFIG_PATH}/x265.pc

    # opus
    \cp -f ${PKG_CONFIG_PATH}/opus.pc.in ${PKG_CONFIG_PATH}/opus.pc
    perl -pi -e "s/OPUS_PREFIX/${G_PKG_PREFIX}/g" ${PKG_CONFIG_PATH}/opus.pc

    # openssl
    ChangePkgconfigPrefix ${PKG_CONFIG_PATH}/openssl.pc

    # SDL2
    ChangePkgconfigPrefix ${PKG_CONFIG_PATH}/sdl2.pc
    # ---- pkgconfig ------------------------------------------------------

    # ffmpeg交叉编译时默认使用${cross-prefix}-pkg-config，不一定存在，存在也可能有bug(ubuntu20中mingw的pkg-config工具)，
    # 因此明确指明pkg-config工具
    ./configure --pkg-config=pkg-config --prefix=${G_INSTALL_ROOT} ${FFMPEG_BUILD_CONFIG} --enable-shared --disable-static --enable-pic --toolchain=msvc --arch=x86_64 --extra-cflags="${CFLAGS}" --extra-cxxflags="${CXXFLAGS}" --extra-ldflags="${LDFLAGS}" --enable-gpl --enable-nonfree ${FFMPEG_3RD_LIB_CONFIG}
    make -j${G_CPU_CORE}
    make install
fi
