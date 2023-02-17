---
title: Okhttp全解析
date: 2023-02-15 19:38:26
tags:
- Android
---



# Okhttp-http



## 基础信息

> - 依赖信息
>
>   ```groovy
>   implementation("com.squareup.okhttp3:okhttp:4.10.0")
>   ```
>
> - 作用
>
>   可用于http及websocket的Http Client请求框架



## 关键概念



> HTTP网络请求中涉及2个重要概念
>
> - Request
> - Response
>
> 即请求和响应

>Okhttp的设计上为了贴合现实的网络请求，规划了5个类
>
>- `OkHttpClient`
>
>  客户端实体，可以进行网络请求细节的配置
>
>- `Request`
>
>  客户端网络请求报文
>
>- `Response`
>
>  服务端网络请求响应报文
>
>- `Call`
>
>  HTTP请求
>
>- `WebSocket`
>
>  Websocket请求

> Okhttp做的很好的一点是使用者基本上只需要和上面几个类打交道
>
> - http请求
>
> ```kotlin
> val request = Request.Builder()
>     .url("https://www.example.com")
>     .headers(Headers.headersOf())
>     .method("get","This is body".toRequestBody())
>     .build()
> 
> val client = OkHttpClient()
> val call = client.newCall(request)
> val response = call.execute()
> ```
>
> - websocket
>
> ```kotlin
> val client = OkHttpClient()
> 
> val request = Request.Builder()
>     .url("ws://www.example.com")
>     .build()
> 
> val webSocket = client.newWebSocket(request, object : WebSocketListener() {
>     //...
> })
> 
> val isSuccess = webSocket.send("hello from client")
> ```



## Http



### Request 

> An HTTP request. Instances of this class are immutable if their body is null or itself immutable.
>
> 一个HTPP的请求，该实例是不可变的。

> 一个Request由5部分组成
>
> - url
>
>   网络请求的url值
>
> - method
>
>   网络请求方法类型
>
> - headers
>
>   网络请求head参数
>
> - body
>
>   网络请求体
>
> - tags
>
>   request上的标记信息，**不用于网络请求**。
>
> - cacheControl
>
>   网络请求缓存策略
>
> - isHttps
>
>   网络请求是否是https

```kotlin
class Request internal constructor(
  @get:JvmName("url") val url: HttpUrl,
  @get:JvmName("method") val method: String,
  @get:JvmName("headers") val headers: Headers,
  @get:JvmName("body") val body: RequestBody?,
  internal val tags: Map<Class<*>, Any>
) {
    val cacheControl: CacheControl
		get() {
          var result = lazyCacheControl
          if (result == null) {
            result = CacheControl.parse(headers)
            lazyCacheControl = result
          }
          return result
        }
    
  	val isHttps: Boolean
    	get() = url.isHttps
    
}
```



> Request的创建不支持直接new，由于需要的配置比较多，所以采用了Builder设计模式

```kotlin
Request.Builder()
    .url("url地址")
    .addHeader(name = "key", value = "value")
    .method(method = "get", body = null)
    .tag(type = String::class.java, tag = "tag")
    .cacheControl(
        CacheControl.Builder()
            .noCache()
            .build()
    )
```



#### url

> url的配置有三种方法

- way1

```kotlin
open fun url(url: String): Builder {
      // Silently replace web socket URLs with HTTP URLs.
      // 获取url
      val finalUrl: String = when {
          //websocket协议的建立需要先进行http请求协议升级。
        url.startsWith("ws:", ignoreCase = true) -> {
          "http:${url.substring(3)}"
        }
        url.startsWith("wss:", ignoreCase = true) -> {
          "https:${url.substring(4)}"
        }
        else -> url
      }
	  // 将url转化为HttpUrl类
      return url(finalUrl.toHttpUrl())
    }

//解析并构建
fun String.toHttpUrl(): HttpUrl = Builder().parse(null, this).build()
```

- way2

```kotlin
open fun url(url: URL) = url(url.toString().toHttpUrl())
```

- way3

```kotlin
open fun url(url: HttpUrl): Builder
```



#### header

> 能够对header操作的有如下

- way1

```kotlin
open fun addHeader(name: String, value: String) = apply {
  //internal var headers: Headers.Builder
  headers.add(name, value)
}

//headers
fun add(name: String, value: String) = apply {
      checkName(name)
      checkValue(value, name)
    //添加k-v
      addLenient(name, value)
}

internal fun addLenient(name: String, value: String) = apply {
    //internal val namesAndValues: MutableList<String> = ArrayList(20)
    //由于header的k是可以重复的，所以采用了一个数组装配
      namesAndValues.add(name)
      namesAndValues.add(value.trim())
}
```

- way2

```kotlin
open fun removeHeader(name: String) = apply {
  headers.removeAll(name)
}
// 移除所有k匹配的k-v键值对
fun removeAll(name: String) = apply {
      var i = 0
      while (i < namesAndValues.size) {
        if (name.equals(namesAndValues[i], ignoreCase = true)) {
          namesAndValues.removeAt(i) // name
          namesAndValues.removeAt(i) // value
          i -= 2
        }
        i += 2
      }
}
```

- way3

```kotlin
open fun header(name: String, value: String) = apply {
      headers[name] = value
}

// 将key对于的value设置为新的值
operator fun set(name: String, value: String) = apply {
      // 校验合法性
      checkName(name)
      checkValue(value, name)
      // 移除后再添加
      removeAll(name)
      addLenient(name, value)
}
```

- way4

```kotlin
// 前面的几个方法封装的已经很好了，基本上也用不上。
open fun headers(headers: Headers) = apply {
  this.headers = headers.newBuilder()
}
```



#### method

> 方法有两类，一类是安全的，内置的

- way1

```kotlin
 open fun get() = method("GET", null)

 open fun head() = method("HEAD", null)

 open fun post(body: RequestBody) = method("POST", body)

 @JvmOverloads
 open fun delete(body: RequestBody? = EMPTY_REQUEST) = method("DELETE", body)

 open fun put(body: RequestBody) = method("PUT", body)

 open fun patch(body: RequestBody) = method("PATCH", body)
```

- way2

```kotlin
open fun method(method: String, body: RequestBody?): Builder = apply {
  require(method.isNotEmpty()) {
    "method.isEmpty() == true"
  }
  if (body == null) {
    require(!HttpMethod.requiresRequestBody(method)) {
      "method $method must have a request body."
    }
  } else {
    require(HttpMethod.permitsRequestBody(method)) {
      "method $method must not have a request body."
    }
  }
  this.method = method
  this.body = body
}
```



#### body

> body即`RequestBody`

> 类关系图如下

![image-20230216170810826](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230216170810826.png)



> RequestBody

> 一个抽象模板类

```kotlin
abstract class RequestBody {

  /** 返回该body的content-type类型 */
  abstract fun contentType(): MediaType?

  /**
  	body的长度（单位为字节），如果不确定长度返回-1
   */
  @Throws(IOException::class)
  open fun contentLength(): Long = -1L

  /** 向body内写入内容（BufferedSink类似于OutputStream，着属于okio的内容了。） */
  @Throws(IOException::class)
  abstract fun writeTo(sink: BufferedSink)

  /**
	http是否是双工的。
	http/2以下都是半双工，只能由client向服务端发送，而不能由server主动向client发送。
	http/2以后加入了服务端推送的特性，可以实现服务端主动向客户端推送消息。
   */
  open fun isDuplex(): Boolean = false

  /**
	
   */
  open fun isOneShot(): Boolean = false

  // 创建responseBody的扩展方法
  // 其实也就是new一个匿名类返回。
  companion object {
    @JvmStatic
    @JvmName("create")
    fun String.toRequestBody(contentType: MediaType? = null): RequestBody {
      var charset: Charset = UTF_8
      var finalContentType: MediaType? = contentType
      if (contentType != null) {
        val resolvedCharset = contentType.charset()
        if (resolvedCharset == null) {
          charset = UTF_8
          finalContentType = "$contentType; charset=utf-8".toMediaTypeOrNull()
        } else {
          charset = resolvedCharset
        }
      }
      val bytes = toByteArray(charset)
      return bytes.toRequestBody(finalContentType, 0, bytes.size)
    }

    /** Returns a new request body that transmits this. */
    @JvmStatic
    @JvmName("create")
    fun ByteString.toRequestBody(contentType: MediaType? = null): RequestBody {
      return object : RequestBody() {
        override fun contentType() = contentType

        override fun contentLength() = size.toLong()

        override fun writeTo(sink: BufferedSink) {
          sink.write(this@toRequestBody)
        }
      }
    }

    /** Returns a new request body that transmits this. */
    @JvmOverloads
    @JvmStatic
    @JvmName("create")
    fun ByteArray.toRequestBody(
      contentType: MediaType? = null,
      offset: Int = 0,
      byteCount: Int = size
    ): RequestBody {
      checkOffsetAndCount(size.toLong(), offset.toLong(), byteCount.toLong())
      return object : RequestBody() {
        override fun contentType() = contentType

        override fun contentLength() = byteCount.toLong()

        override fun writeTo(sink: BufferedSink) {
          sink.write(this@toRequestBody, offset, byteCount)
        }
      }
    }

    /** Returns a new request body that transmits the content of this. */
    @JvmStatic
    @JvmName("create")
    fun File.asRequestBody(contentType: MediaType? = null): RequestBody {
      return object : RequestBody() {
        override fun contentType() = contentType

        override fun contentLength() = length()

        override fun writeTo(sink: BufferedSink) {
          source().use { source -> sink.writeAll(source) }
        }
      }
    }
   
  }
}
```



> FormBody

> 也是采用了Builder设计模式

> 只能通过builder才能进行类实例的创建

```kotlin
val formBody = FormBody.Builder(charset = UTF_8.INSTANCE)
    .add(name = "", value = "")
    .addEncoded(name = "", value = "")
    .build()
```



> 构造的时候可以指定一个Charset

> 再添加表单参数的时候可以选择使用编码对String进行编码

```kotlin
class Builder @JvmOverloads constructor(private val charset: Charset? = null) {
  private val names = mutableListOf<String>()
  private val values = mutableListOf<String>()

  fun add(name: String, value: String) = apply {
    names += name.canonicalize(
        encodeSet = FORM_ENCODE_SET,
        plusIsSpace = true,
        charset = charset
    )
    values += value.canonicalize(
        encodeSet = FORM_ENCODE_SET,
        plusIsSpace = true,
        charset = charset
    )
  }

  fun addEncoded(name: String, value: String) = apply {
    names += name.canonicalize(
        encodeSet = FORM_ENCODE_SET,
        alreadyEncoded = true,
        plusIsSpace = true,
        charset = charset
    )
    values += value.canonicalize(
        encodeSet = FORM_ENCODE_SET,
        alreadyEncoded = true,
        plusIsSpace = true,
        charset = charset
    )
  }

  fun build(): FormBody = FormBody(names, values)
}
```



> MultiPartBody

```kotlin
val multiPart = MultipartBody.Builder()
        .addPart("part1".toRequestBody())
        .addPart("part2".toRequestBody())
        .build()
```

> Builder内部封装了一个list，addPart就是往里找个集合里面塞东西

```kotlin
class Builder @JvmOverloads constructor(boundary: String = UUID.randomUUID().toString()) {
  private val boundary: ByteString = boundary.encodeUtf8()
  private var type = MIXED
  private val parts = mutableListOf<Part>()

  /**
   * Set the MIME type. Expected values for `type` are [MIXED] (the default), [ALTERNATIVE],
   * [DIGEST], [PARALLEL] and [FORM].
   */
  fun setType(type: MediaType) = apply {
    require(type.type == "multipart") { "multipart != $type" }
    this.type = type
  }

  /** Add a part to the body. */
  fun addPart(body: RequestBody) = apply {
    addPart(Part.create(body))
  }

  /** Add a part to the body. */
  fun addPart(headers: Headers?, body: RequestBody) = apply {
    addPart(Part.create(headers, body))
  }

  /** Add a form data part to the body. */
  fun addFormDataPart(name: String, value: String) = apply {
    addPart(Part.createFormData(name, value))
  }

  /** Add a form data part to the body. */
  fun addFormDataPart(name: String, filename: String?, body: RequestBody) = apply {
    addPart(Part.createFormData(name, filename, body))
  }

  /** Add a part to the body. */
  fun addPart(part: Part) = apply {
    parts += part
  }

  /** Assemble the specified parts into a request body. */
  fun build(): MultipartBody {
    check(parts.isNotEmpty()) { "Multipart body must have at least one part." }
    return MultipartBody(boundary, type, parts.toImmutableList())
  }
}
```



#### tag

> tag本质上就是一种标记，网络请求用不上，这个标记是用来标识request的。

> 在拦截器里面做处理的时候可能会依据不同的请求做特殊处理，这个tag可能就有用武之地了

```kotlin
open fun tag(tag: Any?): Builder = tag(Any::class.java, tag)

open fun <T> tag(type: Class<in T>, tag: T?) = apply {
  if (tag == null) {
    // internal var tags: MutableMap<Class<*>, Any> = mutableMapOf()
    tags.remove(type)
  } else {
    if (tags.isEmpty()) {
      tags = mutableMapOf()
    }
    tags[type] = type.cast(tag)!! // Force-unwrap due to lack of contracts on Class#cast()
  }
}
```



#### cache



> CacheControl是网络缓存的选项

> 而且它是通过Request的header指定的

> 它只是提供了更好的api支持

```kotlin
open fun cacheControl(cacheControl: CacheControl): Builder {
  val value = cacheControl.toString()
  return when {
    value.isEmpty() -> removeHeader("Cache-Control")
    else -> header("Cache-Control", value)
  }
}
```







## Websocket







