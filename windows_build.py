import tarfile
import os
import sys
import subprocess
import glob
import shutil
import zipfile


# 修改CMakeLists.txt中的Version
def ChangeCmakeVersion():
    subprocess.run(R'perl -pi -e "s/(CMAKE_MINIMUM_REQUIRED\(VERSION)\s+[\d\.]+/$1 3.14/ig" CMakeLists.txt')


class Env:
    BIT = 64
    BASE_PATH = os.path.dirname(os.path.abspath(__file__))
    INSTALL_ROOT = os.path.join(BASE_PATH, "3rd_root_windows").replace("\\", "/")
    BUILD_DIR = os.path.join(BASE_PATH, "build_tmp")
    BUILD_TYPE = 'Release'
    TARGET_OS = "win7"

    def __init__(self):
        os.chdir(Env.BASE_PATH)
        if os.path.exists(Env.BUILD_DIR):
            shutil.rmtree(Env.BUILD_DIR)

        os.mkdir(Env.BUILD_DIR)
        os.environ["CC"] = "cl.exe"
        os.environ["CXX"] = "cl.exe"
        os.environ["LDFLAGS"] = F"/LIBPATH:{Env.INSTALL_ROOT}/lib"
        COMMON_CFLAGS = F"/D_UNICODE /D_CRT_SECURE_NO_WARNINGS /D_SCL_SECURE_NO_WARNINGS /DWIN32_LEAN_AND_MEAN /source-charset:utf-8 /I{Env.BASE_PATH}/3rd_root/include /I{Env.INSTALL_ROOT}/include"
        if Env.TARGET_OS == "win7":
            os.environ["CFLAGS"] = F"{COMMON_CFLAGS} /D_WIN32_WINNT=0x0601"
        else:
            os.environ["CFLAGS"] = F"{COMMON_CFLAGS} /D_WIN32_WINNT=0x0501 /D_USING_V110_SDK71_"
            
        os.environ["CXXFLAGS"] = F'{os.environ["CFLAGS"]} /std:c++17'

# ------------------------------------------------------------------


def BuildLua():
    os.chdir(Env.BASE_PATH)
    print("lua tar decompress...")
    with tarfile.open(glob.glob("src_package/lua*.tar.gz")[0], mode="r") as lua:
        lua.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/lua*")[0])
    if os.path.exists("./CMakeLists.txt"):
        os.remove("./CMakeLists.txt")
    shutil.copy(os.path.join(Env.BASE_PATH, "my_conf/lua_CMakeLists.txt"), "./CMakeLists.txt")
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildZlib():
    os.chdir(Env.BASE_PATH)
    print("zlib zip decompress...")
    with zipfile.ZipFile(glob.glob("src_package/zlib*.zip")[0], mode='r') as zlib:
        zlib.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/zlib*")[0])
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildBrotli():
    os.chdir(Env.BASE_PATH)
    print("brotli tar decompress...")
    with tarfile.open(glob.glob("src_package/brotli*.tar.gz")[0], mode='r') as brotli:
        brotli.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/brotli*")[0])
    os.mkdir("out")
    os.chdir("out")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX={Env.INSTALL_ROOT} ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildSqlite():
    os.chdir(Env.BASE_PATH)
    print("sqlite zip decompress...")
    with zipfile.ZipFile(glob.glob("src_package/sqlite*.zip")[0], mode='r') as sqlite:
        sqlite.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/sqlite*")[0])
    if os.path.exists("./CMakeLists.txt"):
        os.remove("./CMakeLists.txt")
    shutil.copy(os.path.join(Env.BASE_PATH, "my_conf/sqlite_CMakeLists.txt"), "./CMakeLists.txt")
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX={Env.INSTALL_ROOT} ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildOpenSSL():
    """
    1. 需要安装perl和nasm
    2. -DOPENSSL_NO_ASYNC ios上不定义该宏，会包含一些系统私有的api调用，评审过不了。实测，定义该宏，对
        boost::asio的异步ssl封装没有影响
    3. --debug --release(默认)
    4. tlsv1.3开始禁用了压缩，且之前的版本也不推荐使用压缩，所以最好不集成zlib:
        zlib --with-zlib-include="%cd%\..\zlib\win64\include" --with-zlib-lib="%cd%\..\zlib\win64\lib\zlib.lib"
    """
    os.chdir(Env.BASE_PATH)
    print("openssl tar decompress...")
    with tarfile.open(glob.glob("src_package/openssl*.tar.gz")[0], mode='r') as openssl:
        openssl.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/OpenSSL*")[0])
    if Env.BIT == 64:
        BIT_CONFIG = "VC-WIN64A "
    else:
        BIT_CONFIG = "VC-WIN32 "
    if Env.BUILD_TYPE == "Release":
        BUILD_CONFIG = "--release "
    else:
        BUILD_CONFIG = "--debug "
    # vs2019, 不加入/DEBUG，链接器不会生成pdb，会导致OpenSSL安装时找不到pdb文件报错
    old = os.environ["LDFLAGS"]
    os.environ["LDFLAGS"] = F"{os.environ['LDFLAGS']} /DEBUG "
    subprocess.run(
        RF'perl Configure {BIT_CONFIG} {BUILD_CONFIG} --prefix={Env.INSTALL_ROOT} --openssldir=.\SSL -DOPENSSL_NO_ASYNC')
    subprocess.run("nmake")
    subprocess.run("nmake install_sw")
    subprocess.run("nmake install_ssldirs")
    # subprocess.run("nmake install_docs") // 安装html doc，很耗时
    os.environ["LDFLAGS"] = old


def BuildMariadb():
    os.chdir(Env.BASE_PATH)
    print("mariadb-connector tar decompress...")
    with tarfile.open(glob.glob("src_package/mariadb-connector-c*.tar.gz")[0], mode='r') as mariadb:
        mariadb.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/mariadb-connector-c*")[0])
    ChangeCmakeVersion()
    # plugin改为静态库，集成到libmariadb.so中，方便使用
    subprocess.run(R'perl -pi -e "s/DEFAULT DYNAMIC/DEFAULT STATIC/g" plugins/auth/CMakeLists.txt')
    subprocess.run(R'perl -pi -e "s/DEFAULT DYNAMIC/DEFAULT STATIC/g" plugins/pvio/CMakeLists.txt')
    os.mkdir("build")
    os.chdir("build")
    old_clags = os.environ["CFLAGS"]
    os.environ["CFLAGS"] = F"{old_clags} /DMYSQL_CLIENT=1"
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" -DWITH_EXTERNAL_ZLIB=ON -DZLIB_ROOT={Env.INSTALL_ROOT} -DWITH_SSL=OPENSSL -DOpenSSL_ROOT={Env.INSTALL_ROOT} ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")
    os.environ["CFLAGS"] = F"{old_clags}"


def BuildBoost():
    os.chdir(Env.BASE_PATH)
    boost_name = "boost_1_80_0"
    if not os.path.exists(os.path.join(Env.INSTALL_ROOT, boost_name)):
        print("boost tar decompress...")
        with tarfile.open(os.path.join(Env.BASE_PATH, F"src_package/{boost_name}.tar.gz"), mode="r") as boost_tar:
            boost_tar.extractall(path=Env.INSTALL_ROOT)
    os.chdir(os.path.join(Env.INSTALL_ROOT, boost_name))
    if not os.path.exists("./b2.exe"):
        print("build b2...")
        os.system("bootstrap.bat")
    # user-config
    with open("./user-config.jam", mode="w") as config:
        print(F"using zlib : 1.2.11 : <include>{Env.INSTALL_ROOT}/include <search>{Env.INSTALL_ROOT}/lib ;",
              file=config)

    """ toolset对应关系
    Visual Studio 2019 -- 14.2
    Visual Studio 2017 -- 14.1
    Visual Studio 2015 -- 14.0
    Visual Studio 2013 -- 12.0
    Visual Studio 2012 -- 11.0
    Visual Studio 2010 -- 10.0
    Visual Studio 2008 -- 9.0
    Visual Studio 2005 -- 8.0
    """
    toolset = "msvc-14.2"
    compile_libs = "--without-python"
    # VS2015、2017中，动态链接，char16_t,char32_t的编译会报dll链接不一致的错误
    # boost_local = "define=BOOST_LOCALE_ENABLE_CHAR16_T define=BOOST_LOCALE_ENABLE_CHAR32_T"
    boost_local = ""
    # define=BOOST_THREAD_VERSION=5 指定了这个宏之后，必须指定 BOOST_THREAD_USES_DATETIME, 否则boost_log编译失败；
    # 必须指定BOOST_THREAD_PROVIDES_NESTED_LOCKS，否则boost_locale编译失败。
    libs_config = F"define=BOOST_NO_AUTO_PTR define=BOOST_ASIO_DISABLE_STD_CHRONO define=BOOST_CHRONO_VERSION=2 define=BOOST_FILESYSTEM_NO_DEPRECATED define=BOOST_THREAD_VERSION=5 define=BOOST_THREAD_USES_DATETIME define=BOOST_THREAD_PROVIDES_NESTED_LOCKS define=BOOST_THREAD_QUEUE_DEPRECATE_OLD {boost_local} "

    cmd = RF'.\b2 toolset={toolset} --debug-configuration --user-config=./user-config.jam ' \
        RF'--build-type=complete {compile_libs} --hash threading=multi link=static address-model={Env.BIT} ' \
        R'variant={0} runtime-link={1} ' \
        RF'{libs_config} cflags="{os.environ["CFLAGS"]}" cxxflags="{os.environ["CXXFLAGS"]}" linkflags="{os.environ["LDFLAGS"]}" '
    for item in [["debug", "shared"], ["release", "shared"]]:
        with open(F"compile_{Env.BIT}_{item[0]}_{item[1]}.log", mode="w") as f:
            print(cmd.format(item[0], item[1]))
            subprocess.run(cmd.format(item[0], item[1]), stdout=f)


def BuildYUV():
    os.chdir(Env.BASE_PATH)
    print("libyuc zip decompress...")
    with zipfile.ZipFile(glob.glob("src_package/libyuv*.zip")[0], mode='r') as yuvzip:
        yuvzip.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/libyuv*")[0])
    if os.path.exists("./CMakeLists.txt"):
        os.remove("./CMakeLists.txt")
    shutil.copy(os.path.join(Env.BASE_PATH, "my_conf/yuv_CMakeLists.txt"), "./CMakeLists.txt")
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" -DBUILD_SHARED_LIBS=ON ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildLibjpegTurbo():
    os.chdir(Env.BASE_PATH)
    print("libjpeg-turbo zip decompress...")
    with zipfile.ZipFile(glob.glob("src_package/libjpeg-turbo*.zip")[0], mode='r') as libjpeg:
        libjpeg.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/libjpeg-turbo*")[0])
    ChangeCmakeVersion()
    subprocess.run(R'perl -pi -e "s/\{CMAKE_INSTALL_INCLUDEDIR\}/$&\/libjpeg/g" CMakeLists.txt')
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DENABLE_STATIC=OFF -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildSDL2():
    os.chdir(Env.BASE_PATH)
    print("SDL2 tar decompress...")
    with tarfile.open(glob.glob("src_package/SDL2*.tar.gz")[0], mode='r') as sdl2:
        sdl2.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/SDL2*")[0])
    os.mkdir("build")
    os.chdir("build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" -DBUILD_SHARED_LIBS=ON ..'
    print(cmd)
    # SDL2自己定义了windows的宏 WIN32_LEAN_AND_MEAN ,有冲突
    os.environ["CFLAGS"] = os.environ["CFLAGS"].replace(
        "/DWIN32_LEAN_AND_MEAN", "")
    # vs2019, 不加入vcruntime.lib，vs2019命令行链接时会报错
    old = os.environ["LDFLAGS"]
    os.environ["LDFLAGS"] = "vcruntime.lib"
    subprocess.run(cmd)
    os.environ["CFLAGS"] += " /DWIN32_LEAN_AND_MEAN"
    subprocess.run("ninja install")
    os.environ["LDFLAGS"] = old


def Buildx265():
    os.chdir(Env.BASE_PATH)
    print("x265 tar decompress...")
    with tarfile.open(glob.glob("src_package/x265*.tar.gz")[0], mode='r') as x265:
        x265.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/x265*")[0])
    os.mkdir("cmake_build")
    os.chdir("cmake_build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ../source'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildOpus():
    os.chdir(Env.BASE_PATH)
    print("opus tar decompress...")
    with tarfile.open(glob.glob("src_package/opus*.tar.gz")[0], mode="r") as opus:
        opus.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/opus*")[0])
    with open("opus_buildtype.cmake", mode="w") as opusConfig:
        print(
            'set(BUILD_SHARED_LIBS ON) \n set(CMAKE_INSTALL_LIBDIR lib) \n', file=opusConfig)
    os.mkdir("cmake_build")
    os.chdir("cmake_build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ..'
    print(cmd)
    subprocess.run(cmd)
    subprocess.run("ninja install")


def BuildFfmpeg():
    os.chdir(Env.BASE_PATH)
    input('''ffmpeg编译注意：
    1. 必须安装msys64，并且把安装目录加入到环境变量PATH中；
    2. 必须安装必须的编译工具，msys2.exe打开后执行下面命令安装：
        pacman -S automake autoconf libtool make pkg-config diffutils tar
    按任意键继续。。。
    ''')
    os.environ["MSYS2_PATH_TYPE"]="inherit"
    # msys中"/"用"-"代替
    old_cflags = os.environ["CFLAGS"]
    old_cxxflags = os.environ["CXXFLAGS"]
    os.environ["CFLAGS"] = os.environ["CFLAGS"].replace("/", "-")
    os.environ["CXXFLAGS"] = os.environ["CXXFLAGS"].replace("/", "-")
    os.environ["G_BUILD_TYPE"] = Env.BUILD_TYPE
    subProc = subprocess.Popen(["msys2_shell.cmd", "-mingw64", "-here", "./ffmpeg_build_msys64_msvc.sh"], stdout=subprocess.PIPE)
    # subProc = subprocess.Popen(["msys2_shell.cmd", "-mingw64", "-here"], stdout=subprocess.PIPE)
    subProc.communicate()
    os.environ["CFLAGS"] = old_cflags
    os.environ["CXXFLAGS"] = old_cxxflags
    os.environ.pop("G_BUILD_TYPE")


def BuildGlew():
    os.chdir(Env.BASE_PATH)
    print("glew zip decompress...")
    with zipfile.ZipFile(glob.glob("src_package/glew*.zip")[0], mode="r") as glew:
        glew.extractall(path=Env.BUILD_DIR)
    os.chdir(glob.glob(F"{Env.BUILD_DIR}/glew*")[0])
    os.mkdir("cmake_build")
    os.chdir("cmake_build")
    cmd = RF'cmake -G"Ninja" -DCMAKE_BUILD_TYPE={Env.BUILD_TYPE} -DCMAKE_INSTALL_PREFIX="{Env.INSTALL_ROOT}" ../build/cmake'
    print(cmd)
    # vs2019, 不加入vcruntime.lib，vs2019命令行链接时会报错
    old = os.environ["LDFLAGS"]
    os.environ["LDFLAGS"] = "vcruntime.lib"
    subprocess.run(cmd)
    subprocess.run("ninja install")
    os.environ["LDFLAGS"] = old


if __name__ == "__main__":
    Env()

    if 0:
        BuildLua()

    if 0:
        BuildZlib()

    if 0:
        BuildBrotli()

    if 0:
        BuildSqlite()

    if 0:
        BuildOpenSSL()

    if 0:
        BuildMariadb()

    if 1:
        BuildBoost()

    if 0:
        BuildYUV()
        
    if 0:
        BuildLibjpegTurbo()

    if 0:
        BuildSDL2()
    if 0:
        Buildx265()
    if 0:
        BuildOpus()
    if 0:
        BuildFfmpeg()

    if 0:
        BuildGlew()
