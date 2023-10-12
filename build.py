import argparse
import dataclasses
import datetime
import enum
import functools
import glob
import multiprocessing
import os
import re
import shlex
import subprocess
import sys
import traceback
import typing

import charset_normalizer


if os.name == "nt":
    OS_ENCODING = "mbcs"
    OS_SHELL = [
        subprocess.run(
            "where.exe cmd", shell=True, encoding=OS_ENCODING, capture_output=True, check=True
        ).stdout.strip(),
    ]
elif os.name == "posix":
    OS_ENCODING = "utf-8"
    OS_SHELL = [
        "/bin/bash"
        # "-i", # -i 会使得bash置于前台，其子进程接收Ctrl+C命令
    ]

SUBPROCESS_RUN = functools.partial(subprocess.run, OS_SHELL, executable=None, shell=False, encoding=OS_ENCODING)


class Tools:
    def Log(*args, **kw) -> None:
        lastFrame = sys._getframe().f_back
        fileName = os.path.basename(lastFrame.f_globals["__file__"])
        lineNum = lastFrame.f_lineno
        print(
            f"[{datetime.datetime.now().isoformat(sep=' ', timespec='milliseconds')}][{os.getpid()}][{fileName},{lineNum}]",
            *args,
            **{"flush": True, **kw},
        )

    def PromptSelect(promt: str, optionList: typing.Iterable, defaultValue):
        assert defaultValue in optionList
        text = f"{promt}\n"
        optMap = {}
        index = 0
        for opt in optionList:
            text += f"    {index}: {opt!r}"
            optMap[index] = opt
            index += 1
            if opt == defaultValue:
                text += " [default]"
            text += "\n"

        while True:
            try:
                value = input(text)
                if not value:
                    return defaultValue
                else:
                    return optMap[int(value)]
            except Exception as e:
                Tools.Log(f"{type(e)}: {str(e)}")

    def PromptInput(promt: str, defaultValue):
        while True:
            try:
                value = input(f"{promt}, [default: {defaultValue}]:\n")
                if not value:
                    return defaultValue
                else:
                    return type(defaultValue)(value)
            except Exception as e:
                Tools.Log(f"{type(e)}: {str(e)}")

    def HasUnsafeChar(string: str) -> bool:
        return shlex.quote(string) != string

    def CheckCommand(cmdStr: str, env: dict = None) -> bool:
        try:
            SUBPROCESS_RUN(input=cmdStr, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env, check=True)
            return True
        except:
            return False

    def GlobByRegex(dir: str, regex: re.Pattern, recursive: bool = False) -> typing.List[str]:
        if (not os.path.exists(dir)) or (not os.path.isdir(dir)):
            return []
        result = []
        for fsEntry in os.scandir(dir):
            try:
                if fsEntry.is_dir() and recursive:
                    result.extend(
                        [os.path.join(fsEntry.name, f) for f in Tools.GlobByRegex(fsEntry.path, regex, recursive)]
                    )
                elif fsEntry.is_file() and regex.fullmatch(fsEntry.name):
                    result.append(fsEntry.name)
            except OSError as e:
                Tools.Log(f"{type(e)}: {str(e)}. {traceback.format_exc()}")
        return result

    def RemoveFileOrDirs(dirPatten) -> None:
        dirs = glob.glob(dirPatten)
        if not dirs:
            return
        for d in dirs:
            SUBPROCESS_RUN(input=rf'cmake -E rm -rf "{d}"', check=True)

    def CopyFileOrDirs(src, dest) -> None:
        if not os.path.exists(src):
            return
        srcList = glob.glob(src)
        if not srcList:
            return
        for item in srcList:
            SUBPROCESS_RUN(input=rf'cmake -E copy "{item}" "{dest}"', check=True)

    def Decompress(filePatten: str, destDir: str) -> None:
        file = glob.glob(filePatten)
        assert len(file) == 1
        file = os.path.abspath(file[0])
        assert os.path.exists(destDir)
        SUBPROCESS_RUN(input=rf'cmake -E tar -xf "{file}"', cwd=destDir, check=True)

    def RegexLineByLine(
        filePatten: str,
        regexSearcher: re.Pattern,
        replacement: typing.Union[str, typing.Callable[[re.Match], str]],
        lineCount: int = None,
    ) -> None:
        """
        Use regexSearcher.sub process file line by line.
        lineCount: maximum number of line to be replaced, None means no limit.
        """
        file = glob.glob(filePatten)
        assert len(file) == 1
        file = file[0]
        with open(file, mode="rb") as fr:
            encoding = charset_normalizer.detect(fr.read())["encoding"]
        tmpFile = file + ".tmp"
        if lineCount is None:
            lineCount = int("0xFFFFFFFFFFFFFFF", 16)
        try:
            changedCount = 0
            with open(tmpFile, "w", encoding=encoding) as fw:
                with open(file, "r", encoding=encoding) as fr:
                    for line in fr:
                        newLine = regexSearcher.sub(replacement, line)
                        fw.write(newLine)
                        if newLine != line:
                            changedCount += 1
                            if changedCount >= lineCount:
                                fw.write(fr.read())
                                break
            if changedCount > 0:
                os.remove(file)
                os.rename(tmpFile, file)
        except Exception as e:
            Tools.Log(f"{type(e)}:{str(e)}")
        finally:
            if os.path.exists(tmpFile):
                os.remove(tmpFile)


# ------------------------------------------------------------------------------------------------


class TargetOs(enum.IntEnum):
    windows = 0
    linux = 1
    android = 2


class BuildType(enum.IntEnum):
    debug = 0
    release = 1


@dataclasses.dataclass()
class Environment:
    CC: str = ""
    CXX: str = ""
    CPPFLAGS: str = ""
    CFLAGS: str = ""
    CXXFLAGS: str = ""
    LDFLAGS: str = ""
    PATH: str = os.environ["PATH"]
    PKG_CONFIG_PATH: str = ""  # pkg-config 是从环境变量 PKG_CONFIG_PATH 里面找.pc文件配置参数


@dataclasses.dataclass()
class AndroidNdk:
    ANDROID_NDK_HOME: str = ""
    ANDROID_NDK_SYSROOT: str = ""
    ANDROID_NATIVE_API_LEVEL: str = ""


class Config:
    # user config
    BUILD_VIDEO_AUDIO: bool = True  # 音视频
    BUILD_MACHINE_LEARNING: bool = True  # 机器学习
    BUILD_SDL2_VIDEO: bool = False  # sdl2 video
    BUILD_NATIVE_ARCH: bool = False  # linux, "-march=native"

    # generated config
    BUILD_TYPE = BuildType.release
    TARGET_OS = TargetOs.windows
    DIR_BASE = os.path.dirname(os.path.abspath(__file__))
    DIR_BUILD_TMP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_tmp")
    DIR_INSTALL_ROOT = ""
    IS_CLANG: bool = False
    ENV = Environment()
    ANDROID_NDK = AndroidNdk()
    INSTALL_RPATH = ""
    CMAKE_COMMON_ARGS: typing.List[str] = [
        # "--debug-find",  # 调试查找
        "-D CMAKE_EXPORT_COMPILE_COMMANDS=ON",  # 导出编译命令
        "-D CMAKE_POSITION_INDEPENDENT_CODE=ON",
    ]
    CMAKE_BOOST_ARGS: typing.List[str] = []

    def _CheckPresets():
        assert (sys.version_info.major >= 3) and (sys.version_info.minor >= 9)
        assert not Tools.HasUnsafeChar(Config.DIR_BASE)
        assert Tools.CheckCommand("cmake --version")
        assert Tools.CheckCommand("perl -v")
        assert Tools.CheckCommand("nasm -v")
        assert Tools.CheckCommand("git lfs -v")
        if os.name == "nt":
            assert Tools.CheckCommand("ninja --version")
        else:
            assert Tools.CheckCommand("autoconf -V")
            assert Tools.CheckCommand("automake --version")
            assert Tools.CheckCommand("make -v")
            assert Tools.CheckCommand("pkg-config --version")
            assert Tools.CheckCommand("gfortran -v")
            assert Tools.CheckCommand("patchelf --version")

    def _InitWindows():
        pass

    def _InitLinux():
        Config.IS_CLANG = (
            Tools.CheckCommand("clang -v")
            and Tools.CheckCommand("clang++ -v")
            and Tools.PromptSelect("use clang?", [False, True], False)
        )
        if Config.IS_CLANG:
            Config.ENV.CC = "clang"
            Config.ENV.CXX = "clang++"
        elif (not Tools.CheckCommand("gcc -v")) or (not Tools.CheckCommand("g++ -v")):
            raise RuntimeError("gcc not found!")
        else:
            Config.ENV.CC = "gcc"
            Config.ENV.CXX = "g++"

        if Config.BUILD_NATIVE_ARCH:
            Config.ENV.CFLAGS += " -march=native"

    def _InitAndroid():
        while True:
            value = Tools.PromptInput("Input android ndk root dir", "/opt/android-ndk-*")
            dirList = glob.glob(value)
            if dirList:
                Config.ANDROID_NDK.ANDROID_NDK_HOME = dirList[0]
                break
            else:
                Tools.Log(f"{value} not found!")

        Config.ANDROID_NDK.ANDROID_NDK_SYSROOT = (
            f"${Config.ANDROID_NDK.ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
        )
        assert os.path.exists(Config.ANDROID_NDK.ANDROID_NDK_SYSROOT)

        toolchain = f"{Config.ANDROID_NDK.ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
        assert os.path.exists(toolchain)

        # 不能把ar,ld,as等所在路径({ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/aarch64-linux-android/bin)
        # 加入到PATH中, 交叉编译boost、ffmpeg的时候也需要linux本地编译一些东西, 会引起冲突
        binpath = f"{Config.ANDROID_NDK.ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
        assert os.path.exists(binpath)
        Config.ENV.PATH = f'{binpath}:{os.environ["PATH"]}'

        apiLevel = Tools.PromptInput("Input android api level number", 21)
        Config.ANDROID_NDK.ANDROID_NATIVE_API_LEVEL = apiLevel

        Config.IS_CLANG = True
        Config.ENV.CC = f"aarch64-linux-android{apiLevel}-clang"
        Config.ENV.CXX = f"aarch64-linux-android{apiLevel}-clang++"

        # CMAKE_FIND_ROOT_PATH: 优先从自己的目录中查找。
        # android.toolchain.cmake中设置 CMAKE_FIND_ROOT_PATH 到NDK根目录，并且只从这里查找，
        # 导致查找第三方库时find_library等类似API失败。

        # 下面是使用 Android Ndk 提供的toolchain的配置方法
        Config.CMAKE_COMMON_ARGS = [
            f"-D CMAKE_FIND_ROOT_PATH={Config.DIR_INSTALL_ROOT}",
            f"-D CMAKE_TOOLCHAIN_FILE={toolchain}",
            f"-D ANDROID_NATIVE_API_LEVEL={apiLevel}",
            "-D CMAKE_ANDROID_ARCH_ABI=arm64-v8a",
            "-D CMAKE_ANDROID_STL_TYPE=c++_shared",
        ]
        # 下面是使用 cmake 自己提供的配置方法
        # Config.CMAKE_COMMON_ARGS = [
        #     f"-D CMAKE_FIND_ROOT_PATH={Config.DIR_INSTALL_ROOT}",
        #     "CMAKE_SYSTEM_NAME=Android",
        #     f"CMAKE_SYSTEM_VERSION={apiLevel}",
        #     "CMAKE_ANDROID_ARCH_ABI=arm64-v8a",
        #     f"CMAKE_ANDROID_NDK={Config.ANDROID_NDK.ANDROID_NDK_HOME}",
        #     "CMAKE_ANDROID_STL_TYPE=c++_shared",
        # ]

    def _InitPosixCommmon():
        Config.ENV.CFLAGS += " -fPIC"
        if Config.BUILD_TYPE == BuildType.debug:
            if Config.IS_CLANG:
                Config.ENV.CFLAGS += " -glldb"
            else:
                Config.ENV.CFLAGS += " -gdwarf-4"
        else:
            Config.ENV.CFLAGS += " -O3"

        libPath = f"{Config.DIR_INSTALL_ROOT}/lib"
        os.makedirs(libPath, exist_ok=True)
        if not os.path.exists(f"{Config.DIR_INSTALL_ROOT}/lib64"):
            SUBPROCESS_RUN(input=r"ln -s lib lib64", cwd=Config.DIR_INSTALL_ROOT)
        Config.INSTALL_RPATH = rf"'$ORIGIN:$ORIGIN/lib:$ORIGIN/../lib'"

        Config.ENV.CFLAGS += f" -I{Config.DIR_BASE}/3rd_root/include -I{Config.DIR_INSTALL_ROOT}/include"
        Config.ENV.CFLAGS = Config.ENV.CFLAGS.strip()
        Config.ENV.CXXFLAGS = (Config.ENV.CFLAGS + " -std=c++17 -D_GLIBCXX_USE_DEPRECATED=0").strip()
        Config.ENV.LDFLAGS = (Config.ENV.LDFLAGS + f" -L{libPath}").strip()
        Config.ENV.PKG_CONFIG_PATH = f"{libPath}/pkgconfig:{Config.DIR_INSTALL_ROOT}/share/pkgconfig"

        Config.CMAKE_COMMON_ARGS += [
            f"-D CMAKE_INSTALL_RPATH={Config.INSTALL_RPATH}",  # 设置rpath, 避免编译时找不到间接依赖库。
            "-G 'Unix Makefiles'",
        ]

    def InitBoostCmakeArgs(boostDir: str = None):
        if boostDir is None:
            boostDir = glob.glob(f"{Config.DIR_INSTALL_ROOT}/boost_*")
            if len(boostDir) == 1:
                boostDir = boostDir[0]
        if isinstance(boostDir, str) and os.path.exists(f"{boostDir}/stage"):
            Config.CMAKE_BOOST_ARGS = [f"-D Boost_ROOT={boostDir}/stage", f"-D Boost_DEBUG=ON"]

    def InitConfig():
        Config._CheckPresets()

        # build type
        Config.BUILD_TYPE = Tools.PromptSelect("Build type?", [BuildType.release, BuildType.debug], BuildType.release)
        Config.CMAKE_COMMON_ARGS.append(f"-D CMAKE_BUILD_TYPE={Config.BUILD_TYPE.name.title()}")

        # target os
        if sys.platform.startswith("win32"):
            Config.TARGET_OS = TargetOs.windows
        elif sys.platform.startswith("linux"):
            Config.TARGET_OS = Tools.PromptSelect(
                "Select target os:", [TargetOs.linux, TargetOs.android], TargetOs.linux
            )
        else:
            raise RuntimeError("Unsuppored os!")

        # install root dir
        Config.DIR_INSTALL_ROOT = f"{Config.DIR_BASE}/3rd_root_{Config.TARGET_OS.name.lower()}"
        os.makedirs(Config.DIR_INSTALL_ROOT, exist_ok=True)
        Config.CMAKE_COMMON_ARGS.extend(
            [
                f"-D CMAKE_INSTALL_PREFIX={Config.DIR_INSTALL_ROOT}",  # 安装
                f"-D CMAKE_PREFIX_PATH={Config.DIR_INSTALL_ROOT}",  # 查找
            ]
        )

        # compiler
        if Config.TARGET_OS == TargetOs.windows:
            Config.BUILD_MACHINE_LEARNING = False
            Config._InitWindows()
        else:
            if Config.TARGET_OS == TargetOs.linux:
                Config._InitLinux()
            else:
                Config.BUILD_MACHINE_LEARNING = False
                Config._InitAndroid()
            Config._InitPosixCommmon()

    def EnvDict():
        return {**os.environ, **dataclasses.asdict(Config.ENV)}


# ------------------------------------------------------------------------------------------------


class Builder:
    def PrepareSrcPackage(compressedFilePatten: str, decompressedDirPatten: str):
        os.chdir(Config.DIR_BASE)
        Tools.Decompress(f"src_package/{compressedFilePatten}", Config.DIR_BUILD_TMP)
        curDir = glob.glob(f"{Config.DIR_BUILD_TMP}/{decompressedDirPatten}")
        assert len(curDir) == 1
        os.chdir(curDir[0])

    def CMakeBuild(
        compressedFilePatten: str,
        decompressedDirPatten: str,
        fnPrebuild: typing.Callable = None,
        *,
        cmakeParam: typing.List[str] = None,  # None means Config.CMAKE_COMMON_ARGS + Config.CMAKE_BOOST_ARGS
        cmakeExtraParam: typing.List[str] = None,  # Additional param beyond cmakeParam
        env: typing.Dict[str, str] = None,  # None means Config.EnvDict()
        buildDir: str = "build",  # building in this dir, and "../CMakeLists.txt" must exist!
        changeRequiredVersion: bool = False,
        parallelJobs=multiprocessing.cpu_count(),
    ):
        Builder.PrepareSrcPackage(compressedFilePatten, decompressedDirPatten)
        if fnPrebuild:
            fnPrebuild()
        assert not os.path.isabs(buildDir)
        os.makedirs(buildDir, exist_ok=True)
        os.chdir(buildDir)
        if changeRequiredVersion:
            Tools.RegexLineByLine(
                "../CMakeLists.txt",
                re.compile(r"(CMAKE_MINIMUM_REQUIRED\s*\(\s*VERSION)\s+[\d\.]+", re.IGNORECASE),
                lambda match: f"{match.group(1)} 3.27",
                1,
            )

        cmd = ["cmake"]
        if cmakeParam is None:
            cmakeParam = Config.CMAKE_COMMON_ARGS + Config.CMAKE_BOOST_ARGS
        cmd += cmakeParam
        if isinstance(cmakeExtraParam, list):
            cmd += cmakeExtraParam
        cmd += [".."]
        if env is None:
            env = Config.EnvDict()
        SUBPROCESS_RUN(input=" ".join(cmd), env=env, check=True)
        SUBPROCESS_RUN(
            input=rf"cmake --build . -j {parallelJobs} -t install",
            env=env,
            check=True,
        )

    def MakefileBuild(
        cmd: str,
        env: typing.Dict[str, str] = None,  # None means Config.EnvDict()
        *,
        parallelJobs=multiprocessing.cpu_count(),
    ):
        if env is None:
            env = Config.EnvDict()
        SUBPROCESS_RUN(input=cmd, env=env, check=True)
        SUBPROCESS_RUN(input=f"make -j{parallelJobs}", env=env, check=True)
        SUBPROCESS_RUN(input="make install", env=env, check=True)

    def PkgconigAddPrivLibsToPubLibs(pkgFile: str):
        privateLibs = ""

        def FindPrivateLibs(reMatch: re.Match):
            nonlocal privateLibs
            privateLibs = reMatch.group(1)
            return reMatch.group(0)

        Tools.RegexLineByLine(pkgFile, re.compile(r"Libs.private:(.*)", flags=re.IGNORECASE), FindPrivateLibs, 1)
        Tools.RegexLineByLine(
            pkgFile, re.compile(r"Libs:.*", flags=re.IGNORECASE), lambda reMatch: reMatch.group(0) + privateLibs
        )

    # ------------------------------------------------------------------------------------------------

    def BuildLua():
        def Prebuild():
            Tools.CopyFileOrDirs(os.path.join(Config.DIR_BASE, "my_conf/lua_CMakeLists.txt"), "./CMakeLists.txt")

        Builder.CMakeBuild("lua*.tar.gz", "lua*", Prebuild)

    def BuildSqlite3():
        def Prebuild():
            Tools.CopyFileOrDirs(os.path.join(Config.DIR_BASE, "my_conf/sqlite_CMakeLists.txt"), "./CMakeLists.txt")

        Builder.CMakeBuild("sqlite*.zip", "sqlite*", Prebuild)
        Builder.CMakeBuild("SQLiteCpp*.tar.gz", "SQLiteCpp*", cmakeExtraParam=["-D SQLITECPP_INTERNAL_SQLITE=OFF"])

    def BuildPugixml():
        cmakeExtraParam = []
        if Config.TARGET_OS == TargetOs.windows:
            cmakeExtraParam.append("-D PUGIXML_WCHAR_MODE=ON")
        Builder.CMakeBuild("pugixml*.tar.gz", "pugixml*", cmakeExtraParam=cmakeExtraParam)

    def BuildOpenssl():
        Builder.PrepareSrcPackage("openssl*.tar.gz", "openssl*")
        cmd = []
        env = Config.EnvDict()
        if Config.TARGET_OS == TargetOs.windows:
            cmd.append("perl Configure VC-WIN64A")
            # 1. 需要安装perl和nasm
            # 2. vs2019, 不加入/DEBUG，链接器不会生成pdb，会导致OpenSSL安装时找不到pdb文件报错
            env["LDFLAGS"] = (env["LDFLAGS"] + " /DEBUG").strip()
        elif Config.TARGET_OS == TargetOs.linux:
            cmd.append("./config")
        elif Config.TARGET_OS == TargetOs.android:
            cmd.append("perl Configure android-arm64")
            env["CPPFLAGS"] = (
                env["CPPFLAGS"] + f" -D__ANDROID_API__={Config.ANDROID_NDK.ANDROID_NATIVE_API_LEVEL}"
            ).strip()
            env["ANDROID_NDK_HOME"] = Config.ANDROID_NDK.ANDROID_NDK_HOME

        # 1. -DOPENSSL_NO_ASYNC ios上不定义该宏，会包含一些系统私有的api调用，评审过不了。实测，定义该宏，对
        #    boost::asio的异步ssl封装没有影响
        # 2. tlsv1.3开始禁用了压缩，且之前的版本也不推荐使用压缩，所以最好不集成zlib:
        cmd = " ".join(
            cmd
            + [
                rf"--{Config.BUILD_TYPE.name.lower()}",
                rf"--prefix={Config.DIR_INSTALL_ROOT}",
                "--libdir=lib --openssldir=./SSL shared -DOPENSSL_NO_ASYNC",
            ]
        )
        SUBPROCESS_RUN(input=cmd, env=env, check=True)
        # 不安装doc，生成doc太慢了
        if Config.TARGET_OS == TargetOs.windows:
            SUBPROCESS_RUN(input="nmake", env=env, check=True)
            SUBPROCESS_RUN(input="nmake install_sw install_ssldirs", env=env, check=True)
        else:
            SUBPROCESS_RUN(input=f"make -j{multiprocessing.cpu_count()}", env=env, check=True)
            SUBPROCESS_RUN(input="make install_sw install_ssldirs", env=env, check=True)

    def BuildIconv():
        if Config.TARGET_OS == TargetOs.windows:
            return
        Builder.PrepareSrcPackage("libiconv*.tar.gz", "libiconv*")
        if Config.TARGET_OS == TargetOs.linux:
            cmd = f"./configure --prefix={Config.DIR_INSTALL_ROOT}"
        else:
            cmd = f"./configure --host=aarch64-linux-android --prefix={Config.DIR_INSTALL_ROOT}"
        Builder.MakefileBuild(cmd)

    def BuildBoost():
        os.chdir(Config.DIR_BASE)
        Tools.Decompress("src_package/boost_*.tar.gz", Config.DIR_INSTALL_ROOT)
        boostDir = glob.glob(f"{Config.DIR_INSTALL_ROOT}/boost_*")
        assert len(boostDir) == 1
        boostDir = boostDir[0]
        os.chdir(boostDir)

        # 文档: jamroot and index.html -> tools -> boost.build -> section 4
        configJam = "./user-config.jam"
        cmd = [
            f"./b2 stage -d 2 --debug-configuration --user-config={configJam} --hash link=static",
            # python 使用 pybind11
            "--without-python",
        ]
        with open(configJam, mode="w") as fwConfig:
            if Config.TARGET_OS == TargetOs.windows:
                SUBPROCESS_RUN(input="bootstrap.bat", check=True)
                """toolset对应关系
                Visual Studio 2022 -- 14.3
                Visual Studio 2019 -- 14.2
                Visual Studio 2017 -- 14.1
                Visual Studio 2015 -- 14.0
                Visual Studio 2013 -- 12.0
                Visual Studio 2012 -- 11.0
                Visual Studio 2010 -- 10.0
                Visual Studio 2008 -- 9.0
                Visual Studio 2005 -- 8.0
                """
                cmd.append("toolset=msvc-14.2")
            else:
                SUBPROCESS_RUN(input="bash bootstrap.sh", check=True)
                # "-s ICONV_PATH" 不需要了，CXXFLAGS, LDFLAGS已经有路径了。(libs/locale/build/Jamfile.v2)
                if Config.TARGET_OS == TargetOs.android:
                    fwConfig.write(f"using clang : arm64 : {Config.ENV.CXX} : ;\n")
                    cmd.append("toolset=clang-arm64 target-os=android architecture=arm binary-format=elf abi=aapcs")
                else:
                    if Config.IS_CLANG:
                        cmd.append("toolset=clang")
                    else:
                        cmd.append("toolset=gcc")
                    # statx 是linux kernel 4.11才加入的，如果系统是低版本的，但在高版本的docker内编译，能编译但运行就会出错。
                    disableStatx = True
                    if Config.BUILD_NATIVE_ARCH:
                        reMatch = re.compile(r"^Linux\s+version\s+(\d+\.\d+)\..*").search(
                            SUBPROCESS_RUN(input="cat /proc/version", capture_output=True).stdout.decode()
                        )
                        try:
                            if reMatch and float(reMatch.group(1)) >= 4.11:
                                disableStatx = False
                        except:
                            pass
                    if disableStatx:
                        cmd.append("define=BOOST_FILESYSTEM_DISABLE_STATX")
            # tools/build/src/tools/zlib.jam
            fwConfig.write(
                f"using zlib : 1.2.13 : <include>{Config.DIR_INSTALL_ROOT}/include/zlib <search>{Config.DIR_INSTALL_ROOT}/lib ;\n"
            )
            # tools/build/src/tools/zstd.jam
            fwConfig.write(
                f"using zstd : 1.5.2 : <include>{Config.DIR_INSTALL_ROOT}/include/zstd <search>{Config.DIR_INSTALL_ROOT}/lib ;\n"
            )
        cmd.extend(
            [
                "define=BOOST_ASIO_DISABLE_STD_CHRONO",
                "define=BOOST_CHRONO_VERSION=2",
                "define=BOOST_FILESYSTEM_NO_DEPRECATED",
                # 注意, VS2015、2017中，动态链接，char16_t,char32_t的编译会报dll链接不一致的错误
                # 1.81版本 libs/locale/src/boost/locale/posix/collate.cpp 中 coll_traits 没有针对char16_t, char32_t的特化，编译不过
                # "define=BOOST_LOCALE_ENABLE_CHAR16_T",
                # "define=BOOST_LOCALE_ENABLE_CHAR32_T",
                # define=BOOST_THREAD_VERSION=5 指定了这个宏之后，必须指定 BOOST_THREAD_USES_DATETIME, 否则boost_log编译失败；
                # 必须指定 BOOST_THREAD_PROVIDES_NESTED_LOCKS, 否则boost_locale编译失败。
                "define=BOOST_THREAD_VERSION=5",
                "define=BOOST_THREAD_USES_DATETIME",
                "define=BOOST_THREAD_PROVIDES_NESTED_LOCKS",
                "define=BOOST_THREAD_QUEUE_DEPRECATE_OLD",
                f"threading=multi address-model=64 variant={Config.BUILD_TYPE.name.lower()}",
                f'cflags="{Config.ENV.CFLAGS}" cxxflags="{Config.ENV.CXXFLAGS}" linkflags="{Config.ENV.LDFLAGS}"',
            ]
        )
        # bin.v2/config.log 中查看配置出错原因
        env = Config.EnvDict()
        if Config.TARGET_OS == TargetOs.windows:
            cmd = " ".join(cmd)
            for item in ["shared", "static"]:
                cmdExtra = f" runtime-link={item}"
                Tools.Log(cmd + cmdExtra)
                SUBPROCESS_RUN(input=cmd + cmdExtra, env=env, check=True)
        else:
            # linux 上 runtime-link如果用static 编译时会加 -static
            SUBPROCESS_RUN(input=" ".join(cmd), env=env, check=True)
            Tools.RemoveFileOrDirs("./bin.v2")
        Config.InitBoostCmakeArgs(boostDir)

    def BuildJpeg():
        Builder.CMakeBuild(
            "libjpeg-turbo*.tar.gz",
            "libjpeg-turbo*",
            cmakeExtraParam=[
                # CMAKE_INSTALL_INCLUDEDIR 路径不能使用相对路径，会被 CMAKE_CURRENT_SOURCE_DIR 扩展.或者添加 ":PATH" 属性
                f"-D CMAKE_INSTALL_INCLUDEDIR={Config.DIR_INSTALL_ROOT}/include/libjpeg",
                "-D ENABLE_STATIC=OFF",
            ],
            changeRequiredVersion=True,
        )

    def BuildYuv():
        def Preprocess():
            Tools.CopyFileOrDirs(os.path.join(Config.DIR_BASE, "my_conf/yuv_CMakeLists.txt"), "./CMakeLists.txt")

        Builder.CMakeBuild("libyuv*.zip", "libyuv*", Preprocess)

    def BuildSdl2():
        Builder.CMakeBuild(
            "SDL2*.tar.gz",
            "SDL2*",
            cmakeExtraParam=[
                "-D BUILD_SHARED_LIBS=ON",
                # SDL2 debug模式生成的pkgconfig是错误的, 没有带"d"后缀
                '-D SDL_CMAKE_DEBUG_POSTFIX:SRING=""',
                f'-D SDL_VIDEO={"ON" if Config.BUILD_SDL2_VIDEO else "OFF"}',
            ],
            changeRequiredVersion=True,
        )
        if Config.TARGET_OS == TargetOs.android:
            # android上必须通过java层初始化jni环境，否则无法使用。因此拷贝官方提供的java初始化代码。
            Tools.RemoveFileOrDirs(f"{Config.DIR_INSTALL_ROOT}/lib/java")
            Tools.CopyFileOrDirs("../android-project/app/src/main/java", f"{Config.DIR_INSTALL_ROOT}/lib")

    def BuildOpus():
        def PreBuild():
            # 禁止从git tag中获取版本号
            Tools.RegexLineByLine(
                "opus_functions.cmake",
                re.compile(r"find_package\s*\(\s*git\s*\)", flags=re.IGNORECASE),
                lambda reMatch: f"#{reMatch.group(0)}",
            )
            # 代码中include该文件，因此必须创建
            with open("opus_buildtype.cmake", "w") as fw:
                fw.write("set(BUILD_SHARED_LIBS ON)\n")
                fw.write("set(CMAKE_INSTALL_LIBDIR lib)\n")

        Builder.CMakeBuild("opus*.tar.gz", "opus*", PreBuild)
        Builder.PkgconigAddPrivLibsToPubLibs(f"{Config.DIR_INSTALL_ROOT}/lib/pkgconfig/opus.pc")

    def BuildX264():
        if Config.TARGET_OS == TargetOs.windows:
            return
        Builder.PrepareSrcPackage("x264*.tar.bz2", "x264*")
        cmd = f"./configure --prefix={Config.DIR_INSTALL_ROOT} --enable-shared --enable-pic "
        if Config.BUILD_TYPE == BuildType.debug:
            cmd += "--enable-debug "
        if Config.TARGET_OS == TargetOs.android:
            cmd += f"--host=aarch64-linux-android --cross-prefix=aarch64-linux-android- --sysroot={Config.ANDROID_NDK.ANDROID_NDK_SYSROOT} "
        Builder.MakefileBuild(cmd)
        Builder.PkgconigAddPrivLibsToPubLibs(f"{Config.DIR_INSTALL_ROOT}/lib/pkgconfig/x264.pc")

    def BuildVpx():
        if Config.TARGET_OS == TargetOs.windows:
            return
        Builder.PrepareSrcPackage("libvpx-*.zip", "libvpx-*")
        # android都不支持动态库 --enable-runtime-cpu-detect
        cmd = f"../configure --prefix={Config.DIR_INSTALL_ROOT} --log=yes --enable-pic --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth --enable-vp9-postproc --enable-onthefly-bitpacking --enable-vp9-temporal-denoising "
        if Config.BUILD_TYPE == BuildType.debug:
            cmd += "--enable-debug "
        else:
            cmd += "--enable-optimizations "
        if Config.TARGET_OS == TargetOs.android:
            cmd += "--target=arm64-android-gcc "
        else:
            cmd += "--target=x86_64-linux-gcc "
        os.chdir("build")
        Builder.MakefileBuild(cmd)
        Builder.PkgconigAddPrivLibsToPubLibs(f"{Config.DIR_INSTALL_ROOT}/lib/pkgconfig/vpx.pc")

    def BuildFfmpeg():
        if Config.TARGET_OS == TargetOs.windows:
            return
        Builder.PrepareSrcPackage("ffmpeg*.tar.xz", "ffmpeg*")
        # ffmpeg交叉编译时默认使用${cross-prefix}-pkg-config，不一定存在，存在也可能有bug(ubuntu20中mingw的pkg-config工具)，
        # 因此明确指明pkg-config工具
        cmd = f'./configure --pkg-config=pkg-config --prefix={Config.DIR_INSTALL_ROOT} --enable-shared --disable-static --enable-pic --enable-gpl --enable-nonfree --cc={Config.ENV.CC} --cxx={Config.ENV.CXX} --extra-cflags="{Config.ENV.CFLAGS}" --extra-cxxflags="{Config.ENV.CXXFLAGS}" --extra-ldflags="{Config.ENV.LDFLAGS}" '

        if Config.BUILD_TYPE == BuildType.debug:
            cmd += "--enable-debug --disable-optimizations --disable-stripping "
        else:
            cmd += "--disable-debug "

        if Config.TARGET_OS == TargetOs.android:
            cmd += f"--enable-cross-compile --arch=aarch64 --target-os=android --cross-prefix=aarch64-linux-android- --sysroot={Config.ANDROID_NDK.ANDROID_NDK_SYSROOT} "
            # android sdl2的pkgconfig写的是错的，且sdl2对于ffmpeg主要是开发辅助的作用
            cmd += f"--enable-openssl --enable-libopus --enable-libx264 --enable-libvpx --disable-sdl2 "
        else:
            cmd += f"--enable-openssl --enable-libopus --enable-libx264 --enable-libx265 --enable-libvpx "
        Builder.MakefileBuild(cmd)
        if Config.TARGET_OS == TargetOs.linux:
            # 优化软连接：
            # 原本的状态：比如
            # libavcodec.so -> libavcodec.so.58.91.100
            # libavcodec.so.58 -> libavcodec.so.58.91.100
            # libavformat.so 依赖 libavcodec.so.58
            # 编译的时候 -lavformat -lavcodec，安装时候递归拷贝libavcodec.so,libavformat.so，运行就会报找不到so。因为libavformat.so
            # 依赖的是libavcodec.so.58，不是libavcodec.so或libavcodec.so.58.91.100，还必须把libavcodec.so.58这个软连接单独拷贝。
            libDir = f"{Config.DIR_INSTALL_ROOT}/lib"
            os.chdir(libDir)
            for item in ["avutil", "swresample", "swscale", "postproc", "avcodec", "avformat", "avfilter", "avdevice"]:
                link = f"lib{item}.so"
                Tools.RemoveFileOrDirs(link)
                file = Tools.GlobByRegex(libDir, re.compile(rf"{link}\.\d+"))
                assert len(file) == 1
                SUBPROCESS_RUN(input=f"ln -f -s {file[0]} {link}", check=True)

    def BuildOpenBlas():
        def Prebuild():
            # 修改debug模式生成文件名字
            Tools.RegexLineByLine(
                "./CMakeLists.txt",
                re.compile(r"set_target_properties.*?LIBRARY_OUTPUT_NAME_DEBUG.*", flags=re.IGNORECASE),
                lambda reMatch: f"# {reMatch.group(0)}",
            )
            # 修改.cmake安装位置
            Tools.RegexLineByLine(
                "./CMakeLists.txt",
                re.compile(r"(set\s*\(\s*CMAKECONFIG_INSTALL_DIR.*?)share", flags=re.IGNORECASE),
                lambda reMatch: f"{reMatch.group(1)}lib",
                1,
            )

        Builder.CMakeBuild(
            "OpenBLAS*.tar.gz",
            "OpenBLAS*",
            Prebuild,
            cmakeExtraParam=["-D BUILD_SHARED_LIBS=ON", "-D NUM_THREADS=64"],
            changeRequiredVersion=True,
        )

    def BuildHdf5():
        def Prebuild():
            # 禁止生成的lib名字加上debug后缀
            Tools.RegexLineByLine(
                "config/cmake_ext_mod/HDFMacros.cmake",
                re.compile(r"(set\s*?\(CMAKE_DEBUG_POSTFIX).*", re.IGNORECASE),
                lambda reMatch: f'{reMatch.group(1)} "")',
            )

        Builder.CMakeBuild(
            "hdf5*.tar.gz",
            "hdf5*",
            Prebuild,
            cmakeExtraParam=[
                "-D HDF5_ENABLE_Z_LIB_SUPPORT=ON",
                "-D BUILD_TESTING=OFF",
                "-D ONLY_SHARED_LIBS=ON",
                "-D HDF5_INSTALL_INCLUDE_DIR=include/hdf5",
                "-D HDF5_INSTALL_CMAKE_DIR=lib/cmake/hdf5",  # 烦人!
            ],
        )

    def BuildMlpack():
        if Config.TARGET_OS != TargetOs.linux:
            return
        os.chdir(Config.DIR_BASE)
        Tools.Decompress("src_package/stb*.tar.gz", f"{Config.DIR_INSTALL_ROOT}/include")
        SUBPROCESS_RUN(
            input=f"mv {Config.DIR_INSTALL_ROOT}/include/stb/include/* {Config.DIR_INSTALL_ROOT}/include/stb/",
            check=True,
        )
        Tools.RemoveFileOrDirs(f"{Config.DIR_INSTALL_ROOT}/include/stb/include")

        def Prebuild():
            # 删除 IMPLICIT_INCLUDE_DIRECTORIES 会导致误删除必要的include 目录
            Tools.RegexLineByLine(
                "CMake/cotire.cmake",
                re.compile(r"list.*?REMOVE_ITEM.*?_IMPLICIT_INCLUDE_DIRECTORIES.*", flags=re.IGNORECASE),
                lambda reMatch: f"# {reMatch.group(0)}",
            )

        cmakeExtraParam = ["-D BUILD_TESTS=OFF"]
        if Config.BUILD_TYPE == BuildType.debug:
            cmakeExtraParam.extend(["-D DEBUG=ON", "-D PROFILE=ON"])
        Builder.CMakeBuild(
            "mlpack*.tar.gz",
            "mlpack*",
            Prebuild,
            cmakeExtraParam=cmakeExtraParam,
            changeRequiredVersion=True,
            parallelJobs=multiprocessing.cpu_count() // 2,  # 编译比较耗内存，减少个数避免出错
        )


if __name__ == "__main__":
    Config.InitConfig()
    parser = argparse.ArgumentParser("Build ThirdParty")
    parser.add_argument("--debug_env", action="store_true", help="debug env")
    parser.add_argument("--no_clean", action="store_true", help="don't clean old build cache")
    args = parser.parse_known_args(sys.argv[1:])
    if args[0].debug_env:
        Tools.Log(f"Debug env, next, exter new interactive shell...")
        returncode = SUBPROCESS_RUN(env=Config.EnvDict()).returncode
        Tools.Log(f"Exit with {returncode}!")
        sys.exit(returncode)
    if args[0].no_clean:
        Config.InitBoostCmakeArgs()
    else:
        Tools.RemoveFileOrDirs(Config.DIR_BUILD_TMP)
        os.makedirs(Config.DIR_BUILD_TMP, exist_ok=True)
        Tools.RemoveFileOrDirs(Config.DIR_INSTALL_ROOT)

    Builder.BuildLua()
    Builder.CMakeBuild(
        "fmt*.tar.gz",
        "fmt*",
        cmakeExtraParam=["-D FMT_DOC=OFF", "-D FMT_TEST=OFF", "-D BUILD_SHARED_LIBS=OFF"],
        changeRequiredVersion=True,
    )
    Builder.CMakeBuild(
        "spdlog*.zip",
        "spdlog*",
        cmakeExtraParam=["-D SPDLOG_ENABLE_PCH=ON", "-D SPDLOG_BUILD_PIC=ON", "-D SPDLOG_FMT_EXTERNAL=ON"],
    )
    Builder.CMakeBuild(
        "zlib*.zip",
        "zlib*",
        cmakeExtraParam=[
            f"-D INSTALL_INC_DIR:PATH={Config.DIR_INSTALL_ROOT}/include/zlib",
            f"-D INSTALL_PKGCONFIG_DIR:PATH={Config.DIR_INSTALL_ROOT}/lib/pkgconfig",
        ],
    )
    Builder.CMakeBuild(
        "zstd*.tar.gz",
        "zstd*",
        cmakeExtraParam=[
            f"-D CMAKE_INSTALL_INCLUDEDIR={Config.DIR_INSTALL_ROOT}/include/zstd",
        ],
        buildDir="build/cmake/build",
    )
    # Builder.CMakeBuild("brotli*.tar.gz", "brotli*", buildDir="out")
    Builder.BuildSqlite3()
    Builder.BuildPugixml()
    Builder.BuildOpenssl()
    Builder.BuildIconv()
    Builder.BuildBoost()
    if Config.BUILD_VIDEO_AUDIO:
        Builder.BuildJpeg()
        Builder.BuildYuv()
        Builder.BuildSdl2()
        Builder.BuildOpus()
        Builder.BuildX264()
        if Config.TARGET_OS != TargetOs.android:
            # 汇编代码不支持android平台，性能差
            Builder.CMakeBuild("x265*.tar.gz", "x265*", buildDir="source/build")
        Builder.BuildVpx()
        Builder.BuildFfmpeg()

    if Config.BUILD_MACHINE_LEARNING:
        Builder.BuildOpenBlas()
        Builder.CMakeBuild(
            "superlu*.zip",
            "superlu*",
            cmakeExtraParam=[
                "-D USE_XSDK_DEFAULTS_DEFAULT=TRUE",
                "-D BLA_VENDOR=OpenBLAS",
                "-D BUILD_SHARED_LIBS=ON",
                f"-D CMAKE_INSTALL_INCLUDEDIR={Config.DIR_INSTALL_ROOT}/include/superlu",
            ],
            changeRequiredVersion=True,
        )
        Builder.CMakeBuild(
            "eigen*.tar.gz",
            "eigen*",
            cmakeExtraParam=[
                f"-D CMAKEPACKAGE_INSTALL_DIR={Config.DIR_INSTALL_ROOT}/lib/cmake/Eigen3",
                f"-D PKGCONFIG_INSTALL_DIR={Config.DIR_INSTALL_ROOT}/lib/pkgconfig",
                "-D EIGEN_TEST_CXX11=ON",
                "-D EIGEN_TEST_AVX2=ON",
                "-D EIGEN_TEST_F16C=ON",
                "-D EIGEN_TEST_FMA=ON",
            ],
            changeRequiredVersion=True,
        )
        Builder.BuildHdf5()
        Builder.CMakeBuild(
            "armadillo-*.tar.xz",
            "armadillo-*",
            cmakeExtraParam=[
                "-D OPENBLAS_PROVIDES_LAPACK=ON",
            ],
            changeRequiredVersion=True,
        )
        Builder.CMakeBuild("ensmallen*.tar.gz", "ensmallen*", changeRequiredVersion=True)
        Builder.CMakeBuild(
            "cereal*.zip",
            "cereal*",
            cmakeExtraParam=[
                "-D BUILD_SANDBOX=OFF",
                "-D BUILD_TESTS=OFF",
            ],
            changeRequiredVersion=True,
        )
        Builder.BuildMlpack()
        Builder.CMakeBuild(
            "faiss*.zip",
            "faiss*",
            cmakeExtraParam=[
                "-D FAISS_ENABLE_GPU=OFF",
                "-D FAISS_ENABLE_PYTHON=OFF",
                "-D FAISS_OPT_LEVEL=avx2",
                "-D BLA_VENDOR=OpenBLAS",
                "-D BUILD_TESTING=OFF",
                "-D CMAKE_INSTALL_DATAROOTDIR:PATH=lib/cmake",
            ],
        )

    Builder.CMakeBuild(
        "pybind11*.tar.gz",
        "pybind11*",
        cmakeExtraParam=[f"-D CMAKE_INSTALL_DATAROOTDIR={Config.DIR_INSTALL_ROOT}/lib", "-D PYBIND11_TEST=OFF"],
    )

    if Config.TARGET_OS == TargetOs.linux:
        # ----设置runpath，避免开发或部署时找不到依赖库 -------
        SUBPROCESS_RUN(
            input=f"patchelf --debug --set-rpath {Config.INSTALL_RPATH} {Config.DIR_INSTALL_ROOT}/lib/*.so",
            check=True,
        )
