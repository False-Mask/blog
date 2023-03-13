---
title: Http2连接建立
tags:
- http
- 计算机网络
- 计算机基础
categories:
- 计算机基础
- 计算机网络
---



# Http/2连接建立过程

> Http协议概述

![image-20230304151558421](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230304151558421.png)





http2支持http1.1的所有功能，并比http1.1更高效

HTTP/2 中的基本协议单元是一个帧。每种帧类型都有不同的用途。





## 协议标识



HTTP/2有两个版本标识:

- h2: 构建与TLS之上的`HTTP/2`协议实现, 在连接的TLS握手阶段, 通过TLS扩展协议的`ALPN`字段标识。
- h2c: 基于明文的TCP传输的协议实现, 在`HTTP1.1`升级协商阶段的`Upgrade`字段标识。无安全性保障。



## h2c

> 在并不知道对方是否支持http2的情况下。
>
> http客户端通过使用http升级机制建立http2连接

> 客户端发送

```text
GET / HTTP/1.1
Host: server.example.com
Connection: Upgrade, HTTP2-Settings
Upgrade: h2c
HTTP2-Settings: <base64url encoding of HTTP/2 SETTINGS payload>
```

> 服务端响应（如果不支持http2连接）

```text
HTTP/1.1 200 OK
Content-Length: 243
Content-Type: text/html
...
```

> 如果支持http2连接

```text
HTTP/1.1 101 Switching Protocols
Connection: Upgrade
Upgrade: h2c

[ HTTP/2 connection ...
```



> 服务端发送的第一个`HTTP/2`帧必须是一个`SETTINGS`帧, 客户端收到101的状态响应码后也必须发送一个`SETTINGS`帧, 组成`Connection Preface`(连接序言)。



1. 客户端通过TCP连接服务器
2. 客户端发送SETTINGS帧到服务器，告诉服务器它支持的HTTP2参数
3. 服务器返回一个SETTINGS帧确认收到客户端的SETTINGS帧，告诉客户端服务器也支持哪些HTTP2参数
4. 客户端发送一个带有特殊标记的HTTP1.1请求到服务器，标记表示客户端支持HTTP2
5. 服务器收到请求后，返回101 Switching Protocols响应
6. TCP连接被升级到HTTP2，客户端和服务器可以发送HTTP2帧来通信



## h2

> 客户端可以通过其他方式了解特定服务器是否支持 HTTP/2

> 客户端必须发送连接前奏



1. 建立TCP连接
2. TLS握手
3. 发送http/2连接序言，发送settings帧



## Connection Preface

> "连接前奏" 有些地方也会翻译成 "连接序言"。

在 HTTP/2 中，每个端点都需要发送连接前奏作为正在使用的协议的最终确认，并建立 HTTP/2 连接的初始设置。客户端和服务器各自发送不同的连接前奏。

客户端连接前奏以 24 个八位字节的序列开始，以十六进制表示法为：

```text
 0x505249202a20485454502f322e300d0a0d0a534d0d0a0d0a
```

也就是说，连接前奏以字符串 "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" 开头。该序列必须后跟 SETTINGS 帧，该帧可以为空。客户端在收到 101 (交换协议)响应(指示成功升级)或作为 TLS 连接的第一个应用程序数据八位字节后立即发送客户端连接前奏。如果启动具有服务器对协议支持的 prior knowledge 的 HTTP/2 连接，则在建立连接时发送客户端连接前奏。



