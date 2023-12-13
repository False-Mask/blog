---
title: Android NDK 项目报错
tags:
  - ndk
  - error
date: 2023-12-13 13:10:00
---




# 背景



在学习 ART-TI 的过程中发现了GitHub 有一个[项目](https://juejin.cn/post/6844903913846472717?searchId=202312122200446C0CD5E9C9E03747C3C8)

但是把项目拉下来以后发现会有报错

![image-20231213125739987](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231213125739987.png)



# 解决



1. 确认报错原因

从报错中很容易得出是 NDK 的配置问题

> NDK not configured. 



2. 配置 NDK([官网](https://developer.android.google.cn/studio/projects/install-ndk?hl=zh-cn)配置教程)

```properties
# local.properties
ndk.dir=/Users/fool/Library/Android/sdk/ndk/18.1.5063045
```





# 新的问题



> Invalid revision: 3.22.1-g37088a8



>  查了下是 cmake 不兼容的问题。

配置了一下 cmake 版本

```properties
# local.properties
cmake.dir=/Users/fool/Library/Android/sdk/cmake/3.6.4111459
```



# 配置成功



>  CONFIGURE SUCCESSFUL in 1s



总结下NDK 工厂需要配置

- SDK
- cmake
- NDK



