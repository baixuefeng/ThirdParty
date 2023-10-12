# ThirdParty

常用第三方库的集成。

## windows 编译

### 依赖
1. Visual Studio 2019，其他未测试；
2. perl，注意添加到系统环境变量中；
3. python3.6或以上，注意添加到系统环境变量中；
4. cmake3.14或以上，注意添加到系统环境变量中；
5. ninja(windows, 因为nmake不支持并发编译)，注意添加到系统环境变量中；
6. nasm 2.14以上, 缺少的话许多库无法启用汇编优化，注意添加到系统环境变量中；
7. git lfs，因为有的文件是用git lfs管理；

ffmpeg编译依赖

1. msys64, 注意添加到系统环境变量中；
    注意msys和代码路径中不要有空格、中文。打开msys命令行，安装编译工具。
    （可以在 msys64\etc\pacman.d\mirrorlist.* 中修改源的优先级，提高下载速度。）
    pacman -S automake autoconf libtool make pkg-config diffutils tar man

2. 如果不是从VS命令行启动、而后执行 msys2_shell.cmd，必须把 /usr/bin/link.exe 改名 msys-link.exe，否则会和msvc的link冲突。
    windows_build.py中的启动方式即使不修改也不会有问题。

在**VC命令工具提示（位置：开始菜单/Visual Studio 2019/x64 Native Tools Command Prompt for VS 2019）**的环境下运行：  
`python windows_build.py`

## linux编译

1. 以ubuntu20为例，安装编译工具: 
   ```sh
    # 基本工具
    apt install -y perl bash-completion less file zip unzip bc

    # 开发工具
    apt install -y autoconf automake make libtool pkg-config gcc g++ gdbserver nasm ninja-build diffutils patchelf gfortran libgomp1
    apt install -y cmake cmake-curses-gui
    apt install -y lld clang lldb llvm-dev libomp-dev clangd clang-format clang-tidy
    ln -s `which lld` /usr/local/bin/ld

    # [可选]下面是音视频相关库，可以在linux_build.sh中修改 BUILD_VIDEO_AUDIO 选择是否编译。

    # SDL依赖库，用于音视频播放
    apt install -y libasound2-dev 
    # 视频播放
    apt install -y libx11-dev libxext-dev libxcursor-dev libxinerama-dev libxi-dev libxrandr-dev libxrender-dev libxss-dev libxxf86vm-dev
    apt install -y libwayland-dev libwayland-bin wayland-protocols libegl1-mesa-dev libxkbcommon-dev
    apt install -y libegl1-mesa-dev libgles2-mesa-dev
   ```

2. `bash linux_build.sh`, 选择linux

## android编译

1. 下载android-ndk ( https://dl.google.com/android/repository/android-ndk-r21b-linux-x86_64.zip )，这里使用的r21b，
    更低版本未测试，在linux上交叉编译。所需的其他编译工具与linux编译相同。默认解压位置：/opt
2. `bash linux_build.sh`, 选择android

## 使用

其他工程的CMakeLists.txt中include 文件ThirdParty.cmake，就可以很方便地使用这些第三方库了。
详情看ThirdParty.cmake，cmake相关的知识这里不赘述。
