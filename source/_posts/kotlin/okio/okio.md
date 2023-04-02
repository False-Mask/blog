---
title: Okio基础使用
date: 2023-04-01 13:29:05
tags:
- okio
- io
---



# Okio使用篇

> Note: okio版本为3.3.0

> Okio是一个用于io操作的框架

> Okio的出现源于`java.io`以及`java.nio`不够简洁，不易使用，学习成本大

> Okio解决了上手成本的问题

> 目前okio已经由kotlin重写，并使用了kotlin multiplatform实现跨平台

> 这已是Okio的几乎所有类

from [doc](https://square.github.io/okio/3.x/okio/okio/okio/)

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402164721569.png" alt="image-20230402164721569" style="zoom:50%;" />



## Okio组成

[ByteString & Buffer](https://square.github.io/okio/#bytestrings-and-buffers)

- `ByteString`

  String的增强类，其中包含二进制编码，Base64，UTF-8编码，等。

- `Buffer`

  byte[]的增强，`Buffer`的组织不同于`byte[]`，`Buffer`的数据会形成一个链表结构，一个节点只是类的一部分。



[Source & Sink](https://square.github.io/okio/#sources-and-sinks)

- `Source`
- `Sink`

类似于`java.io`中的`InputStream`和`OutputStream`，不同的是`Source/Sink`类关系更少，方法更少，更简单，并且还提供了`Timeout`机制，允许使用者自定义超时策略



## ByteString

> ByteString是String的争抢版，支持编码，摘要计算

```kotlin
fun main() {

    val m = "Hello".toByteArray().toByteString()
    println(m.base64())
    println(m.sha256().hex())
    println(m.base64Url())
    println(m.md5().hex())
    println(m.sha1().hex())
    println(m.sha512().hex())

}
```



## Buffer

> 与ByteBuffer类似

```kotlin
actual class Buffer : BufferedSource, BufferedSink, Cloneable, ByteChannel
```



![image-20230402200510068](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402200510068.png)



![image-20230402200541451](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402200541451.png)



## Sink



> Sink为一个接口

> 标志性的方法就是write，表明它和OutputStream一样可以输出内容

![image-20230402202750615](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402202750615.png)



> 如下是Okio-JVM的继承关系

![image-20230402202954870](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402202954870.png)



## Source

![image-20230402203105809](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402203105809.png)



> Source的实现类和Sink是成对的

![image-20230402203209050](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402203209050.png)



## Sink/Source使用



Sink/Source的创建很简单

- FileSystem直接创建
- 使用扩展函数

![image-20230402213950127](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230402213950127.png)





```kotlin
fun fromNet() {

    Socket("127.0.0.1", 7899)
        .source()
        .buffer()
        .gzip()

}

fun fromFile() {
    
    val source = FileSystem.SYSTEM
    	.source("okio/test.txt".toPath())
        .buffer()
    val arr = ByteArray(1024)

    while (!source.exhausted()) {
        val len = source.read(arr)
        println(String(arr, 0, len))
    }
}
```



## timeout



```kotlin
fun main() {

    val source = File("okio/test.txt")
        .inputStream()
        .buffered()
        .source()
        .buffer()
        .apply {
            // 1 nano seconds 以后即超时。
            timeout().deadline(1,TimeUnit.NANOSECONDS)
        }


    val read = source.read(ByteArray(1024))
    println(read)

}
```



> 输出

> Exception in thread "main" java.io.InterruptedIOException: deadline reached
> 	at okio.Timeout.throwIfReached(Timeout.kt:103)
> 	at okio.InputStreamSource.read(JvmOkio.kt:91)
> 	at okio.RealBufferedSource.read(RealBufferedSource.kt:262)
> 	at okio.RealBufferedSource.read(RealBufferedSource.kt:75)
> 	at com.example.okio.TestKt.main(Test.kt:31)
> 	at com.example.okio.TestKt.main(Test.kt)
