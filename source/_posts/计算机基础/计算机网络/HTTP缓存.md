---
title: HTTP缓存
date: 2023-02-17 11:03:09
tags:
- 计算机基础
- 计算机网络
categories:
- 计算机基础
- 计算机网络
---



# HTTP缓存



> 参考自[MDN文档](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers/Cache-Control)



## 什么是HTTP缓存

> 缓存是一种思想。为了加速效率，把经常访问的内容保存下来。之后就不需要经过低效率的渠道获取内容从而提升效率。



## 缓存术语



- 缓存有效期（max-age）

  数据是变动的，一旦缓存就要考虑数据的一致性，HTTP的协议制定者也不是傻子，也考虑到了这点，所以缓存是有一个时限的。

- 新鲜（fresh）

  如果一个缓存在它的时限之内，则是新鲜的

- 过时（stale）

  如果一个缓存在它的时限之外，则是过时的

- 共享缓存`Public cache`

  缓存可能存放在公共网络中，即CDN等公共网络缓存设备可以对请求进行缓存（开发者应避免个人信息的泄露）

- 私有缓存`Private cache`

  缓存可以存放在本地，这部分是用户独享。

- 存储`Store respose`

  对可缓存的响应报文进行存储（存放不代表一定能复用）

- 复用`Reuse response`

  缓存命中，使用缓存

- 验证`Revalidate response`

  询问服务器当前持有的缓存是否过期（通常用于协商缓存）

- 新鲜响应`Fresh response`

  缓存没有过期，可以使用

- 过期响应`Stale  response`

  缓存过期了，需要对缓存进行刷新

- 缓存年龄`Age`

  响应请求自生成以后过了多长时间（缓存是以响应生成时间开始计算，而不是接受到响应开始计算）



> 缓存分为2类
>
> - 本地缓存
>
>   即缓存在本地的缓存，通常是游览器，或者本地的数据库等。
>
> - 远程缓存
>
>   即缓存在远端的缓存，也称为web缓存，通常是缓存代理设备，CDN等

> 缓存结构如下

> 终端的请求会依次经过Local和Remote缓存，其中只要有一个命中，就不会请求源服务器。

![image-20230217112018919](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230217112018919.png)



> 为了之后描述方便，我们称Local Cache为**客户端缓存**，Web Cache为**服务端缓存**。

> 下图我们姑且称为**引入缓存的C/S架构结构**

![image-20230217113222876](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230217113222876.png)



> 缓存有时间限制，没超时的是新鲜的可以复用，超时的需要向服务器校验才能使用

> 校验的结果有两个一个是没过期，一个是过期。没过期服务器不会返回资源，自个用缓存就好，过期了服务端会返回最新的资源



![image-20230217223830060](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230217223830060.png)



## HTTP缓存是如何实现的



> HTTP缓存是通过加Header字段实现的。

> Note:
>
> HTTP是协议，协议这种东西**只防君子不防小人**，也就是说是一个软性规定，得两方都遵守才行。



缓存的过程中需要涉及两类行为

- 缓存控制

  怎么缓存，缓存多久

- 缓存验证

  如何判断缓存发生变动



>关于缓存控制目前最为流行，兼容性最好的也就是`Cache-Control`

> **`Cache-Control`** 通用消息头字段，被用于在 http 请求和响应中，通过指定指令来实现缓存机制。

> 这里得分两类情况讨论，即
>
> - Response
>
>   Response是发送给客户端的，所以它可以控制客户端缓存
>
> - Request
>
>   Request是发送给服务端的，所以它是用于控制服务端缓存



> 客户端可以在 HTTP 请求中使用的标准 Cache-Control 指令。

```text
Cache-Control: max-age=<seconds>
Cache-Control: max-stale[=<seconds>]
Cache-Control: min-fresh=<seconds>
Cache-control: no-cache
Cache-control: no-store
Cache-control: no-transform
Cache-control: only-if-cached
```

> 服务器可以在响应中使用的标准 Cache-Control 指令。

```text
Cache-control: must-revalidate
Cache-control: no-cache
Cache-control: no-store
Cache-control: no-transform
Cache-control: public
Cache-control: private
Cache-control: proxy-revalidate
Cache-Control: max-age=<seconds>
Cache-control: s-maxage=<seconds>
```



> 关于缓存验证通过

- If-None-Match/ETag
- If-Modified-Since/Last-Modified



## Cache-Control



> 客户端缓存是由服务端在Response中指定Cache-Control

> 服务端缓存时由客户端在Request中指定Cache-Control



### Response



- #### `max-age`

```text
Cache-Control: max-age=604800
```

即缓存有效期604800秒



- #### `s-maxage`

```text
Cache-Control: s-maxage=604800
```

同max-age只不过是用于告知共享缓存（CDN，Proxy）的有效期为604800秒



- #### `no-cache`

```text
Cache-Control: no-cache
```

不是不采用缓存，是指缓存的有效期为0，即你可以缓存，但是每次使用前得问我有没有过期，过期了我给你新的，没过期你就自己用缓存，我就不发给你了。



- #### `no-store`

```text
Cache-Control: no-store
```

不允许缓存（本地和代理设备都不能缓存）



- #### `must-revalidate`

```text
Cache-Control: max-age=604800, must-revalidate
```

缓存有效期为604800，过期了不允许你擅自使用过期的数据，必须先询问我。

因为有些场景是允许使用脏数据的

1. 验证了数据没有变
2. 服务器504（Gateway Timeout）了



- #### `proxy-revalidate`

同must-revalidate指定的是（CDN，Proxy），即web缓存过期后必须校验才能使用。





- `public`

```text
Cache-Control: public
```

缓存共享，代理设置可以缓存。





- `private`

```text
Cache-Control: private
```

缓存私有，只要本地可以缓存，网络中间代理不可以缓存。



- `no-transform`

有时网络的中间代理为了极致的效率，会对缓存内容进行压缩，比如图片压缩，代码去空格等。该选项告诉中间代理不要做转换。







### Request



- `no-cache`

  每次请求网络中间代理设备需要校验资源是否发生变动。

- `no-store`

  告诉网络中间设备不要缓存资源，即时资源是可以被缓存的。

- `max-age`

  网络中间设备缓存的请求不能超过指定时间，否则就得找源服务器校验

- `max-stale`

  客户端允许脏数据最大范围

- `min-fresh`

  网络中间设备需要包装在这个时间段内保持数据是干净的

- `only-if-cached`

  客户端只接受缓存的数据，如果缓存服务器没缓存也不需要向源服务器验证请求的新鲜度。

- `no-transform`

  缓存服务不能对请缓存进行修改，保持缓存原有的模样





## Validate

> 缓存过期了需要验证，验证是依据如下两对Header实现的

- If-None-Match/ETag

  客户端带有If-None-Match: etag header，如果没变服务端会返回403，变了会返回ETag。（这里的Etag近似于摘要）

- If-Modified-Since/Last-Modified

  客户端带有If-Modified-Since: 时间的header，如果在当前时间内没变服务端会返回403，变了会返回Last-Modified。



