---
title: xv6内核构建
tags:
  - xv6
  - linux
  - 操作系统
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/xv6.png'
date: 2024-01-04 10:47:58
---


# xv6内核构建





# 概念



- xv6

> Xv6是由[麻省理工学院](https://baike.baidu.com/item/麻省理工学院/117999?fromModule=lemma_inlink)(MIT)为操作系统工程的课程（代号6.828）,开发的一个教学目的的操作系统。
>
> ——百度文库





# 准备



设备：Win11

环境：WSL2

> WSL 版本： 2.0.14.0
> 内核版本： 5.15.133.1-1
> WSLg 版本： 1.0.59
> MSRDC 版本： 1.2.4677
> Direct3D 版本： 1.611.1-81528511
> DXCore 版本： 10.0.25131.1002-220531-1700.rs-onecore-base2-hyp
> Windows 版本： 10.0.22631.2861
>
> Linux：Debian
>
> Linux foolish-pc 5.15.133.1-microsoft-standard-WSL2 #1 SMP Thu Oct 5 21:02:42 UTC 2023 x86_64 GNU/Linux

源码：[XV6](https://github.com/mit-pdos/xv6-riscv.git)



# 环境配置



> Note: WSL环境配置略



## 源代码下载



> 本文主要是对RISC-V架构的[xv6](https://github.com/mit-pdos/xv6-riscv.git))项目进行构建



## Risc-V工具链下载



> [源代码](https://github.com/riscv-collab/riscv-gnu-toolchain)下载

```shell
git clone https://github.com/riscv/riscv-gnu-toolchain
```



> 下载必要的工具

On Ubuntu, executing the following command should suffice:

```
$ sudo apt-get install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev
```



On Fedora/CentOS/RHEL OS, executing the following command should suffice:

```
$ sudo yum install autoconf automake python3 libmpc-devel mpfr-devel gmp-devel gawk  bison flex texinfo patchutils gcc gcc-c++ zlib-devel expat-devel
```



On Arch Linux, executing the following command should suffice:

```
$ sudo pacman -Syyu autoconf automake curl python3 libmpc mpfr gmp gawk base-devel bison flex texinfo gperf libtool patchutils bc zlib expat
```



Also available for Arch users on the AUR: https://aur.archlinux.org/packages/riscv-gnu-toolchain-bin

On OS X, you can use [Homebrew](http://brew.sh/) to install the dependencies:

```
$ brew install python3 gawk gnu-sed gmp mpfr libmpc isl zlib expat texinfo flock
```





>  构建

```shell
./configure --prefix=/opt/riscv
make
```



> 构建完成后会在/opt/riscv下生成工具链

```shell
➜  riscv-gnu-toolchain git:(master) ll /opt/riscv
total 24K
drwxr-xr-x 2 root root 4.0K Jan  4 08:22 bin
drwxr-xr-x 4 root root 4.0K Jan  4 08:22 include
drwxr-xr-x 4 root root 4.0K Jan  4 08:22 lib
drwxr-xr-x 3 root root 4.0K Jan  3 23:21 libexec
drwxr-xr-x 5 root root 4.0K Jan  3 23:24 riscv64-unknown-elf
drwxr-xr-x 7 root root 4.0K Jan  4 08:22 share
```



## 安装qemu



[官方教程](https://www.qemu.org/download/#linux)

```shell
sudo apt install qemu-system
```







# 构建



> 修改xv6 Makefile
>
> /opt/riscv/bin/
>
> Note：
>
> 记住路径末尾一定得加/而且不能有空格（因为xv6是直接将TOOLPREFIX和工具拼接）
>
> 否则就会报错Permission Denied

```shell
# riscv64-unknown-elf- or riscv64-linux-gnu-
# perhaps in /opt/riscv/bin
TOOLPREFIX = /opt/riscv/bin/
```



> 除此之外由于risc-v工具链编译的文件为了防止重名加了一个riscv64-unknown-elf-的前缀。
>
> 我们还需要软连接一下

```shell
for file in /opt/riscv/bin/riscv64-unknown-elf-*; do
    ln -s "$file" "$(basename "$file" | sed 's/^riscv64-unknown-elf-//')"
done
```



```shell
make qemu
```



# 坑点



> 1. 千万，千万，千万！！！不能将RiscV工具链设置到Path中
>
> 很可能会覆盖掉原本的gcc，导致程序运行的各种错误



# 参考



[XV6 Doc](https://pdos.csail.mit.edu/6.828/2023/xv6.html)
