---
title: Windows常见的编码问题
date: 2023-05-12 23:23:24
tags:
- error
---



# 编码



## 什么是编码



*”编码的诞生是带有一定场景和目的性的“*



所谓场景既是需要用**数字来表达信息**的时候，很容易想到计算机，计算机只认01，恰好与之吻合。

目的就更好理解了，编码的出现就是为了解决01环境下无法表达信息的情况。



## 什么是编码问题



直观的例子就是“鸡同鸭讲”



“鸡叫”是一种编码，“🦆叫”又是一种编码，他们属于不同的物种，语言不同即编码不兼容，就会出现双非都听不懂对方在说什么的情况。

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512233127194.png" alt="image-20230512233127194" style="zoom:33%;" />（我不是什么小黑子，我只是单纯觉得这张图片好看）



放在实际情况来看，编码异常也就是，编码方和解码方采用不同的方式进行操作，导致双方得到的结果错误的情况，典型的如：

比如我编码采用GBK，解码采用UTF-8，就会出现如下问题：

![image-20230512233438898](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512233438898.png)





## Windows平台的编码问题



就主流操作系统来看，Mac和Linux采用了UTF-8的编码，而Window却默认采用了GBK的编码。

而GBK对于UTF-8的中文解码是存在不兼容的。所以很容易出现乱码的情况。

![image-20230512234056143](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512234056143.png)





## 如何解决Windows的编码问题



一般发生编码异常的高发段（对于程序员）有如下：

1. 源文件编码
2. 编译器编码
3. 终端编码



源文件编码容易理解，也就是代码的编码方式（代码本质就是纯文本），编译器也好理解，源文件由编译处理得到编译文件，读取过程中如果与源文件编码不符就会出现异常。终端是执行二进制文件的平台，编码一般不会造成错误，但是会使得一些信息不能读取和及时发现。



### 文件

关于源文件编码，编译器编码主流的IDE应该都支持设定



如Jetbrains全家桶设置基本如下

Settings -> Help -> Edit Custom VM Options  

![image-20230512234817788](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512234817788.png)



末尾加入两行配置

```text
# 文件编码
-Dfile.encoding=UTF-8
# 终端编码
-Dconsole.encoding=UTF-8
```



再进行如下配置

![image-20230512235016472](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512235016472.png)



### 终端

关于终端的编码问题有两种解决

1. 通过chcp 65001修改当前会话的编码为UTF-8(临时性的)

全局配置可考虑修改注册表

计算机\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Command Processor

添加一条字符串值（这样Cmd开启就会执行这条指令将cmd编码改为UTF-8）

![image-20230512235306940](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512235306940.png)





2. 必杀技，全局设置

![image-20230512235437963](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512235437963.png)





![image-20230512235503942](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512235503942.png)



![image-20230512235521392](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230512235521392.png)



但是一般不推荐，谁还没有接收到过GBK编码的文件，要是你收到了GBK编码的文件你还不得乖乖地改回来？Windows用户量也不是盖地啊。
