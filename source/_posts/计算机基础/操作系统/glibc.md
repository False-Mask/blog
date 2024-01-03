---
title: glibc
tags:
  - glibc
  - linux
cover: >-
  https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gnu.png
date: 2023-12-28 17:07:46
---


# 认识Glibc





# 概念



- Glibc

> *[glibc](https://www.gnu.org/software/libc/#download)是*linux下面c标准库的实现，即GNU C Library
>
> 和java的jdk，kotlin的stdlib类似。

- 查看我们所用的glibc版本

```shell
➜  glibc getconf GNU_LIBC_VERSION
# 输出
glibc 2.31
```

- 关于陌生

> 我们其实对Glibc特别特别陌生，主要是当我们点开一些C语言的基础调用的时候，我们是看不了具体的源代码的。
>
> 所以就这样Glibc在我们心里越来越模糊，黑盒化





# 编译Glibc



> 认识Glibc的最好的方法就是编译它。打一个包，如果可以还可以装到Linux系统上自己用。
>
> [官方文档](https://sourceware.org/glibc/started.html)



## 下载



[下载地址](https://mirror.koddos.net/gnu/libc/)



> 为了可玩性，笔者下载了最新版的Glibc
>
> glibc-2.38.tar.gz

```shell
# 下载
➜  glibc curl -O https://mirror.koddos.net/gnu/libc/glibc-2.38.tar.gz

# 解压
➜  glibc tar -xvf glibc-2.38.tar.gz

# check下是否安装完成
➜  glibc ll
total 36M
drwxr-xr-x 68 fool fool 4.0K Aug  1 01:54 glibc-2.38
-rw-r--r--  1 fool fool  36M Dec 28 11:22 glibc-2.38.tar.gz
```



## 配置



> 创建一个路径用于放置构建产物



```shell
# 离开源代码路径
cd ..
# 创建新的路径
mkdir build
# 进入
cd build
# 配置生成makefile
../glibc-2.38/configure --prefix=/usr
```





## 构建



> 前面配置已经生成了合适的Makefile。

```shell
make
```



> 查看一下

```cpp
➜  build ll | grep "libc\..*"
-rwxr-xr-x  1 fool fool 4.6K Dec 28 14:07 debugglibc.sh
-rw-r--r--  1 fool fool  33M Dec 28 14:07 libc.a
-rw-r--r--  1 fool fool  55K Dec 28 14:03 libc.map
-rwxr-xr-x  1 fool fool  15M Dec 28 14:07 libc.so
lrwxrwxrwx  1 fool fool    7 Dec 28 14:07 libc.so.6 -> libc.so
```





