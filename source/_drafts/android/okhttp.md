---
title: Okhttp全解析
date: 2023-02-15 19:38:26
tags:
- android
categories:
- android
- 网络
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

> Cache-Control也只能通过使用Builder来实例化

```kotlin
CacheControl.Builder()
    .noCache()
    .noTransform()
    .build()
```

![image-20230218102959969](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230218102959969.png)







### Response

> Response可以通过Builder构建，但是一般是内部使用，或者测试Mock数据的时候

![image-20230218105712006](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230218105712006.png)



#### head

> 有三种方法（同Reqeust）

- way1

```kotlin
open fun addHeader(name: String, value: String)
```

- way2

```kotlin
open fun header(name: String, value: String)
```

- way3

```kotlin
open fun headers(headers: Headers)
```



#### status

- way1

> 设置status code整型数据

```kotlin
open fun code(code: Int)
```

- way2

> 设置消息，比如200，表示success，504 Gateway timeout等

```kotlin
open fun message(message: String)
```





#### body

> 即`ResponseBody`

> 类结构图如下

![image-20230218110829678](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230218110829678.png)

> `ResponseBody`

> 从使用上看到了`RequestBody`的影子，实际上原理也类似

```kotlin
val r = Response.Builder()
    .body("a".toResponseBody())
```

```kotlin
val r = Response.Builder() 
	.body(ByteArray(10).toResponseBody())
```



> `CahchedResponseBody`

> 其实也是io的包装，而而且还是private，说明是内部使用的。

```kotlin
private class CacheResponseBody(
  val snapshot: DiskLruCache.Snapshot,
  private val contentType: String?,
  private val contentLength: String?
) : ResponseBody() {
  private val bodySource: BufferedSource

  init {
    val source = snapshot.getSource(ENTRY_BODY)
    bodySource = object : ForwardingSource(source) {
      @Throws(IOException::class)
      override fun close() {
        snapshot.close()
        super.close()
      }
    }.buffer()
  }

  override fun contentType(): MediaType? = contentType?.toMediaTypeOrNull()

  override fun contentLength(): Long = contentLength?.toLongOrDefault(-1L) ?: -1L

  override fun source(): BufferedSource = bodySource
}
```

> `RealResponseBody`
>
> 查包名`okhttp3.internal.http`就知道是内部使用的，api相对来说没那么好用。

```kotlin
class RealResponseBody(
  /**
   * Use a string to avoid parsing the content type until needed. This also defers problems caused
   * by malformed content types.
   */
  private val contentTypeString: String?,
  private val contentLength: Long,
  private val source: BufferedSource
) : ResponseBody() {

  override fun contentLength(): Long = contentLength

  override fun contentType(): MediaType? = contentTypeString?.toMediaTypeOrNull()

  override fun source(): BufferedSource = source
}
```





#### 其他



- protocol

> 协议类型

```kotlin
open fun protocol(protocol: Protocol)
```

> 是个枚举类

```kotlin
enum class Protocol(private val protocol: String) {
 
  HTTP_1_0("http/1.0"),

  HTTP_1_1("http/1.1"),

  @Deprecated("OkHttp has dropped support for SPDY. Prefer {@link #HTTP_2}.")
  SPDY_3("spdy/3.1"),
 
  HTTP_2("h2"),

  H2_PRIOR_KNOWLEDGE("h2_prior_knowledge"),

  QUIC("quic");

  override fun toString() = protocol

  companion object {

    @JvmStatic
    @Throws(IOException::class)
    fun get(protocol: String): Protocol {
      // Unroll the loop over values() to save an allocation.
      @Suppress("DEPRECATION")
      return when (protocol) {
        HTTP_1_0.protocol -> HTTP_1_0
        HTTP_1_1.protocol -> HTTP_1_1
        H2_PRIOR_KNOWLEDGE.protocol -> H2_PRIOR_KNOWLEDGE
        HTTP_2.protocol -> HTTP_2
        SPDY_3.protocol -> SPDY_3
        QUIC.protocol -> QUIC
        else -> throw IOException("Unexpected protocol: $protocol")
      }
    }
  }
}
```

- handshake

> TLS握手的实体类

```kotlin
open fun handshake(handshake: Handshake?)
```

- networkResponse

> 网络请求获取的原始数据

```kotlin
open fun networkResponse(networkResponse: Response?)
```

- cacheResponse

> 本地缓存获取的原生数据

```kotlin
open fun cacheResponse(cacheResponse: Response?)
```

- priorResponse

> okhttp支持自动重定向，`priorResponse`就是它前一个重定向的请求

```kotlin
open fun priorResponse(priorResponse: Response?)
```

- sentRequestAtMillis

> 请求发送的时间

```kotlin
open fun sentRequestAtMillis(sentRequestAtMillis: Long)
```

- receivedResponseAtMillis

> 请求接受的时间

```kotlin
open fun receivedResponseAtMillis(receivedResponseAtMillis: Long)
```

- request

> 与response对应的wire-level（满足协议要求）的request

```kotlin
open fun request(request: Request)
```





### Call

> Call是即将执行的网络请求

```kotlin
interface Call : Cloneable {
  
  fun request(): Request

  @Throws(IOException::class)
  fun execute(): Response

  fun enqueue(responseCallback: Callback)

  fun cancel()

  fun isExecuted(): Boolean

  fun isCanceled(): Boolean

  fun timeout(): Timeout

  public override fun clone(): Call

  fun interface Factory {
    fun newCall(request: Request): Call
  }
}
```



> Call虽然是一个接口，但是只有一个实现类`RealCall`

```kotlin
class RealCall(
  val client: OkHttpClient,
  /** The application's original request unadulterated by redirects or auth headers. */
  val originalRequest: Request,
  val forWebSocket: Boolean
) 
```



#### timeout

> 获取超时计时器

```kotlin
private val timeout = object : AsyncTimeout() {
    override fun timedOut() {
      cancel()
    }
  }.apply {
    timeout(client.callTimeoutMillis.toLong(), MILLISECONDS)
  }

override fun timeout() = timeout
```



#### clone

> 直接返回结果

```kotlin
override fun clone() = RealCall(client, originalRequest, forWebSocket)
```



#### request

> 返回最新的请求

```kotlin
override fun request(): Request = originalRequest
```



#### cancel

> cancel提供了线程安全的特征，但是这个安全是**有限**

> 能保证线程**可见性**，**禁止指令重排**，但不能实现原子性即可能重复cancel。

> 可能为了保证性能吧，安全性越高，性能就越弱

```kotlin
@Volatile private var canceled = false

override fun cancel() {
  if (canceled) return // Already canceled.

  canceled = true
  exchange?.cancel()
  connectionToCancel?.cancel()

  eventListener.canceled(this)
}
```



#### isCanceld

```kotlin
override fun isCanceled() = canceled
```



#### isExecuted

> 不同于cancel，call必须保证只能执行一次，所以需要保证较强的安全水平。

```kotlin
private val executed = AtomicBoolean()

override fun isExecuted(): Boolean = executed.get()
```



#### execute

> 执行请求

```kotlin
override fun execute(): Response {
  //修改flag，cas确保一次执行
  check(executed.compareAndSet(false, true)) { "Already Executed" }
  //启动计时器，超时取消执行。
  timeout.enter()
  //告知call开始了
  callStart()
  try {
    //通知调度器，该call开始执行
    client.dispatcher.executed(this)
    //执行获取响应结果
    return getResponseWithInterceptorChain()
  } finally {
    //告知调度器该call已经结束。
    client.dispatcher.finished(this)
  }
}
```



> 处理请求

```kotlin
internal fun getResponseWithInterceptorChain(): Response {
    // 构建拦截器链
    val interceptors = mutableListOf<Interceptor>()
    //自定义拦截器
    interceptors += client.interceptors
    //预制拦截器
    interceptors += RetryAndFollowUpInterceptor(client)
    interceptors += BridgeInterceptor(client.cookieJar)
    interceptors += CacheInterceptor(client.cache)
    interceptors += ConnectInterceptor
    //自定义网络拦截器
    if (!forWebSocket) {
      interceptors += client.networkInterceptors
    }
    interceptors += CallServerInterceptor(forWebSocket)

    val chain = RealInterceptorChain(
        call = this,
        interceptors = interceptors,
        index = 0,
        exchange = null,
        request = originalRequest,
        connectTimeoutMillis = client.connectTimeoutMillis,
        readTimeoutMillis = client.readTimeoutMillis,
        writeTimeoutMillis = client.writeTimeoutMillis
    )

    var calledNoMoreExchanges = false
    try {
      // 启动责任链处理
      val response = chain.proceed(originalRequest)
      // 取消处理
      if (isCanceled()) {
        response.closeQuietly()
        throw IOException("Canceled")
      }
      return response
    } catch (e: IOException) {
      // 异常处理
      calledNoMoreExchanges = true
      throw noMoreExchanges(e) as Throwable
    } finally {
      // 
      if (!calledNoMoreExchanges) {
        noMoreExchanges(null)
      }
    }
  }
```





#### enqueue

> 异步实现请求



```kotlin
override fun enqueue(responseCallback: Callback) {
  // 检验是否已经执行
  check(executed.compareAndSet(false, true)) { "Already Executed" }
	
  callStart()
  // 请求入队
  client.dispatcher.enqueue(AsyncCall(responseCallback))
}
```





### Client

> 客户端请求的实体类，可以用于做网络请求参数的配置





#### Interceptor

> 可以说式okhttp中核心的部分

> Interceptor分为三类
>
> - 内置拦截器
>
>   内部预置的拦截器
>
> - 网络拦截器
>
>   在内置拦截器之后起作用的拦截器
>
> - 普通拦截器
>
>   在内置拦截器之前起作用的拦截器



```kotlin
// Build a full stack of interceptors.
val interceptors = mutableListOf<Interceptor>()
//普通拦截器
interceptors += client.interceptors
// 内置拦截器
interceptors += RetryAndFollowUpInterceptor(client)
interceptors += BridgeInterceptor(client.cookieJar)
interceptors += CacheInterceptor(client.cache)
interceptors += ConnectInterceptor
if (!forWebSocket) {
  //网络拦截器
  interceptors += client.networkInterceptors
}
//内置拦截器
interceptors += CallServerInterceptor(forWebSocket)
```



##### 内置拦截器



###### RetryAndFollowUpInterceptor

> This interceptor recovers from failures and follows redirects as necessary. It may throw an IOException if the call was canceled.
>
> 此拦截器用于从失败的请求中回复并且在有必要的时候进行重定向，当请求取消时抛出IO异常。





> 类声明

```kotlin
class RetryAndFollowUpInterceptor(private val client: OkHttpClient) : Interceptor
```

> 总调度

```kotlin
override fun intercept(chain: Interceptor.Chain): Response {
  val realChain = chain as RealInterceptorChain
  var request = chain.request
  val call = realChain.call
  var followUpCount = 0
  var priorResponse: Response? = null
  var newExchangeFinder = true
  var recoveredFailures = listOf<IOException>()
  while (true) {
    // 为网络请求创建连接
    call.enterNetworkInterceptorExchange(request, newExchangeFinder)

    var response: Response
    var closeActiveExchange = true
    try {
      //处理取消
      if (call.isCanceled()) {
        throw IOException("Canceled")
      }

      try {
        // 向前推进
        response = realChain.proceed(request)
        // 时候开启新的连接
        newExchangeFinder = true
      } catch (e: RouteException) {
        // 尝试恢复连接
        if (!recover(e.lastConnectException, call, request, requestSendStarted = false)) {
          //恢复失败抛异常
          throw e.firstConnectException.withSuppressed(recoveredFailures)
        } else {
          recoveredFailures += e.firstConnectException
        }
        // 不需要重新建立连接
        newExchangeFinder = false
        continue
      } catch (e: IOException) {
        // An attempt to communicate with a server failed. The request may have been sent.
        if (!recover(e, call, request, requestSendStarted = e !is ConnectionShutdownException)) {
          throw e.withSuppressed(recoveredFailures)
        } else {
          recoveredFailures += e
        }
        newExchangeFinder = false
        continue
      }

      // Attach the prior response if it exists. Such responses never have a body.
      // 合并前一个连接
      if (priorResponse != null) {
        response = response.newBuilder()
            .priorResponse(priorResponse.newBuilder()
                .body(null)
                .build())
            .build()
      }

      val exchange = call.interceptorScopedExchange
      // 重定向request 
      val followUp = followUpRequest(response, exchange)

      if (followUp == null) {
        if (exchange != null && exchange.isDuplex) {
          call.timeoutEarlyExit()
        }
        closeActiveExchange = false
        return response
      }

      val followUpBody = followUp.body
      if (followUpBody != null && followUpBody.isOneShot()) {
        closeActiveExchange = false
        return response
      }

      response.body?.closeQuietly()
	
      // 限制重定向次数
      if (++followUpCount > MAX_FOLLOW_UPS) {
        throw ProtocolException("Too many follow-up requests: $followUpCount")
      }
	  // 更新重定向的请求地址
      request = followUp
      // 当前请求作为后一个
      priorResponse = response
    } finally {
      call.exitNetworkInterceptorExchange(closeActiveExchange)
    }
  }
}
```

> 重定向

```kotlin
private fun followUpRequest(userResponse: Response, exchange: Exchange?): Request? {
  val route = exchange?.connection?.route()
  val responseCode = userResponse.code

  val method = userResponse.request.method
  when (responseCode) {
    HTTP_PROXY_AUTH -> {
        // 代理身份验证
        // 407 
      val selectedProxy = route!!.proxy
      if (selectedProxy.type() != Proxy.Type.HTTP) {
        throw ProtocolException("Received HTTP_PROXY_AUTH (407) code while not using proxy")
      }
      return client.proxyAuthenticator.authenticate(route, userResponse)
    }

      //客户端身份验证
      // 401 
    HTTP_UNAUTHORIZED -> return client.authenticator.authenticate(route, userResponse)

      //重定向
      /// 30X
    HTTP_PERM_REDIRECT, HTTP_TEMP_REDIRECT, HTTP_MULT_CHOICE, HTTP_MOVED_PERM, HTTP_MOVED_TEMP, HTTP_SEE_OTHER -> {
      return buildRedirectRequest(userResponse, method)
    }

      //客户端超时 408
    HTTP_CLIENT_TIMEOUT -> {
      // 408's are rare in practice, but some servers like HAProxy use this response code. The
      // spec says that we may repeat the request without modifications. Modern browsers also
      // repeat the request (even non-idempotent ones.)
      if (!client.retryOnConnectionFailure) {
        // The application layer has directed us not to retry the request.
        return null
      }

      val requestBody = userResponse.request.body
      if (requestBody != null && requestBody.isOneShot()) {
        return null
      }
      val priorResponse = userResponse.priorResponse
      if (priorResponse != null && priorResponse.code == HTTP_CLIENT_TIMEOUT) {
        // We attempted to retry and got another timeout. Give up.
        return null
      }

      if (retryAfter(userResponse, 0) > 0) {
        return null
      }

      return userResponse.request
    }

      //服务不用
    HTTP_UNAVAILABLE -> {
      val priorResponse = userResponse.priorResponse
      if (priorResponse != null && priorResponse.code == HTTP_UNAVAILABLE) {
        // We attempted to retry and got another timeout. Give up.
        return null
      }

      if (retryAfter(userResponse, Integer.MAX_VALUE) == 0) {
        // specifically received an instruction to retry without delay
        return userResponse.request
      }

      return null
    }

      //There are too many connections from your internet address  421
    HTTP_MISDIRECTED_REQUEST -> {
      // OkHttp can coalesce HTTP/2 connections even if the domain names are different. See
      // RealConnection.isEligible(). If we attempted this and the server returned HTTP 421, then
      // we can retry on a different connection.
      val requestBody = userResponse.request.body
      if (requestBody != null && requestBody.isOneShot()) {
        return null
      }

      if (exchange == null || !exchange.isCoalescedConnection) {
        return null
      }

      exchange.connection.noCoalescedConnections()
      return userResponse.request
    }

    else -> return null
  }
}
```

> 该拦截器处理了如下status code，并在合适的时候进行retry
>
> 身份验证
>
> - 407
>
>   Proxy Authentication Required
>
> - 401
>
>   Unauthorized
>
> 重定向
>
> - 307/308
>
>   Temporary Redirect.
>
> - 300
>
>   Multiple Choices
>
> - 301
>
>   Moved Permanently.
>
> - 302
>
>   Temporary Redirect.
>
> - 303
>
>   See Other
>
> 其他
>
> - 408
>
>   Request timeout
>
> - 503
>
>   Service Unavailable.
>
> - 421
>
>   There are too many connections from your internet address





###### BridgeInterceptor

> 类型声明

> cookieJar用于管理cookie

```kotlin
class BridgeInterceptor(private val cookieJar: CookieJar) : Interceptor
```

> 核心实现



```kotlin
override fun intercept(chain: Interceptor.Chain): Response {
  // 获取请求
  val userRequest = chain.request()
  val requestBuilder = userRequest.newBuilder()
  // 获取body
  val body = userRequest.body
  if (body != null) {
    val contentType = body.contentType()
    if (contentType != null) { // content-type
      requestBuilder.header("Content-Type", contentType.toString())
    }

    val contentLength = body.contentLength()
    if (contentLength != -1L) { // 指定了content-length
      requestBuilder.header("Content-Length", contentLength.toString())
      requestBuilder.removeHeader("Transfer-Encoding") 
    } else { // 没有指定content-length，使用Transfer-Encoding： chunked
      requestBuilder.header("Transfer-Encoding", "chunked")
      requestBuilder.removeHeader("Content-Length")
    }
  }

  if (userRequest.header("Host") == null) { // 主机名
    requestBuilder.header("Host", userRequest.url.toHostHeader())
  }

  if (userRequest.header("Connection") == null) { // 长连接
    requestBuilder.header("Connection", "Keep-Alive")
  }

  // If we add an "Accept-Encoding: gzip" header field we're responsible for also decompressing
  // the transfer stream.
  var transparentGzip = false
  if (userRequest.header("Accept-Encoding") == null && userRequest.header("Range") == null) { // 没设置编码，并且不是分块传输，默认采用gzip
    transparentGzip = true
    requestBuilder.header("Accept-Encoding", "gzip")
  }
  // 价值cookie
  val cookies = cookieJar.loadForRequest(userRequest.url)
  if (cookies.isNotEmpty()) {
    requestBuilder.header("Cookie", cookieHeader(cookies))
  }
  // 默认ua
  // const val userAgent = "okhttp/${OkHttp.VERSION}"
  if (userRequest.header("User-Agent") == null) {
    requestBuilder.header("User-Agent", userAgent)
  }
  // 进行后续的传输
  val networkResponse = chain.proceed(requestBuilder.build())
  // 更新cookie
  cookieJar.receiveHeaders(userRequest.url, networkResponse.headers)
  // 重新配置response，关联request
  val responseBuilder = networkResponse.newBuilder()
      .request(userRequest)
  // gzip解码
  if (transparentGzip &&
      "gzip".equals(networkResponse.header("Content-Encoding"), ignoreCase = true) &&
      networkResponse.promisesBody()) {
    val responseBody = networkResponse.body
    if (responseBody != null) {
        // gzip 输出流包装
      val gzipSource = GzipSource(responseBody.source())
        // 移除Content-Encoding Content-Length
      val strippedHeaders = networkResponse.headers.newBuilder()
          .removeAll("Content-Encoding")
          .removeAll("Content-Length")
          .build()
        // 添加头部
      responseBuilder.headers(strippedHeaders)
        // 替换body
      val contentType = networkResponse.header("Content-Type")
      responseBuilder.body(RealResponseBody(contentType, -1L, gzipSource.buffer()))
    }
  }
  // 返回
  return responseBuilder.build()
}
```



> 该拦截器实现了
>
> - Content-Type/Content-Length/Transfer-Encoding/Host/Connection/Accept-Encoding/User-Agent等头部的校验
> - Cookie的添加和更新
> - 消息压缩（尽可能采用gzip压缩）
>
> 总的来说就是做请求的转接，将应用层的数据整合成符合http规范的报文。



###### CacheInterceptor

> 类型声明

> `Cache`用于做http缓存。

```kotlin
class CacheInterceptor(internal val cache: Cache?) : Interceptor
```





> 先从缓存中获取request
>
> 然后`CacheStrategy`会依据Request和CachedResponse判断缓存是否生效
>
> 若失效交由后续的拦截器处理，命中则直接返回。

```kotlin
override fun intercept(chain: Interceptor.Chain): Response {
  val call = chain.call()
    // 获取缓存
  val cacheCandidate = cache?.get(chain.request())

  val now = System.currentTimeMillis()
	// http 缓存策略
  val strategy = CacheStrategy.Factory(now, chain.request(), cacheCandidate).compute()
    // 网络请求
    //（如果为null，要么是缓存hit，要么是request only-if-cached但无缓存，如果不为null表明该请求可以用于之后的拦截器）
  val networkRequest = strategy.networkRequest
    // 缓存响应（如果为null表示无缓存，不为null表示有命中的缓存）
  val cacheResponse = strategy.cacheResponse
	// 记录缓存命中次数，validation次数
  cache?.trackResponse(strategy)
    // 时间监听器
  val listener = (call as? RealCall)?.eventListener ?: EventListener.NONE
  	// 关闭缓存body（缓存未命中）
  if (cacheCandidate != null && cacheResponse == null) {
    // The cache candidate wasn't applicable. Close it.
    cacheCandidate.body?.closeQuietly()
  }

  // If we're forbidden from using the network and the cache is insufficient, fail.
    // 要么是request only-if-cached但无缓存，返回异常报文
  if (networkRequest == null && cacheResponse == null) {
    return Response.Builder()
        .request(chain.request())
        .protocol(Protocol.HTTP_1_1)
        .code(HTTP_GATEWAY_TIMEOUT)
        .message("Unsatisfiable Request (only-if-cached)")
        .body(EMPTY_RESPONSE)
        .sentRequestAtMillis(-1L)
        .receivedResponseAtMillis(System.currentTimeMillis())
        .build().also {
          listener.satisfactionFailure(call, it)
        }
  }

  // If we don't need the network, we're done.
    // 缓存命中，使用cache，直接返回
  if (networkRequest == null) {
    return cacheResponse!!.newBuilder()
        .cacheResponse(stripBody(cacheResponse))
        .build().also {
          listener.cacheHit(call, it)
        }
  }

  if (cacheResponse != null) { // 通知监听器，缓存命中
    listener.cacheConditionalHit(call, cacheResponse)
  } else if (cache != null) { // 通知监听器缓存miss。
    listener.cacheMiss(call)
  }

  var networkResponse: Response? = null
  try { // 让后续拦截器进行处理
    networkResponse = chain.proceed(networkRequest)
  } finally {
    // If we're crashing on I/O or otherwise, don't leak the cache body.
    if (networkResponse == null && cacheCandidate != null) {
      cacheCandidate.body?.closeQuietly()
    }
  }

  // If we have a cache response too, then we're doing a conditional get.
    // 如果在缓存策略中有匹配的缓存。
  if (cacheResponse != null) {
      // validation结果为没变，使用缓存并更新缓存
    if (networkResponse?.code == HTTP_NOT_MODIFIED) {
      val response = cacheResponse.newBuilder()
          .headers(combine(cacheResponse.headers, networkResponse.headers))
          .sentRequestAtMillis(networkResponse.sentRequestAtMillis)
          .receivedResponseAtMillis(networkResponse.receivedResponseAtMillis)
          .cacheResponse(stripBody(cacheResponse))
          .networkResponse(stripBody(networkResponse))
          .build()

      networkResponse.body!!.close()

      // Update the cache after combining headers but before stripping the
      // Content-Encoding header (as performed by initContentStream()).
      cache!!.trackConditionalCacheHit()
      cache.update(cacheResponse, response)
      return response.also {
        listener.cacheHit(call, it)
      }
    } else { // validation发现资源发生变化，关闭流（以后也用不上了）
      cacheResponse.body?.closeQuietly()
    }
  }

  val response = networkResponse!!.newBuilder()
      .cacheResponse(stripBody(cacheResponse))
      .networkResponse(stripBody(networkResponse))
      .build()
	// 缓存非空，刷新缓存
  if (cache != null) {
      // 有body，并且可以缓存
    if (response.promisesBody() && CacheStrategy.isCacheable(response, networkRequest)) {
      // Offer this request to the cache.
        // 将内容放入缓存
      val cacheRequest = cache.put(response)
      return cacheWritingResponse(cacheRequest, response).also {
        if (cacheResponse != null) {
          // This will log a conditional cache miss only.
          listener.cacheMiss(call)
        }
      }
    }
		// 刷新缓存
    if (HttpMethod.invalidatesCache(networkRequest.method)) {
      try {
        cache.remove(networkRequest)
      } catch (_: IOException) {
        // The cache cannot be written.
      }
    }
  }

  return response
}
```



> 缓存策略

```kotlin
val strategy = CacheStrategy.Factory(now, chain.request(), cacheCandidate).compute()
```



```kotlin
fun compute(): CacheStrategy {
  val candidate = computeCandidate()

  // We're forbidden from using the network and the cache is insufficient.
    // 如果networkRequest不为空，但request中设置了only-if-cached策略
  if (candidate.networkRequest != null && request.cacheControl.onlyIfCached) {
    return CacheStrategy(null, null)
  }

  return candidate
}
```



```kotlin
private fun computeCandidate(): CacheStrategy {
  // No cached response.
    // 如果没有缓存
  if (cacheResponse == null) {
    return CacheStrategy(request, null)
  }

  // Drop the cached response if it's missing a required handshake.
  	// 如果请求式https，握手信息为null
  if (request.isHttps && cacheResponse.handshake == null) {
    return CacheStrategy(request, null)
  }

  // If this response shouldn't have been stored, it should never be used as a response source.
  // This check should be redundant as long as the persistence store is well-behaved and the
  // rules are constant.
    // 如果不可以缓存
  if (!isCacheable(cacheResponse, request)) {
    return CacheStrategy(request, null)
  }

  val requestCaching = request.cacheControl
    // 如果缓存策略式no-cache，或有缓存限定
  if (requestCaching.noCache || hasConditions(request)) {
    return CacheStrategy(request, null)
  }
	
  val responseCaching = cacheResponse.cacheControl
// 当前缓存的请求的存活时间
  val ageMillis = cacheResponseAge()
// 缓存的最大生存时间    
  var freshMillis = computeFreshnessLifetime()

  if (requestCaching.maxAgeSeconds != -1) {
    freshMillis = minOf(freshMillis, SECONDS.toMillis(requestCaching.maxAgeSeconds.toLong()))
  }

  var minFreshMillis: Long = 0
  if (requestCaching.minFreshSeconds != -1) {
    minFreshMillis = SECONDS.toMillis(requestCaching.minFreshSeconds.toLong())
  }

  var maxStaleMillis: Long = 0
  if (!responseCaching.mustRevalidate && requestCaching.maxStaleSeconds != -1) {
    maxStaleMillis = SECONDS.toMillis(requestCaching.maxStaleSeconds.toLong())
  }
// 没有设置no-cache，并且 age + minFresh < freshMills + maxStale (及缓存没有完全失效)
  if (!responseCaching.noCache && ageMillis + minFreshMillis < freshMillis + maxStaleMillis) {
    val builder = cacheResponse.newBuilder()
    if (ageMillis + minFreshMillis >= freshMillis) { // 缓存已经超过了max-age,但是还在maxStale范围内
      builder.addHeader("Warning", "110 HttpURLConnection \"Response is stale\"")
    }
    val oneDayMillis = 24 * 60 * 60 * 1000L
    if (ageMillis > oneDayMillis && isFreshnessLifetimeHeuristic()) { // 无限期缓存，并且缓存已经超过一天了
      builder.addHeader("Warning", "113 HttpURLConnection \"Heuristic expiration\"")
    }
    return CacheStrategy(null, builder.build())
  }

  // Find a condition to add to the request. If the condition is satisfied, the response body
  // will not be transmitted.
  val conditionName: String
  val conditionValue: String?
  when { // 如果有条件判断
    etag != null -> {
      conditionName = "If-None-Match"
      conditionValue = etag
    }

    lastModified != null -> {
      conditionName = "If-Modified-Since"
      conditionValue = lastModifiedString
    }

    servedDate != null -> {
      conditionName = "If-Modified-Since"
      conditionValue = servedDateString
    }
    // 没有条件判断，不考虑缓存
    else -> return CacheStrategy(request, null) // No condition! Make a regular request.
  }

    // 加入相关的条件首部，进行validation
  val conditionalRequestHeaders = request.headers.newBuilder()
  conditionalRequestHeaders.addLenient(conditionName, conditionValue!!)

  val conditionalRequest = request.newBuilder()
      .headers(conditionalRequestHeaders.build())
      .build()
  return CacheStrategy(conditionalRequest, cacheResponse)
}
```



> 简单来说就是http缓存的封装。
>
> 严格遵循RFC



###### ConnectInterceptor





###### CallServerInterceptor





##### 普通拦截器







##### 网络拦截器







#### Cache



#### Authenticator





#### timeout





#### ConnectionPool







#### ConnectSpec





#### CookieJar





#### Dispatcher







#### Dns



#### EventListener



#### redirect





#### HostnameVerifier



#### proxy





#### socket







#### 其他







## Websocket







