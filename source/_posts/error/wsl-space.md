---
title: 记一次WSL扩容问题
date: 2023-03-19 14:24:23
tags:
- error
- wsl
categories:
- error
---



# 记一次WSL扩容问题



## 背景

> 昨日心血来潮，突发地想打一个自己的Android镜像。
>
> 所以呢拉了aosp的源代码，sync过程异常平稳（除了跑了我50G+流量...），
>
> 构建的过程出了一个小插曲吧，wsl 报了一个空间不足。





## 环境



WSL 2 + Ubuntu 22.04

![image-20230319143016680](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319143016680.png)



## 解决过程



> 第一我肯定不会认为这是aosp的锅，所以定是不会去aosp查issue。
>
> 既然是空间不足，这一定是系统的问题，而系统是wsl，不去[微软官网](https://learn.microsoft.com/zh-cn/windows/wsl)查解决方法还真没别的了。



> 既然是空间异常铁定是找[磁盘管理](https://learn.microsoft.com/zh-cn/windows/wsl/disk-space)专栏doc了





## 事后总结



简单来说就是wsl的`ex4.vhdx`文件是有大小限制的。

> - 虚拟大小
>
>   WSL Ubuntu认为的大小空间，即WSL内`lsblk`的大小
>
> - 物理大小
>
>   WSL是在Windows平台运行的，所有的文件内容是存储在`ext4.vhdx`中的，此大小指的是占据宿主机的空间。

> 下图表示
>
> - WSL能用的最大空间是500G
> - WSL Ubuntu占用的内容加载一起占据物理机182G

![image-20230319143623222](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319143623222.png)



> 检测一下

![image-20230319144109619](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319144109619.png)



![image-20230319144530665](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319144530665.png)





## gain



简单认识了如下3个linux磁盘相关的指令

- df

  Linux df（英文全拼：disk free） 命令用于显示目前在 Linux 系统上的文件系统磁盘使用情况统计。

  可以用于查看系统的文件系统列表和使用情况，也可以用于查找文件所属于文件系统。

- du

  du命令来自于英文词组“Disk Usage”的缩写，其功能是**用于查看文件或目录的大小**。

- lsblk

  lsblk命令**用于列出所有可用块设备的信息**，而且还能显示他们之间的依赖关系，但是它不会列出RAM盘的信息。



## 最后



一位不知名的程序员看着**爆红**的**D盘**露出了久违的**微笑**...



![image-20230319145951515](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319145951515.png)
