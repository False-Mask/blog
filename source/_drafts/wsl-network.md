---
title: WSL之网络设置
date: 2023-03-26 14:55:37
tags:
- error
- wsl
categories:
- error
---



#  WSL 0x8007023e



## 背景

> C:\Users\fool>wsl
>
> {应用程序错误} 应用程序发生异常 %s (0x
> Error code: Wsl/Service/CreateInstance/CreateVm/ConfigureNetworking/0x8007023e



## 查看WSL网卡



​	![image-20230326151648569](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230326151648569.png)



## 启用Hyper-V

![image-20230326154550355](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230326154550355.png)



![image-20230326154634327](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230326154634327.png)





## 尝试1



- 删除WSL网卡

- 删除WSL并重装



结果是并没有什么用

最离谱的是现在WSL网卡也没了

![image-20230329002325206](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230329002325206.png)









## 尝试2



搜索到WSL中的[issue 9016](https://github.com/microsoft/WSL/issues/9016)

![image-20230329002436926](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230329002436926.png)