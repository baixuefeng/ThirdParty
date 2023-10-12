
set +x

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# ---- G_TARGET_OS ---------------------------
if [ -z "${G_TARGET_OS}" ] ; then
    printf "%s\n" \
    "select target os:" \
    "1. linux [default]" \
    "2. android"
    read G_TARGET_OS
    case ${G_TARGET_OS} in
    2)
        G_TARGET_OS="android"
    ;;
    *)
        G_TARGET_OS="linux"
    ;;
    esac
fi

# ---- CC CXX CFLAGS G_NATIVE_BUILD G_CMAKE_PLATFORM_CONFIG -------------------------------------------
export CFLAGS="-fPIC"
if [ "${G_TARGET_OS}" = "linux" ] ; then
    if command_exists clang && command_exists clang++; then
        read -p "Use clang ?[y/N]" USE_CLANG
        if [ "${USE_CLANG}" = "y" ] || [ "${USE_CLANG}" = "Y" ]; then
            export CC=clang
            export CXX=clang++
        fi
        unset USE_CLANG
    fi
    if [ -z "${CC}" ]; then
        export CC=gcc
        export CXX=g++
    fi
    read -p "Build native for this machine ?[y/N]" G_NATIVE_BUILD
    if [ -z "$G_NATIVE_BUILD" ] || [ "$G_NATIVE_BUILD" = "N" ] || [ "$G_NATIVE_BUILD" = "n" ] ; then
        G_NATIVE_BUILD="N"
    else
        G_NATIVE_BUILD="Y"
        export CFLAGS="${CFLAGS} -march=native"
    fi
    G_CMAKE_PLATFORM_CONFIG=""

elif [ "${G_TARGET_OS}" = "android" ] ; then
    # ---- ANDROID_NDK_HOME ANDROID_NDK_SYSROOT ANDROID_NATIVE_API_LEVEL G_HOST_PATH ------------------
    read -p "input android ndk root dir:[/opt/android-ndk-*]" ANDROID_NDK_HOME
    if [ -z "${ANDROID_NDK_HOME}" ] ; then
        ANDROID_NDK_HOME=$(cd /opt/android-ndk-*/ && pwd)
    fi
    ANDROID_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake
    if [ ! -f ${ANDROID_TOOLCHAIN_FILE} ] ; then
        echo "can't find android toolchan cmake!"
        exit -1
    fi
    export ANDROID_NDK_HOME=${ANDROID_NDK_HOME} # openssl依赖该环境变量
    ANDROID_NDK_SYSROOT=${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot
    read -p "input android api level number:[21]" ANDROID_NATIVE_API_LEVEL
    if [ -z "$ANDROID_NATIVE_API_LEVEL" ] ; then
        ANDROID_NATIVE_API_LEVEL=21
    fi

    G_HOST_PATH=${PATH}
    # 不能把ar,ld,as等所在路径(${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/aarch64-linux-android/bin)加入到PATH中，
    # 交叉编译boost、ffmpeg的时候也需要linux本地编译一些东西，会引起冲突
    export PATH="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin:${PATH}" 
    export CC=aarch64-linux-android${ANDROID_NATIVE_API_LEVEL}-clang
    export CXX=aarch64-linux-android${ANDROID_NATIVE_API_LEVEL}-clang++

    G_CMAKE_PLATFORM_CONFIG="-D ANDROID_NDK=${ANDROID_NDK_HOME} \
    -D ANDROID_ABI=arm64-v8a \
    -D ANDROID_NATIVE_API_LEVEL=${ANDROID_NATIVE_API_LEVEL} \
    -D ANDROID_STL=c++_shared \
    -D CMAKE_TOOLCHAIN_FILE=${ANDROID_TOOLCHAIN_FILE} "
    unset ANDROID_TOOLCHAIN_FILE
fi

# ---- G_BUILD_TYPE ---------------------------------------------------------------------
read -p "Build release?[Y/n]" G_BUILD_TYPE
if [ -z "$G_BUILD_TYPE" ] || [ "$G_BUILD_TYPE" = "Y" ] || [ "$G_BUILD_TYPE" = "y" ] ; then
    G_BUILD_TYPE=Release
    export CFLAGS="${CFLAGS} -O3"
else
    G_BUILD_TYPE=Debug
    if [ "${CC}" = "clang" ] ; then
        export CFLAGS="${CFLAGS} -glldb"
    else
        export CFLAGS="${CFLAGS} -gdwarf-4"
    fi
    unset CLANG_DEBUG_INFO
fi

# ---- CXXFLAGS ---------------------------------------------------------------------
export CXXFLAGS="${CFLAGS} -std=c++17 -D_GLIBCXX_USE_DEPRECATED=0" # diable the features that C++17 has removed

# ---- G_CPU_CORE ---------------------------------------------------------------------
G_CPU_CORE=$(cat /proc/cpuinfo | grep "processor" | wc -l)
