---
title: frida基础配置
date: 2023-12-09 17:24:29
tags:
- 逆向
---



# Frida 环境搭建



## 背景

> 最近工作中需要逆向对比，调研学习中发现了 Frida 这么一个不错的框架



## 基础条件



设备：root 手机



# 配置



## 安装 pip 依赖



```shell
pip install frida-tools
```



## 安装 frida-server



[release](https://github.com/frida/frida/releases)

选择合适的版本（Frida 可以对Android/IOS/Mac/Window/Linux进行逆向分析）

记得选择 frida-server

![image-20231209173405989](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231209173405989.png)



## push到手机



> 本文主要是进行 Android 逆向环境搭建
>
> 如果是其他平台，请在指定的平台允许 server 脚本

Unzip

```shell
tar -xvf frida-server-XX.xz
```

Push

```shell
adb push frida-server /data/local/tmp/frida-server
```

设置权限

```shell
chmod 777 /data/local/tmp/frida-server
```







## 执行 frida-server



```shell
/data/local/tmp/frida-server &
```





## 完成



> 环境搭建完成





