---
title: Glide核心原理概览
date: 2023-04-08 16:57:14
tags:
- glide
- android
---



# Glide



## 主线流程



> Glide是一个图片加载库

> Glide通过压缩和缓存，解决了图片内存占用大的问题

> Glide的过程大致分为5步



![image-20230408211150203](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230408211150203.png)



1. Glide初始化
2. 生命周期绑定（Glide -> RequestManager）
3. 请求构建（RequestManager -> RequestBuilder）
4. 请求配置（RequestBuilder -> RequestBuilder）
5. 发起请求资源获取，解码，转化，呈现（RequestBuilder -> Target）



Note:

1. 前4步通常是在Main线程，主要是做好Request的配置
2. 最后一步最为复杂也最为重要，完成资源获取和界面呈现。其中资源获取在后台线程，然后界面的呈现为main线程。



## 尺寸优化



> Glide会自定依据`ImageView`的大小对图片进行缩放，以免图像的像素过高导致`Bitmap`无法分配或者OOM的问题





## Bitmap缓存



> Glide在加载过程中有使用缓存来加速图片的加载，其中Bitmap会被缓存到`BitmapPool`中

> 其中BitmapPool采用了LRU的淘汰策略，即淘汰最近最少使用的一个Bitmap。

> 除此之外`BitmapPool`还设置了一个大小阈值超过阈值即的内容不会被缓存

> `Bitmap`的复用策略和`LruPoolStrategy`有关

> `LruPoolStrategy`作为一个接口他有3个实现类

> - `AttributeStrategy`
>
>   将Bitmap的width，height和config计算得到key，缓存和获取必须要要求key一致。
>
> - `SizeConfigStrategy`
>
>   要求config一致，但是size必须要大于等于所需的bitmap
>
> - `SizeStrategy`
>
>   只要求bitmap size（width * height * config像素大小）大于所需bitmap即可复用



## 二级缓存



> Glide的缓存分为两级：**内存**，**磁盘**

> Glide的缓存顺序为：内存-> 磁盘 -> 网络

> 二级缓存不同于Bitmap缓存，二级缓存是对加载的资源进行缓存，以达到快速加载，减少流量消耗的目的。



## 其他



> Glide的支线特别多，有特别多内容都没有例举

> - Transitions 
> - Transmisions
> - 网络状态监听
> - 组件生命周期监听
> - Generated API
> - 配置
> - ......

> 上述内容或许会分析或许不会，终归**不是最为核心**的内容。