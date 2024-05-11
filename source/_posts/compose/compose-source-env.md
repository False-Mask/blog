---
title: Compose源码环境搭建
tags:
- compose
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/first_app.png'
date: 2024-05-11 16:41:31
---




# Compose源码环境搭建



> 进行Compose源代码环境构建。



Compose Compiler：1.5.1



# 前言



1. 为什么需要使用Linux作为搭建环境?（指跑源代码）

   > 这肯定不是我想用Linux开发，因为Compose项目的限制
   >
   > a. 我们可以看一部分project的manifest声明，发现什么？项目依赖了ios的sdk，linux的sdk，就是没有Windows。这想表明什么就不言而喻了
   >
   > ![image-20240511142907854](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511142907854.png)
   >
   > b. 通过查看Compose项目的一部分的文件你也能发现一些端倪，没有gradlew.bat？所以使用Windows跑环境会有一些问题的。
   >
   > （不清楚是否能跑。但是绝对是要做一些配置的。）
   >
   > ![image-20240511143537716](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511143537716.png)

2. 为什么选择配置Compose Compiler的Release环境？

   > 很简单，如果你拉取最新的commit项目未必能跑起来，是否稳定你只能求助开发者。
   >
   > 这是因为开发分值是feature最多的分值，而且你不清楚他是否是开发完成的，这种项目的不稳定因素肯定就尽可能控制下。
   >
   > （问就是踩过坑。）

3. Release的版本号为什么选择1.5.1

   > 我们可以查看下目前的[Compose Compiler Release Note](https://developer.android.com/jetpack/androidx/releases/compose-compiler)，以及[Compose Kotlin Compiler对照表](https://developer.android.com/jetpack/androidx/releases/compose-kotlin)
   >
   > 目前是2025/5 Compose Compiler已经开发到了1.5.13。说实话我也很难选。到时是哪个版本。
   >
   > 所以我创建了一个Compose工程，Compose Compiler的版本为1.5.1。
   >
   > ```kotlin
   > composeOptions {
   >         kotlinCompilerExtensionVersion = "1.5.1"
   > }
   > ```





# 源码获取



> Compose的源代码有两个地方可以获取，一是GitHub，而是AOSP仓库。
>
> 先说下结论，最好从AOSP中获取。



> androidx 在 Github上有仓库。地址为https://github.com/androidx/androidx.git
>
> 既然是Androidx肯定是包含Compose的。但是有一个很大的问题。
>
> 由于Androidx是AOSP工程的一部分。Github仓库的有源代码，但是跑不起来（因为缺失了部分依赖）。
>
> （头铁的可以自己去试试。）
>
> 所以我们只能去拉AOSP完整的依赖了。



> Note: “拉AOSP完整的依赖”的意思不是说拉取AOSP所有代码，AOSP代码有很多分支。
>
> 具体分支可见https://android.googlesource.com/
>
> 我们只是拉取AOSP开放代码中一条与Compose-Compiler相关的**分支**。



## 下载Repo工具

> AOSP代码是使用自研的Repo下载的。
>
> 所以我们如果需要下载源代码我们就得下载Repo工具。



[可参考官网教程](https://source.android.com/docs/setup/download/source-control-tools#repo)

> 下载repo并将其放到了PATH下。

```shell
mkdir ~/bin
PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
```



## Repo Sync拉取



> 使用[北京外国语大学开源软件镜像站](https://mirrors.bfsu.edu.cn/)初始化repo仓库
>
> 指定branch 为androidx-compose-compiler-release(Compose release 1.5.1)

```shell
repo init -u https://mirrors.bfsu.edu.cn/git/AOSP/platform/manifest -b 85ae76552bd5c9307eed386b71645008359e9761
```



> 紧接着通过repo sync等待拉取完成源代码就下载完成了。

>  就可以使用Idea、Android Studio打开配置环境了。

```shell
repo sync
```





> Note：
>
> androidx-compose-compiler-release为Compiler release的manifest分支。(通过查Commit记录猜出来的)
>
> 但是具体release版本是没有打tag的。（下面讲述下我是如何找到1.5.1 release版本的manifest commit id的）
>
> 1. 首先我们去[Compose Release Note](https://developer.android.com/jetpack/androidx/releases/compose-compiler#1.5.1)去查release的时间（2023-7-26）
>
> ![image-20240511140621624](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511140621624.png)
>
> 2. 查找代码提交的时间也就是上图[Version 1.5.1 contains these commits.](https://android.googlesource.com/platform/frameworks/support/+log/da73ca08c9fa56221ac7d21a156934ddffa94a78..2afaef8594bfa39e6e31140fbecae2a2c71eaf29/compose/compiler)发现有两次提交
>
>    ![image-20240511140742534](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511140742534.png)
>
> 3. 查看[最近一次提交](https://android.googlesource.com/platform/frameworks/support/+/774ff92bfd471177d7e6a57236c31d8e917b11be)的时间（2023-7-21 +0000），这里发现是可以单独下载源代码的[[tgz](https://android.googlesource.com/platform/frameworks/support/+archive/774ff92bfd471177d7e6a57236c31d8e917b11be.tar.gz)]。（不过我们是要下载源代码以及它的依赖。）
>
> ![image-20240511140859781](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511140859781.png)
>
> 4. 通过git查找下commit，发现有一个匹配的commit信息
>
> ```shell
> cd .repo/manifests/ #进入manifests git路径
> git checkout androidx-compose-compiler-release # 切换到指定分支
> git log --since 2023-7-20 --until 2023-7-26 # 查找时间段的commit记录
> ```
>
> ![image-20240511141320362](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511141320362.png)
>
> 5. 通过Change-Id去[Google Code View](https://android-review.googlesource.com/dashboard/self)网页查找当前Commit记录发现修改了support（androidx）的版本
>
> ![image-20240511141730856](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511141730856.png)
>
> 6. 查找下这个版本的[git log信息](https://android.googlesource.com/platform/frameworks/support/+log/2afaef8594bfa39e6e31140fbecae2a2c71eaf29)，发现附近3个commit均无变更记录。因此commit版本同774ff92版本（1.5.1最后一个commit）为 Compose Compiler release 1.5.1分支。
>
> ![image-20240511141934595](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511141934595.png)
>
> 7. 得出结论85ae76552bd5c9307eed386b71645008359e9761 manifest commitId为 Compose Compiler 1.5.1 release











# 项目配置





## 完整运行



> 这种方式运行由于需要拉取整个项目。这种方式会比较卡。
>
> 但是可以用于修改源码并进行重新打包。





> 通过使用上述拉取的AOSP代码进行build。



> 这里需要稍微提示一下项目的路径和结构

> 如下是compiler项目的路径，在如下位置使用Idea、Android Studio打开即可

```shell
frameworks/support/compose/compiler
```



> 如下是compiler的整体结构

- compiler

  > 只是一个壳，用于做发布等任务

- compiler-host

  > 具体的compiler模块

![image-20240511161206495](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511161206495.png)





## 极简配置



> 这种配置由于是使用的产物进行配置，所以运行会比较快。
>
> 而且能在任何平台上跑。
>
> 唯一的缺点就是不能修改源代码。



### 配置方法

1. 创建Compose Project

![image-20240511144816343](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511144816343.png)

2. 配置Gradle

```java
testImplementation("com.github.tschuchortdev:kotlin-compile-testing:1.5.0")
testImplementation("androidx.compose.compiler:compiler:1.5.1") {
    exclude("org.jetbrains.kotlin","kotlin-scripting-compiler")
}
testImplementation("org.jetbrains.kotlin:kotlin-scripting-compiler:1.9.0")
testImplementation("org.jetbrains.kotlin:kotlin-compiler-embeddable:1.9.0")
testImplementation(libs.androidx.material3)
```



### 常见问题





#### Compose Compiler没源代码的问题

点开项目发现没有代码

![image-20240511145332593](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511145332593.png)

打开Library Settings，查看源文件。发现是空的......

![image-20240511145405208](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511145405208.png)

![image-20240511145442659](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240511145442659.png)



解决方法有两种：

1.去AOSP repo sync

2.去Android source下载指定的commit id的patch文件



如果跟着前文拉取的Compose的源代码。可以直接使用上述指令打包一份源代码

```shell
cd frameworks/support/compose/compiler/compiler-hosted/src/main/java # 进入源码路径
tar cvf compose-compiler-1.5.1-source.jar androidx # 打包源代码
```



如果没有拉取Compose 1.5.1的源代码，可以通过下载[[tgz](https://android.googlesource.com/platform/frameworks/support/+archive/774ff92bfd471177d7e6a57236c31d8e917b11be.tar.gz)]获取1.5.1 指定commit的源代码。最后重复上述操作自己打包一份。



然后导入IDE就可以开始调试了。                                                                                                                                                                                                                                                                                                                









# 参考



[AOSP源代码官方下载教程](https://source.android.com/docs/setup/download)

[Repo下载教程](https://source.android.com/docs/setup/download/source-control-tools#repo)

[Compose Compiler Release Note](https://developer.android.com/jetpack/androidx/releases/compose-compiler)

[Compose Kotlin Compatibility 对照表](https://developer.android.com/jetpack/androidx/releases/compose-kotlin)



