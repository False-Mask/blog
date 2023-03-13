---

title: Android AIDL
date: 2022-04-25 18:43:44
tags:
- android
- 操作系统
categories:
- android

---



# Aidl

aidl的全称叫做android interface define language

即**安卓接口定义语言**。

为什么会有他的存在？

因为跨进程通信有些冗余。



## c/s app通信-非aidl写法

> 通信逻辑：即client端向server发送一条字符串信息，server返回一条字符串信息。





client端

![image-20220424162846484](http://114.116.23.72/images/2022/04/24/image-20220424162846484.png)



client界面

![image-20220424163027033](http://114.116.23.72/images/2022/04/24/image-20220424163027033.png)

代码

```kotlin
class ClientActivity : AppCompatActivity() {

    private var remote: IBinder? = null

    private val binding by lazy {
        ActivityClientBinding.inflate(layoutInflater)
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(p0: ComponentName?, p1: IBinder?) {
            Log.e("TAG", "onServiceConnected: ")
            remote = p1
        }

        override fun onServiceDisconnected(p0: ComponentName?) {
            remote = null
        }

    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(binding.root)

        binding.btnBind.setOnClickListener { bind() }
        binding.btnSend.setOnClickListener { send() }


    }

    private fun send() {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()

        val str = binding.etSend.text.toString()
        data.writeString(str)


        remote?.transact(200, data, reply, 0)

        val result = reply.readString()

        binding.tvContent.text = result

        data.recycle()
        reply.recycle()
    }

    private fun bind() {
        Intent().apply {
            component = ComponentName("org.example.server", "org.example.server.RemoteService")
        }.run {
            bindService(this, connection, BIND_AUTO_CREATE)
        }
    }
}
```



server端

![image-20220424163355458](http://114.116.23.72/images/2022/04/24/image-20220424163355458.png)

代码

```kotlin
class RemoteService : Service() {

    private val requestCode = 200

    override fun onBind(intent: Intent): IBinder = IBinder()

    inner class IBinder : Binder() {

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {


            if (code == requestCode){
                val str = data.readString()
                reply?.apply {
                    writeString("我是服务端我收到了消息$str")
                }
                return true
            }

            return super.onTransact(code, data, reply, flags)

        }

    }

}
```







可以发现其实通信就是与server绑定，server在绑定以后会返回一个binder。然后依靠binder进行一个跨进程的通信。

不过内部通信传入数据是非常痛苦的。因为要手动去写入parcel中。



不过最后还是能达到对应的效果。

![image-20220424163829968](http://114.116.23.72/images/2022/04/24/image-20220424163829968.png)



进行简单的通信就要写这么多冗余的代码。

很是不好。如果交互的数据复杂一点后，那可能问题就大了。而且重复的代码谁都不想写啊。







## c/s Aidl

> aidl很重要一点就是简洁，如果他不简洁也不会用它的。hh。

光说是么用的你得给我代码才行啊



- interface

![image-20220424204209473](http://114.116.23.72/images/2022/04/24/image-20220424204209473.png)

- client

```kotlin
class MainActivity : AppCompatActivity() {

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(p0: ComponentName?, p1: IBinder?) {
            Log.e("TAG", "onServiceConnected: " )
            ask = Ask.Stub.asInterface(p1)
        }

        override fun onServiceDisconnected(p0: ComponentName?) {
            ask = null
        }
    }

    private var ask: Ask? = null

    private val binding by lazy { ActivityMainBinding.inflate(layoutInflater) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(binding.root)

        binding.btnBind.setOnClickListener {
            bind()
        }

        binding.btnSend.setOnClickListener {
            Log.e("TAG", ask.toString() )
            binding.tvShow.text = ask?.ask(binding.etSend.text.toString())
        }

    }

    private fun bind() {
        Intent().apply {
            component = ComponentName("org.example.aidl", "org.example.aidl.RemoteService")
        }.run {
            bindService(this, connection, BIND_AUTO_CREATE)
        }
    }
}
```



- server

```kotlin
class RemoteService : Service() {

    inner class IBinder : Ask.Stub() {

        override fun ask(content: String?): String {
            return "我是服务端我收到了客户端信息${content}"
        }

    }

    override fun onBind(p0: Intent?): android.os.IBinder = IBinder()

}
```



可以发现，我们好像是没和binder打交道的。因为打交道的那一部分已经被实现了。是aidl帮我们实现了。我们只需要写具体的交互逻辑即可。很是舒服。



## aidl源码分析

![image-20220424210524286](http://114.116.23.72/images/2022/04/24/image-20220424210524286.png)

查看一下生成的代码就发现猫腻了。aidl是一种类似于java的语法定义语言，在打包的时候会对它进行一次编译生成一些模板代码。

废话不多说，还是看看代码。



aidl

![image-20220424210959362](http://114.116.23.72/images/2022/04/24/image-20220424210959362.png)

generated code

一个同名的接口，代码挺长的，130多行。

![image-20220424211122251](http://114.116.23.72/images/2022/04/24/image-20220424211122251.png)

有两个实现类

- Default

  好像没啥的。可能是为了兼容吧

  ![image-20220424211313197](http://114.116.23.72/images/2022/04/24/image-20220424211313197.png)

- Stub

  插桩代码有些复杂

  ![image-20220424211450382](http://114.116.23.72/images/2022/04/24/image-20220424211450382.png)

  public的方法不多

  - asInterface

    ![image-20220424212535209](http://114.116.23.72/images/2022/04/24/image-20220424212535209.png)

    obj为空就返回空，然后去bind里面去搜索，如果有实现对应接口的类就给他强转出来，如果没有那就返回一个代理类。

    如果服务端和客户端处于两个不同的进程那么是一定拿不到的，所以会依靠这个代理类进行通信。

    由于存有内核隔离，所以其实两个进程是拿不到对应的接口的，但是我们在实际使用中就好像是跨进程拿到了接口一样。很奇怪吧。其实是内部做了处理的。你拿不到接口但是可以对接口做校验的。对接口名称做校验，这样就可以达到不同进程调用接口的效果。

    ![image-20220424220414121](http://114.116.23.72/images/2022/04/24/image-20220424220414121.png)

    ![image-20220424220900726](http://114.116.23.72/images/2022/04/24/image-20220424220900726.png)

    这样跨进程调用接口方法就完成了。

    不过还有部分的流程还没完成。我们继续。

    ![image-20220424221115092](http://114.116.23.72/images/2022/04/24/image-20220424221115092.png)

    前面分析了transact调用服务端。不过后面的收尾工作还没有分析，收尾比较简单，依据transact的返回值判断，如果transact出问题了（返回了false）而且还能拿到默认实现，那么就调用默认实现。如果没出问题就读取结果，回收parcel然后返回值收尾。

  - setDefaultImpl

    为接口设置一个默认实现

    ![image-20220425180155539](http://114.116.23.72/images/2022/04/25/image-20220425180155539.png)
  
  - getDefaultImpl
  
    获取接口的默认实现
  
    ![image-20220425180241567](http://114.116.23.72/images/2022/04/25/image-20220425180241567.png)
  
  

至此aidl已经分析完全。



## 总结

aidl中有几个比较重要的类。

- 接口
- Stub
- Proxy

>  接口就不必多说了，他是我们在进行跨进程通信时候，客户端和服务端通信的抽象。

> Stub是一个插桩类，它为我们进行通信的时候提供便利。client可以通过它来简化与服务端的通信，server也是通过使用它来简化与客户端的多余的通信成本。

> Proxy是一个代理类，主要的原因是：不同的进程间存在有一个内核隔离，所以内存是不共享的，这样就会导致跨进程是无法直接调用接口的。但Proxy实现了跨进程调用接口这一骚操作。原理也很简单，就是：服务端和客户端都对接口类型进行一个判断，虽然接口不共享，但是我们可以通过传递parcel的形式来验证他们是否是同一个接口，如果是那么当客户端进程通过接口调用某个方法的时候，会通过Proxy来代理这个接口的方法，通过将调用的接口转化为parcel数据发送给服务端，调用服务端的onTransact方法，然后服务端在对调用的接口请求进行验证，然后和服务端实现的是吻合的，那么就会调用服务端的接口，这样就达到了跨进程调用接口的效果。

所以跨进程通信的流程如下，客户端持有的接口会被代理类代理，接口中的每个方法的调用都会想服务端发送一个token进行验证，服务端在验证接口无误以后才会调用对应的方法，最后返回给客户端。（通信底层还是使用的binder）。

也就是说aidl只是帮我们自动生成的了一些冗余的用于通信的代码，再使用aidl以后，我们只需要做具体的逻辑，跨进程的通信已经由aidl帮我们封装好了(而aidl底层也是封装的binder)。
