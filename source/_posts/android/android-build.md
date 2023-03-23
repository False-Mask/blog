---
title: Android源码构建
date: 2023-03-21 13:27:43
tags:
- android
categories:
- android
---

# Android 源码编译



## 基础要求



### 硬件要求

[官网链接](https://source.android.com/docs/setup/start/requirements?hl=zh-cn#hardware-requirements)



### 环境配置

[官方链接](https://source.android.com/docs/setup/start/initializing?hl=zh-cn)



## 源码下载



### 创建文件夹

```shell
mkdir aosp
```



### 安装源代码控制工具

```shell
mkdir ~/bin
PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
```



### 配置repo

```shell
vim ~/.bashrc
export REPO_URL='https://mirrors.bfsu.edu.cn/git/git-repo'
```





### 初始化镜像仓库

[分支列表](https://source.android.com/docs/setup/about/build-numbers?hl=zh-cn#source-code-tags-and-builds)

```shell
repo init -u https://mirrors.bfsu.edu.cn/git/AOSP/platform/manifest -b android-10.0.0_r47
```







## 编译



### 设置环境

```shell
source build/envsetup.sh
```



### 选择编译目标

```shell
lunch
```



| 构建类型  | 使用情况                                                     |
| :-------- | :----------------------------------------------------------- |
| user      | 权限受限；适用于生产环境                                     |
| userdebug | 与“user”类似，但具有 root 权限和调试功能；是进行调试时的首选编译类型 |
| eng       | 具有额外调试工具的开发配置                                   |



### 构建源代码

-j8：指定8个线程进行编译

```shell
m -j8
```

- **`droid`** - `m droid` 是正常 build。此目标在此处，因为默认目标需要名称。
- **`all`** - `m all` 会构建 `m droid` 构建的所有内容，加上不包含 `droid` 标记的所有内容。构建服务器会运行此命令，以确保包含在树中且包含 `Android.mk` 文件的所有元素都会构建。
- **`m`** - 从树的顶部运行构建系统。这很有用，因为您可以在子目录中运行 `make`。如果您设置了 `TOP` 环境变量，它便会使用此变量。如果您未设置此变量，它便会从当前目录中查找相应的树，以尝试找到树的顶层。您可以通过运行不包含参数的 `m` 来构建整个源代码树，也可以通过指定相应名称来构建特定目标。
- **`mma`** - 构建当前目录中的所有模块及其依赖项。
- **`mmma`** - 构建提供的目录中的所有模块及其依赖项。
- **`croot`** - `cd` 到树顶部。
- **`clean`** - `m clean` 会删除此配置的所有输出和中间文件。此内容与 `rm -rf out/` 相同。



## 构建完成

> 构建完成后会在out文件夹输出镜像文件

`out/target/product/<your product>`

