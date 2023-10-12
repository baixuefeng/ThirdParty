# ThirdParty

Integration of common third-party libraries.

## windows compile

### Dependence
1. vs2019 is used, and the lower version is not tested；
2. perl，Note: add to the system environment variable;
3. >=python3.6，Note: add to the system environment variable;
4. >=cmake3.14，Note: add to the system environment variable;
5. ninja(windows, Because nmake does not support concurrent compilation)，Note: add to the system environment variable;
6. >=nasm 2.14, Without it, many libraries cannot enable assembly optimization. Note: add to the system environment variable;
7. git lfs，Because some files are managed with git-lfs;

ffmpeg compile dependence

1. msys64, Note: add to the system environment variable;
    Note: Msys and code path should be free of spaces and Chinese characters. Open the msys command line and install the compiler.
    (You can modify the priority of the source in `msys64\etc\pacman.d\mirrorlist.*` to improve the download speed.)
    pacman -S automake autoconf libtool make pkg-config diffutils tar man

2. If you do not start from the vs command line and then execute msys2_shell.cmd, you must change /usr/bin/link.exe to msys-link.exe, otherwise it will conflict with MSVC's link.exe. The startup mode in windows_build.py will not be a problem even if it is not modified.

Run in the environment of **VC command tooltip (Location: Start menu/visual studio 2019/x64 native tools command prompt for vs 2019)**:
`python windows_build.py`

## linux compile

1. Taking Ubuntu 20 as an example, install the compiler: 
   ```sh
    # base tools
    apt install -y perl bash-completion less file zip unzip bc

    # develop tools
    apt install -y autoconf automake make libtool pkg-config gcc g++ gdbserver nasm ninja-build diffutils patchelf gfortran libgomp1
    apt install -y cmake cmake-curses-gui
    apt install -y lld clang lldb llvm-dev libomp-dev clangd clang-format clang-tidy
    ln -s `which lld` /usr/local/bin/ld

    # [optional] The following are audio and video related libraries, you can change `BUILD_VIDEO_AUDIO` in linux_build.sh to select whether to compile

    # SDL dependency libraries for audio and video playback
    apt install -y libasound2-dev
    # video playback
    apt install -y libx11-dev libxext-dev libxcursor-dev libxinerama-dev libxi-dev libxrandr-dev libxrender-dev libxss-dev libxxf86vm-dev
    apt install -y libwayland-dev libwayland-bin wayland-protocols libegl1-mesa-dev libxkbcommon-dev
    apt install -y libegl1-mesa-dev libgles2-mesa-dev
   ```

2. `bash linux_build.sh`, select linux

## android compile

1. Download android-ndk ( https://dl.google.com/android/repository/android-ndk-r21b-linux-x86_64.zip )，R21b used here, an earlier version is not tested. Cross compiled on Linux. Other compilation tools required are the same as Linux compilation. Default decompression location：/opt
2. `bash linux_build.sh`, select android

## Instructions

Include `ThirdParty.cmake` in other project's CMakeLists.txt, then you can easily use these third-party libraries.
See `ThirdParty.cmake` for details. Cmake related knowledge will not be repeated here.
