---
title: Retrofit分析
date:2022-02-17 19:15:05
tags:
- android
categories:
- android
- 网络
---



# Retrofit



## 基本使用

```kotlin
interface Api {
    @GET("friend/json")
    fun test():Call<Bean>

}
object ApiService {
    private val retrofit: Retrofit = Retrofit.Builder()
        .addConverterFactory(GsonConverterFactory.create())
        .addConverterFactory(GsonConverterFactory.create())
        .baseUrl("https://www.wanandroid.com")
        .client(OkHttpClient())
        .validateEagerly(false)
        .build()

    val api = retrofit.create<Api>()
}
fun main() {
    println(ApiService.api.test().execute().body())
}
```

retrofit的基本使用很简单，

可以按照以下步骤来

- 创建网络请求的接口 见Api interface

- 创建Retrofit实例 见ApiService.retrofit

- 获取对应的接口，见retrofit.create

## Retrofit的优势

- 扩展性强
  
  > 体现再哪里呢？主要的体现就是我们在创建Retrofit的时候我们可以对必要的配置进行自定义。它内部没有完全写死，比如client使用OkhttpClient(他基本上是把所有的网络配置都暴露了出来)，又比如Json的解析器我们可以使用任何是实现了Converter.Factory的类。

- 简便
  
  > 简便与否只有开发者知道，在使用其他的框架内之前我们得怎么进行网络请求？
  > 
  > 先传入url然后进行网络配置，然后连接。然后定义一个回调，开一个线程进行请求，然后切回主线程。
  > 
  > 上述的操作由于比较复杂，我们通常情况下会将将一些列进行封装。然而呢，这部封装没事，一封装满篇都是bug。
  > 
  > 而Retrofit呢开箱即用，只需要定义一个带有我们请求配置注解的接口。上述的一切繁琐操作就被retrofit全全负责。
  > 
  > **有的时候你或许会怀疑：这简单的有些过头了，是否会出现问题？**

## Retrofit是什么

我初学Retrofit的时候也想过这个问题，Retrofit是什么呢？祂们都使用的是Retrofit。就我使用的HttpUrlConnection。过了一段时间了解学了一个适中的框架Okhttp。所以Retrofit是替代Okhttp的？因为我们最终都没使用Okhttp嘛是吧？真实是这样嘛？

不是的！！！

> 有的时候我们看似没使用一个框架，其实不是真的没有使用。说不定底层使用了呢？

> Retrofit恰恰就是这种，Retrofit没有引入新的技术，他做了一件事情——那就是封装，他把与网络请求相关的所有库的封装到了一起，而且还封装的很简洁，扩展性还挺高的。
> 
> 所以实际是Retrofit就是一个缝合怪，他是很多网络请求相关库的一个封装。
> 
> 由于他用起来很爽所以入坑以后就回不来了。

## Retrofit实例化

通常情况下我们是采用的build构建一个Retrofit

如下

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220217195534.png)

```kotlin
private val retrofit: Retrofit = Retrofit.Builder()
        .addConverterFactory(GsonConverterFactory.create())
        .addConverterFactory(GsonConverterFactory.create())
        .baseUrl("https://www.wanandroid.com")
        .client(OkHttpClient())
        .validateEagerly(false)
        .build()
```

构建一个retrofit采用的是builder模式，这种模式呢比较简介，不过对于kt而言直接使用可选参数或许更好。

Build内部的方法也就是为了修改retrofit的一些成员变量

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220217200538.png" title="" alt="" data-align="center">

build的时候直接new了一个Retrofit回去。

## 获取接口

```kotlin
public <T> T create(final Class<T> service) {
    validateServiceInterface(service);
    return (T)
        Proxy.newProxyInstance(
            service.getClassLoader(),
            new Class<?>[] {service},
            new InvocationHandler() {
              private final Platform platform = Platform.get();
              private final Object[] emptyArgs = new Object[0];

              @Override
              public @Nullable Object invoke(Object proxy, Method method, @Nullable Object[] args)
                  throws Throwable {
                // If the method is a method from Object then defer to normal invocation.
                if (method.getDeclaringClass() == Object.class) {
                  return method.invoke(this, args);
                }
                args = args != null ? args : emptyArgs;
                return platform.isDefaultMethod(method)
                    ? platform.invokeDefaultMethod(method, service, proxy, args)
                    : loadServiceMethod(method).invoke(args);
              }
            });
  }
```

这个create好像有点意思啊。

好像是用了一个很奇怪的东西。动态代理。下面就先讲讲动态代理是什么。

## JDK代理

> Time: 2022-2-18

### 静态代理

```kotlin
class StaticProxy(private val proxy: NetWork) : NetWork {

    override fun sendNetWorkMsg() {
        println("我是代理人--我现在要代理完成NetWork代理")
        proxy.sendNetWorkMsg()
        println("我是代理人--我已经完成了NetWork的代理")
    }
}

interface NetWork {
    fun sendNetWorkMsg()
}

class NetWorkImp1 : NetWork {
    override fun sendNetWorkMsg() {
        println("send Message")
    }
}

fun main() {
    val proxy = StaticProxy(NetWorkImp1())
    proxy.sendNetWorkMsg()
}
```

可以发现静态代理其实并不难。就是在一个对象的基础上再组合一个同类的对象。

简单来说就是我需要完成发送网络请求的目的。但是我并不知直接去找对应的实现类。我找一个代理类，我要通过这个代理类帮我完成对应的任务。代理类又会把对应的任务委托给真正的实现类。这种关系类似于买卖房的中介的关系。

### 动态代理

动态代理?怎么个动态法？动态的生成实现类？是吗？不是吗？还真是。

> 静态代理的是静态的是因为这个关系在编译器就已经实现了，虽然我们利用了多态，编译器比较傻不知道，但是值得肯定的是编译的时候他的委托关系就已经确定了。

> 动态代理呢？动态代理的实现类是动态生成的。这个动态生成表示的是在执行某一行代码的时候才有这种委托关系。没执行就没有关系。所以呢静态代理 受代理对象和代理的实现类的耦合性比较弱但是还是有耦合。动态代理受代理的对象和代理实现类没有耦合。因为运行时候才有联系，真正实现了热可插拔。

这是动态代理比较简单的实现类

```
java.lang.reflect.Proxy
```

所以呢？java.lang是语言包，也就是说动态代理Java在语言的层面上就支持。所以会有很多的动态代理框架cglib，springboot。

不过呢我们现在使用的动态代理没有那么高级，所以没必要使用这么重量级的框架。

#### 使用

```kotlin
fun main() {
    val imp = NetWorkImp()
    val proxy = NetWorkProxy(imp)
    val prox = Proxy.newProxyInstance(NetWorkImp::class.java.classLoader, NetWorkImp::class.java.interfaces, proxy) as NetWork
    prox.sendNetWorkMsg("11")
}

class NetWorkProxy(private val target: Any) : InvocationHandler {
    override fun invoke(proxy: Any?, method: Method?, args: Array<out Any>?): Any? {
        println("before Proxy")
        val result = method!!.invoke(target, args!![0])
        println("after Proxy")
        return result
    }
}

class NetWorkImp : NetWork {

    override fun sendNetWorkMsg(msg: String) {
        println("send:${msg}")
    }

}


interface NetWork {
    fun sendNetWorkMsg(msg: String)
}
```

稍微分析一下，在结构上动态代理和静态代理并没有变化。

都有一个抽象接口，都有一个代理实现类，都有一个代理类。

不同点就是多了一个步骤，获取接口的方式是通过Proxy.newProxyInstance的方式

#### 流程分析

```kotlin
public static Object newProxyInstance(ClassLoader loader,
                                          Class<?>[] interfaces,
                                          InvocationHandler h) {
        Objects.requireNonNull(h);

        final Class<?> caller = System.getSecurityManager() == null
                                    ? null
                                    : Reflection.getCallerClass();

        /*
         * Look up or generate the designated proxy class and its constructor.
         */
        Constructor<?> cons = getProxyConstructor(caller, loader, interfaces);

        return newProxyInstance(caller, cons, h);
    }
```

##### getProxyConstructor

> Returns the Constructor object of a proxy class that takes a single argument of type InvocationHandler, given a class loader and an array of interfaces. The returned constructor will have the accessible flag already set.
> Params:
> caller – passed from a public-facing @CallerSensitive method if SecurityManager is set or null if there's no SecurityManager
> loader – the class loader to define the proxy class
> interfaces – the list of interfaces for the proxy class to implement
> Returns:
> a Constructor of the proxy class taking single InvocationHandler parameter

注释给出的意思是返回代理类的实例。这个代理类是谁？

```java
 private static Constructor<?> getProxyConstructor(Class<?> caller,
                                                      ClassLoader loader,
                                                      Class<?>... interfaces)
    {
        // optimization for single interface
        if (interfaces.length == 1) {
            Class<?> intf = interfaces[0];
            if (caller != null) {
                checkProxyAccess(caller, loader, intf);
            }
            return proxyCache.sub(intf).computeIfAbsent(
                loader,
                (ld, clv) -> new ProxyBuilder(ld, clv.key()).build()
            );
        } else {
            // interfaces cloned
            final Class<?>[] intfsArray = interfaces.clone();
            if (caller != null) {
                checkProxyAccess(caller, loader, intfsArray);
            }
            final List<Class<?>> intfs = Arrays.asList(intfsArray);
            return proxyCache.sub(intfs).computeIfAbsent(
                loader,
                (ld, clv) -> new ProxyBuilder(ld, clv.key()).build()
            );
        }
    }
```

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218095103.png)

这就是对应的生成的代理类。

现在开始具体的流程分析

进入getConstructor以后他会进行判断。接口到底有几个

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218095251.png)

这里显然只有一个，所以会执行以下代码

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218095410.png)

实际重要的也就是一行

```java
return proxyCache.sub(intf).computeIfAbsent(
                loader,
                (ld, clv) -> new ProxyBuilder(ld, clv.key()).build()
            );
```

这一行首先new了一个Sub

```java
public <K> Sub<K> sub(K key) {
        return new Sub<>(key);
    }
```

然后调用了computeIfAbsent

别的不说这一行代码执行完一后Constructer的实例就获取到了，所以Constructor就是在这里获取的。

代码很多但是有用的好像比较少

```java
public V computeIfAbsent(ClassLoader cl,
                             BiFunction<
                                 ? super ClassLoader,
                                 ? super CLV,
                                 ? extends V
                                 > mappingFunction) throws IllegalStateException {
        ConcurrentHashMap<CLV, Object> map = map(cl);
        @SuppressWarnings("unchecked")
        CLV clv = (CLV) this;
        Memoizer<CLV, V> mv = null;
        while (true) {
            Object val = (mv == null) ? map.get(clv) : map.putIfAbsent(clv, mv);
            if (val == null) {
                if (mv == null) {
                    // create Memoizer lazily when 1st needed and restart loop
                    mv = new Memoizer<>(cl, clv, mappingFunction);
                    continue;
                }
                // mv != null, therefore sv == null was a result of successful
                // putIfAbsent
                try {
                    // trigger Memoizer to compute the value
                    V v = mv.get();
                    // attempt to replace our Memoizer with the value
                    map.replace(clv, mv, v);
                    // return computed value
                    return v;
                } catch (Throwable t) {
                    // our Memoizer has thrown, attempt to remove it
                    map.remove(clv, mv);
                    // propagate exception because it's from our Memoizer
                    throw t;
                }
            } else {
                try {
                    return extractValue(val);
                } catch (Memoizer.RecursiveInvocationException e) {
                    // propagate recursive attempts to calculate the same
                    // value as being calculated at the moment
                    throw e;
                } catch (Throwable t) {
                    // don't propagate exceptions thrown from foreign Memoizer -
                    // pretend that there was no entry and retry
                    // (foreign computeIfAbsent invocation will try to remove it anyway)
                }
            }
            // TODO:
            // Thread.onSpinLoop(); // when available
        }
    }
```

经过调试发现获取对应的构造函数的核心代码是

```
V v = mv.get();
```

调用以后就跑到了这里

```java
public V get() throws RecursiveInvocationException {
            V v = this.v;
            if (v != null) return v;
            Throwable t = this.t;
            if (t == null) {
                synchronized (this) {
                    if ((v = this.v) == null && (t = this.t) == null) {
                        if (inCall) {
                            throw new RecursiveInvocationException();
                        }
                        inCall = true;
                        try {
                            this.v = v = Objects.requireNonNull(
                                mappingFunction.apply(cl, clv));
                        } catch (Throwable x) {
                            this.t = t = x;
                        } finally {
                            inCall = false;
                        }
                    }
                }
            }
            if (v != null) return v;
            if (t instanceof Error) {
                throw (Error) t;
            } else if (t instanceof RuntimeException) {
                throw (RuntimeException) t;
            } else {
                throw new UndeclaredThrowableException(t);
            }
        }
```

这里看似都是不相干的代码，但是别忘了其中的非常重要的一行。

```java
this.v = v = Objects.requireNonNull( 
mappingFunction.apply(cl, clv));
```

这里调用了mapFunction

也就是这里

```java
 (ld, clv) -> new ProxyBuilder(ld, clv.key()).build()
```

点看以后豁然开朗

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218100552.png)

new Build的时候初始化了一些配置，这里不提。

调用build以后就完了class文件的生成。

build先后电泳了

- defineProxyClass

- getConstructor

核心代码呼之欲出必然是defineProxyClass

defineProxyClass的前半段也就定义了动态代理的类名，包名，修饰符的信息，还没完成对于类的字节码文件的生成。

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218101109.png)

后半页的核心代码露头了

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218101604.png)

我们来分析以下这个Generator

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218104155.png)

ClassWriter嗯有点意思一看包名

jdk.internal.org.objectweb.asm

asm。具体就不分析了。

所以呢代码的生成底层是依靠的ASM字节码插桩

```java
static byte[] generateProxyClass(ClassLoader loader,
                                     final String name,
                                     List<Class<?>> interfaces,
                                     int accessFlags) {
        ProxyGenerator gen = new ProxyGenerator(loader, name, interfaces, accessFlags);
        final byte[] classFile = gen.generateClassFile();

        if (saveGeneratedFiles) {
            java.security.AccessController.doPrivileged(
                    new java.security.PrivilegedAction<Void>() {
                        public Void run() {
                            try {
                                int i = name.lastIndexOf('.');
                                Path path;
                                if (i > 0) {
                                    Path dir = Path.of(dotToSlash(name.substring(0, i)));
                                    Files.createDirectories(dir);
                                    path = dir.resolve(name.substring(i + 1) + ".class");
                                } else {
                                    path = Path.of(name + ".class");
                                }
                                Files.write(path, classFile);
                                return null;
                            } catch (IOException e) {
                                throw new InternalError(
                                        "I/O exception saving generated file: " + e);
                            }
                        }
                    });
        }

        return classFile;
    }
```

通过new一个Generator然后调用Generator的generateClass实现了字节码的插桩。

我们可以很清楚的看到generateClass的返回值是一串byte数组

```java
final byte[] classFile = gen.generateClassFile();
```

这个byte数组是一个class文件的二进制形式，在执行完生成操作以后他会直接通过反射去获取这个byte数组表示的class文件的构造函数。然后返回。

```java
 byte[] proxyClassFile = ProxyGenerator.generateProxyClass(loader, proxyName, interfaces, accessFlags);
            try {
                Class<?> pc = JLA.defineClass(loader, proxyName, proxyClassFile,
                                              null, "__dynamic_proxy__");
                reverseProxyCache.sub(pc).putIfAbsent(loader, Boolean.TRUE);
                return pc;
            } 
```

光是byte数组我们不好分析他的原理，所有有办法给他弄出.class文件？然后我们再反编译去看他的java代码？

- way1 
  
  通过把这个byte数组的所有内容给打印出来然后自己用相应的软件去解码。
  
  这方法行吗？太行了只不过呢byte数组有点大而且操作起来有点点复杂。

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218104638.png)

- way2
  
  通过JDK里面提供的方法，就在generate bytes的下面一点点就有一个if判断这个if判断如果满足他会自动帮我们把这个bytes给保存成文件的形式

我们可以看到下面冗长的if判断就是做的这个事情

```java
if (saveGeneratedFiles)
private static final boolean saveGeneratedFiles =
            java.security.AccessController.doPrivileged(
                    new GetBooleanAction(
                            "jdk.proxy.ProxyGenerator.saveGeneratedFiles"));
```

这个saveGeneratedFiles可以通过设置系统参数来确定。（没设置默认就是false）

```java
    System.getProperties().setProperty("jdk.proxy.ProxyGenerator.saveGeneratedFiles","true");
```

如果在我们的代码里面加上这一行,再重新run代码的时候class就会保存为一个文件

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218105234.png)

这就是动态生成代理类的具体内容，代码比较短。

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218105318.png)

好了以上就是动态代理动态生成代理类字节码并获取其构造函数的全过程。

(这个class文件后续会分析的)

##### newProxyInstance

前面我们分析了

```java
Constructor<?> cons = getProxyConstructor(caller, loader, interfaces);
```

形成字节码的全部流程。我们甚至还看到了他生成的字节码的信息。

继续走流程看看这段又干了啥

```java
private static Object newProxyInstance(Class<?> caller, // null if no SecurityManager
                                           Constructor<?> cons,
                                           InvocationHandler h) {
        /*
         * Invoke its constructor with the designated invocation handler.
         */
        try {
            if (caller != null) {
                checkNewProxyPermission(caller, cons.getDeclaringClass());
            }

            return cons.newInstance(new Object[]{h});
        } catch (IllegalAccessException | InstantiationException e) {
            throw new InternalError(e.toString(), e);
        } catch (InvocationTargetException e) {
            Throwable t = e.getCause();
            if (t instanceof RuntimeException) {
                throw (RuntimeException) t;
            } else {
                throw new InternalError(t.toString(), t);
            }
        }
    }
try {
            if (caller != null) {
                checkNewProxyPermission(caller, cons.getDeclaringClass());
            }

            return cons.newInstance(new Object[]{h});
        }
```

if判断权限无关紧要，所以核心就一行反射。

反射了一个带有InvocationHandler的构造

new了一个Proxy实例。

也就是

```java
return new $Proxy0(h)
```

这个h是我们在调用Proxy.newProxyInstance的时候传入的

也就是这个

```kotlin
class NetWorkProxy(private val target: Any) : InvocationHandler {
    override fun invoke(proxy: Any?, method: Method?, args: Array<out Any>?): Any? {
        println("before Proxy")
        println(args!!.javaClass)
        val result = method!!.invoke(target, args[0])
        println("after Proxy")
        return result
    }
}
```

就这样我们就拿到了动态代理对象。

##### $Proxy0分析

###### static代码块

```java
static {
        try {
            m0 = Class.forName("java.lang.Object").getMethod("hashCode");
            m1 = Class.forName("java.lang.Object").getMethod("equals", Class.forName("java.lang.Object"));
            m2 = Class.forName("java.lang.Object").getMethod("toString");
            m3 = Class.forName("proxy.dynamic.NetWork").getMethod("sendNetWorkMsg", Class.forName("java.lang.String"));
        } catch (NoSuchMethodException var2) {
            throw new NoSuchMethodError(var2.getMessage());
        } catch (ClassNotFoundException var3) {
            throw new NoClassDefFoundError(var3.getMessage());
        }
    }
```

通过反射去获取方法。

m0，m1,m2分别是hashCode，equals，toString

m3是我们定义的方法。（如果我们还有其他方法，他还会自动取生成对应的方法）

###### hashCode/equals/toString/sendNetWorkMsg

子所以把这些拿到一块来主要是因为他们实现原理都是一样的。

调用了InvocationHandler对象的invoke方法，而这个InvocationHandler会在构造函数内进行初始化，而Proxy0会在反射的时候调用它的构造函数。所以综上来看InvocationHandler会在Proxy.newProxyInstance的时候传入。    

```java
public final int hashCode() {
        try {
            return (Integer)super.h.invoke(this, m0, (Object[])null);
        } catch (RuntimeException | Error var2) {
            throw var2;
        } catch (Throwable var3) {
            throw new UndeclaredThrowableException(var3);
        }
    }

    public final boolean equals(Object var1) {
        try {
            return (Boolean)super.h.invoke(this, m1, new Object[]{var1});
        } catch (RuntimeException | Error var2) {
            throw var2;
        } catch (Throwable var3) {
            throw new UndeclaredThrowableException(var3);
        }
    }

    public final String toString() {
        try {
            return (String)super.h.invoke(this, m2, (Object[])null);
        } catch (RuntimeException | Error var2) {
            throw var2;
        } catch (Throwable var3) {
            throw new UndeclaredThrowableException(var3);
        }
    }

    public final void sendNetWorkMsg(String var1) {
        try {
            super.h.invoke(this, m3, new Object[]{var1});
        } catch (RuntimeException | Error var2) {
            throw var2;
        } catch (Throwable var3) {
            throw new UndeclaredThrowableException(var3);
        }
    }
```

所以上述的所以方法都是通过调用这个方法实现的。

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218134439.png)

##### 小结

- 代理接口，就是一些我们需要委托的内容。例如比如上述的NetWork接口就是一个代理接口

- InvocationHandler所作的确实和它的名字是类似的，Proxy的大部分方法都会转交给他。其中包含hashCode，equal，toString，自己定义的代理接口的所有方法。

- Proxy实现类，他是委托接口的具体实现，InvocationHandler会持有一个它的引用。

- 动态生成的Proxy类，他直接和受代理者打交道的代理类，他持有了一个InvocationHandle的引用

动态代理类关系图。

为什么说动态代理没有耦合，这是有原因的。

受代理对象想持有ProxyInterface的实现类，让实现类帮他完成一定的内容。

编译时期由于没有生成字节码所以没有耦合，类图有标明。

运行时候生成了$$Proxy对象返回才有了比较弱的耦合关系。

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/动态代理.drawio.png)

## Retrofit继续分析

> 前面分析了Retrofit的创建流程，但是网络请求接口的创建还没有分析完成。
> 
> 由于动态代理卡住了。hh
> 
> 接下来我们分析一下Retrofit的动态代理是如何实现的。

### Retrofit动态代理

```java
public <T> T create(final Class<T> service) {
    validateServiceInterface(service);
    return (T)
        Proxy.newProxyInstance(
            service.getClassLoader(),
            new Class<?>[] {service},
            new InvocationHandler() {
              private final Platform platform = Platform.get();
              private final Object[] emptyArgs = new Object[0];

              @Override
              public @Nullable Object invoke(Object proxy, Method method, @Nullable Object[] args)
                  throws Throwable {
                // If the method is a method from Object then defer to normal invocation.
                if (method.getDeclaringClass() == Object.class) {
                  return method.invoke(this, args);
                }
                args = args != null ? args : emptyArgs;
                return platform.isDefaultMethod(method)
                    ? platform.invokeDefaultMethod(method, service, proxy, args)
                    : loadServiceMethod(method).invoke(args);
              }
            });
  }
```

很熟悉的代码这不是Jdk的动态代理吗。

- 传入了网络请求接口的类加载器

- 传入了网络请求接口的Class对象

- 传入了一个InvocationHandler的匿名实现类

```java
   Proxy.newProxyInstance(
            service.getClassLoader(),
            new Class<?>[] {service},
            new InvocationHandler()....
   )
```

接下来重心到了InvocationHandler

#### InvocationHandler

```java
new InvocationHandler() {
              private final Platform platform = Platform.get();
              private final Object[] emptyArgs = new Object[0];

              @Override
              public @Nullable Object invoke(Object proxy, Method method, @Nullable Object[] args)
                  throws Throwable {
                // If the method is a method from Object then defer to normal invocation.
                if (method.getDeclaringClass() == Object.class) {
                  return method.invoke(this, args);
                }
                args = args != null ? args : emptyArgs;
                return platform.isDefaultMethod(method)
                    ? platform.invokeDefaultMethod(method, service, proxy, args)
                    : loadServiceMethod(method).invoke(args);
              }
            }
```

有两个成员变量还都是final的。

##### 成员变量

###### PlatForm

```java
private static final Platform PLATFORM = findPlatform();

  static Platform get() {
    return PLATFORM;
  }

  private static Platform findPlatform() {
    return "Dalvik".equals(System.getProperty("java.vm.name"))
        ? new Android() //
        : new Platform(true);
  } }
```

所以这个PlatForm也就是一个类，一个反映平台的类型。

Retrofit对Dalvik平台有特殊的处理(也就是Android)

由于我们的是PC上跑来测试的所以平台应该创建PlatForm

Platform内容如下

![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218143456.png)

###### emptyArgs

这个其实没什么奇怪的就是一个empty的参数。长度为0的object数组。

之所以有这个的原因是这样的，方法有形式参数，当一个方法没有新参的时候，args传入会是null,为了防止空指针传入一个长度为0数组。

```java
private final Object[] emptyArgs = new Object[0];
```

如下

```java
 args = args != null ? args : emptyArgs;
```

##### 方法体分析

```java
if (method.getDeclaringClass() == Object.class) {
                  return method.invoke(this, args);
                }
                args = args != null ? args : emptyArgs;
                return platform.isDefaultMethod(method)
                    ? platform.invokeDefaultMethod(method, service, proxy, args)
                    : loadServiceMethod(method).invoke(args);
```

方法体可谓是非常简单。

- 由于java是纯面向对象的，而且java没有函数的概念，Java的方法是必须依托于类而存在的（函数可以独立存在），获取了方法关联的类，若是Object说明是class如果不是说明是一个interface或者abstract class。明显这里不会进入if分支。

- 然后确保args非空，如果是空的就赋值为emptyArgs

- 然后开始调用platform开始进行网络请求
  
  > 这里先判断一下该方法是不是interface的default方法
  > 
  > ```java
  > boolean isDefaultMethod(Method method) {
  >     return hasJava8Types && method.isDefault();
  >  }
  > ```
  > 
  > 测试用例显然会返回false
  > 
  > 然后就就会调用如下方法
  > 
  > ```java
  > ServiceMethod<?> loadServiceMethod(Method method) {
  >     ServiceMethod<?> result = serviceMethodCache.get(method);
  >     if (result != null) return result;
  > 
  >     synchronized (serviceMethodCache) {
  >       result = serviceMethodCache.get(method);
  >       if (result == null) {
  >         result = ServiceMethod.parseAnnotations(this, method);
  >         serviceMethodCache.put(method, result);
  >       }
  >     }
  >     return result;
  >   }
  > ```
  
  > 先去缓存里面拿对应的方法的解析结果。（显然是拿不到的因为是第一次调用，怎么会有缓存）
  > 
  > 然后加了一个同步锁再取拿缓存看看是否有（因为网络请求一般是多线程操作，可能前一步没拿到后一步就有一个线程放入进入了。）
  > 
  > 然后就调用静态方法取解析注解。
  > 
  > ```java
  > static <T> ServiceMethod<T> parseAnnotations(Retrofit retrofit, Method method) {
  >     RequestFactory requestFactory = RequestFactory.parseAnnotations(retrofit, method);
  > 
  >     Type returnType = method.getGenericReturnType();
  >     if (Utils.hasUnresolvableType(returnType)) {
  >       throw methodError(
  >           method,
  >           "Method return type must not include a type variable or wildcard: %s",
  >           returnType);
  >     }
  >     if (returnType == void.class) {
  >       throw methodError(method, "Service methods cannot return void.");
  >     }
  > 
  >     return HttpServiceMethod.parseAnnotations(retrofit, method, requestFactory);
  >   }
  > ```
  > 
  > 先parse了一下注解
  > 
  > 然后确保了returnType的合法性(不能是void)
  > 
  > 然后进一步进行解析
  
  > ![](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/PicsAndGifs/20220218165134.png)
  > 
  > 最后返回了一个CallAdapted 
  > 
  > 具体如何配置就不深入分析
  
  > 现在result依据注解的配置解析完成
  > 
  > ```java
  > result = ServiceMethod.parseAnnotations(this, method);
  >         serviceMethodCache.put(method, result);
  > ```
  > 
  > 然后向cache里面放入了
  > 
  > 最后把result返回回去了
  
  > 接下了调用了invoke
  > 
  > ```java
  > loadServiceMethod(method).invoke(args);
  > ```
  
  > ```java
  > final @Nullable ReturnT invoke(Object[] args) {
  >     Call<ResponseT> call = new OkHttpCall<>(requestFactory, args, callFactory, responseConverter);
  >     return adapt(call, args);
  >   }
  > ```
  > 
  > 依据解析的信息和参数new了一个OkhttpCall（内部封装了一个okhttp.call,但是确是retrofit.call的实现类）然后调用了adapt
  > 
  > ```java
  > public Call<Object> adapt(Call<Object> call) {
  >         return executor == null ? call : new ExecutorCallbackCall<>(executor, call);
  >       }
  > ```
  
  > executor不为空，所以实际上就是把OkhttpCall返回了。（注意因为Api的interface的返回值是Call所以他才直接返回的OkhttpCall如果我们返回的是一个Observable那么他就会返回一个Observable，具体的转化逻辑在
  > 
  > `adapt(call, arg)`中,这里不进行分析)

## 小结

- Retrofit使用了JDK的懂它代理对我们的interface进行了解耦合

- Retrofit没有引入新的技术而是不一些常用的网络请求库封装到了一起

- 我们对于网络请求的配置是写在代理接口里面，Retrofit在运行时候会通过反射去读取信息，比如我们的注解配置信息(get，post，url，header等一系列)，函数参数，返回值。（另外高版本的Retrofit对Kotlin协程进行了适配，具体哪个版本开始就懒得查了。）