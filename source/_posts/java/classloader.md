---
title: classloader
date: 2023-02-11 13:27:07
tags:
- Java
---





# 关于本文



> 1. Java内置ClassLoader
> 2. Java ClassLoader加载过程
> 3. 自定义ClassLoader





# 基本概念



> A class loader is an java object that is responsible for loading classes. The class ClassLoader is an abstract class. Given the binary name of a class, a class loader should attempt to locate or generate data that constitutes a definition for the class. A typical strategy is to transform the name into a file name and then read a "class file" of that name from a file system.
>
> Classloader是用于加载class的对象，接受一个class的binary name寻找或者生成该类的2进制信息。





# 类生命周期

![image-20230211165234116](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230211165234116.png)





- 加载

  > 将class文件的二进制信息传入jvm

- 校验

  > 验证是连接阶段的第一步，这一阶段的目的是为了确保Class文件的字节流中包含的信息符合当前虚拟机的要求，并且不会危害虚拟机自身的安全。但从整体 上看，验证阶段大致上会完成下面4个阶段的检验动作：文件格式验证、元数据验证、字节码验证、符号引用验证.

- 准备

  > 将static变量赋0值

- 解析

  > jvm将字符串常量池中的符号引用赋值为直接引用。

- 初始化

  > 执行static代码块or对static变量赋默认值

- 使用

  > 程序员对对应类进行实例化，调用等操作

- 卸载

  > jvm内存不足时，发生full gc，对无用的class对象进行回收。





# ClassLoader变更

> ClassLoader是从java 1.0开始被提出以来一直伴随至今。

> ClassLoader在此过程中几乎没有多大变动，唯一一次变更是在**java 9**引入模块化编程以后，内置的ClassLoader有了不小的变动，但是理念都是类似的。





# Java内置ClassLoader



## JDK 9之前



### 类继承关系

> 这是java所有的ClassLoader

> 看上去很多，但是实际上很多都不是通用的，都是只能用于jdk内部的特殊用途，用于加载特定的class文件。

> 真正有用的只有一个
>
> - SecureClassLoader

![image-20230211143430084](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230211143430084.png)



>  最后经过层层筛选有用的就只有这几个

![image-20230211144351158](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230211144351158.png)



> 类结构关系

![classloader.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/classloader.drawio.png)

- ClassLoader

  > 顶层父类，提供一套公共的模板

- SecureClassLoader

  > 为子类提供了安全校验的功能，扩展安全性。

- URLClassLoader

  > 指定Url加载jar包

- AppClassLoader

  > 用于从java.class.path路径加载的类装入器

- ExtClassLoader

  > 用于加载扩展jar包

- FactoryURLClassLoader

  > 是URLClassLoader的一个Factory，所有工作几乎都是委托给URLClassLoader完成。



### 类加载

> 所谓类加载就是触发ClassLoader的loadClass方法，将本地或者远端来源的class文件装载进入jvm中。

#### 类加载时机

1. 遇到new、getstatic、putstatic或invokestatic这四条字节码指令时，如果类型没有进行过初始 化，则需要先触发其初始化阶段。能够生成这四条指令的典型Java代码场景有： 

   - 使用new关键字实例化对象的时候。 


   - 读取或设置一个类型的静态字段 的时候。


   - 调用一个类型的静态方法的时候。


2. 使用java.lang.reflect包的方法对类型进行反射调用的时候，如果类型没有进行过初始化，则需 要先触发其初始化。

3. 当初始化类的时候，如果发现其父类还没有进行过初始化，则需要先触发其父类的初始化。

4. 当虚拟机启动时，用户需要指定一个要执行的主类（包含main()方法的那个类），虚拟机会先 初始化这个主类。

5. 当使用JDK 7新加入的动态语言支持时，如果一个java.lang.invoke.MethodHandle实例最后的解 析结果为REF_getStatic、REF_putStatic、REF_invokeStatic、REF_newInvokeSpecial四种类型的方法句 柄，并且这个方法句柄对应的类没有进行过初始化，则需要先触发其初始化。

6. 当一个接口中定义了JDK 8新加入的默认方法（被default关键字修饰的接口方法）时，如果有 这个接口的实现类发生了初始化，那该接口要在其之前被初始化。



#### 类加载过程

- 调用ClassLoader loadClass方法加载类
- loadClass内部或许会调用其他classLoader loadClass的方法，或是使用自己的findClass方法获取Class

> Note:
>
> 1. 类加载是由JVM调用ClassLoader，当JVM执行指令的过程中会查内存中是否有该类的Class对象，没有自动匹配ClassLoader加载Class文件进入内存。
> 2. ClassLoader本质上就是一个数据源，大多数情况下是通过输入流把class文件读入内存接着通过defineClass存入虚拟机。



#### ClassLoader之间的关系

> 之前是有列举ClassLoader的类继承关系，但是此关系非彼关系。

> 运行时每一个ClassLoader都会有一个成员变量，我们称之为双亲。
>
> ```java
>  private final ClassLoader parent;
> ```

> ClassLoader基于这种双亲关系，在运行时构成的树形结构关系如下

![image-20230212142847924](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212142847924.png)



#### 双亲委派机制



> 所谓双亲委派其实原理很简单。
>
> 前面讲过ClassLoader通过loadClass加载class



> 双亲委派即是loadClass方法满足如下：
>
> 1. 查看Class是否已经被加载。
> 2. 如果没有被加载调用parent.loadClass
> 3. 如果parent无法加载调用ClassLoader的findClass方法加载Class

> 一句话概况就是内存没有Class的情况下，优先询问双亲加载。

> Note:
>
> 双亲委派机制是Java推荐的做法，但是有的时候业务决定了不方便使用那就可以打破！

流程如下：

![image-20230211233541134](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230211233541134.png)



### 源码分析



#### URLClassLoader



- 构造

  > 两类方式，一类是指定parent，一类是不指定parent
  >
  > ```java
  > public URLClassLoader(URL[] urls){}
  > URLClassLoader(URL[] urls, AccessControlContext acc){}
  > ```
  >
  > 不指定parent默认就是SystemClassLoader
  >
  > ```java
  > public URLClassLoader(URL[] urls, ClassLoader parent,
  >                       URLStreamHandlerFactory factory){}
  > 
  > URLClassLoader(URL[] urls, ClassLoader parent,
  >                    AccessControlContext acc){}
  >     
  > public URLClassLoader(URL[] urls, ClassLoader parent){}
  > ```

  > 另外每一个构造函数都初始化了一个成员
  >
  > ```java
  >  ucp = new URLClassPath(urls, acc);
  > ```

  > ```
  > //用于保存class搜寻路径的类，其中resources表征着正在加载的class或者resource资源。
  > /**
  >  * This class is used to maintain a search path of URLs for loading classes
  >  * and resources from both JAR files and directories.
  >  *
  >  * @author  David Connelly
  >  */
  > public class URLClassPath {}
  > ```

  > 构造函数
  >
  > ```java
  > public URLClassPath(URL[] urls,
  >                     URLStreamHandlerFactory factory,
  >                     AccessControlContext acc) {
  >     //搜寻路径
  >     for (int i = 0; i < urls.length; i++) {
  >         path.add(urls[i]);
  >     }
  >     //把urls反向压入栈里面，即从urls.length - 1 ~ 0
  >     push(urls);
  >     //默认是null,该成员用于处理jar
  >     if (factory != null) {
  >         jarHandler = factory.createURLStreamHandler("jar");
  >     }
  >     if (DISABLE_ACC_CHECKING)
  >         this.acc = null;
  >     else
  >         this.acc = acc;
  > }
  > ```

  > 接着分析一下URLClassLoader是如何找到class文件的
  >
  > ```java
  > protected Class<?> findClass(final String name)
  >     throws ClassNotFoundException
  > {
  >     final Class<?> result;
  >     try {
  >       	//访问控制
  >         result = AccessController.doPrivileged(
  >             new PrivilegedExceptionAction<Class<?>>() {
  >                 public Class<?> run() throws ClassNotFoundException {
  >                     //className转为binary name
  >                     String path = name.replace('.', '/').concat(".class");
  >                     //通过URLClassPath获取resource
  >                     Resource res = ucp.getResource(path, false);
  >                     if (res != null) {
  >                         try {
  >                             //转载如jvm
  >                             return defineClass(name, res);
  >                         } catch (IOException e) {
  >                             throw new ClassNotFoundException(name, e);
  >                         } catch (ClassFormatError e2) {
  >                             if (res.getDataError() != null) {
  >                                 e2.addSuppressed(res.getDataError());
  >                             }
  >                             throw e2;
  >                         }
  >                     } else {
  >                         return null;
  >                     }
  >                 }
  >             }, acc);
  >     } catch (java.security.PrivilegedActionException pae) {
  >         throw (ClassNotFoundException) pae.getException();
  >     }
  >     if (result == null) {
  >         throw new ClassNotFoundException(name);
  >     }
  >     return result;
  > }
  > ```

  > 寻找Resource的负担落在了URLClassPath
  >
  > ```java
  > public Resource getResource(String name, boolean check) {
  > 	//...
  >     
  >     Loader loader;
  >     //获取缓存
  >     int[] cache = getLookupCache(name);
  >     //获取一个加载器
  >     for (int i = 0; (loader = getNextLoader(cache, i)) != null; i++) {
  >         //获取资源
  >         Resource res = loader.getResource(name, check);
  >         //返回
  >         if (res != null) {
  >             return res;
  >         }
  >     }
  >     return null;
  > }
  > ```

  > 获取loader
  >
  > ```java
  > private synchronized Loader getNextLoader(int[] cache, int index) {
  >     if (closed) {
  >         return null;
  >     }
  >     //从缓存中获取
  >     if (cache != null) {
  >         if (index < cache.length) {
  >             Loader loader = loaders.get(cache[index]);
  >             if (DEBUG_LOOKUP_CACHE) {
  >                 System.out.println("HASCACHE: Loading from : " + cache[index]
  >                                    + " = " + loader.getBaseURL());
  >             }
  >             return loader;
  >         } else {
  >             return null; // finished iterating over cache[]
  >         }
  >     } else {
  >         //没有缓存自己生成loader
  >         return getLoader(index);
  >     }
  > }
  > ```

  > 生成Loader
  >
  > ```java
  > private synchronized Loader getLoader(int index) {
  >     if (closed) {
  >         return null;
  >     }
  >      // Expand URL search path until the request can be satisfied
  >      // or the URL stack is empty.
  >     //如果生成缓存的index越界
  >     while (loaders.size() < index + 1) {
  >         // Pop the next URL from the URL stack
  >         URL url;
  >         synchronized (urls) {
  >             if (urls.empty()) {
  >                 return null;
  >             } else {
  >                 //classPath获取
  >                 url = urls.pop();
  >             }
  >         }
  >         // Skip this URL if it already has a Loader. (Loader
  >         // may be null in the case where URL has not been opened
  >         // but is referenced by a JAR index.)
  >         String urlNoFragString = URLUtil.urlNoFragString(url);
  >         if (lmap.containsKey(urlNoFragString)) {
  >             continue;
  >         }
  >         // Otherwise, create a new Loader for the URL.
  >         Loader loader;
  >         try {
  >             //根据classPath的url获取loader
  >             loader = getLoader(url);
  >             // If the loader defines a local class path then add the
  >             // URLs to the list of URLs to be opened.
  >             //获取loader的classPath
  >             URL[] urls = loader.getClassPath();
  >             //将classLoader内包含的url入栈。
  >             if (urls != null) {
  >                 push(urls);
  >             }
  >         } catch (IOException e) {
  >             // Silently ignore for now...
  >             continue;
  >         } catch (SecurityException se) {
  >             // Always silently ignore. The context, if there is one, that
  >             // this URLClassPath was given during construction will never
  >             // have permission to access the URL.
  >             if (DEBUG) {
  >                 System.err.println("Failed to access " + url + ", " + se );
  >             }
  >             continue;
  >         }
  >         // Finally, add the Loader to the search path.
  >         validateLookupCache(loaders.size(), urlNoFragString);
  >         loaders.add(loader);
  >         lmap.put(urlNoFragString, loader);
  >     }
  > 	//返回生成的loader
  >     return loaders.get(index);
  > }
  > ```

  > 关于loader的获取
  >
  > ```java
  > String file = url.getFile();
  > //如果url对应的是一个路径
  > if (file != null && file.endsWith("/")) {
  >     //本地文件夹
  >     if ("file".equals(url.getProtocol())) {
  >         return new FileLoader(url);
  >     } else { // 网络资源
  >         return new Loader(url);
  >     }
  > } else { // 除此之外就是jar包了
  >     return new JarLoader(url, jarHandler, lmap, acc);
  > }
  > ```

  > 1. loader会依据不同的url返回。
  >
  > 2. 不同的loader有不同的获取资源的方法，无非都是依据classname找文件，然后返回Resource，
  > 3. Resource包含了一些方法可以获取文件的二进制，最后整个class的byte[]会通过defineClass加载入jvm



流程图

![image-20230212140716724](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212140716724.png)





#### AppClassLoader

> 加载工作委托给父类

```java
public Class<?> loadClass(String name, boolean resolve)
            throws ClassNotFoundException
        {
            //...
    		//确保包含class文件
			//委托给父类URLClassLoader
            return (super.loadClass(name, resolve));
        }
```

> 没有重新findClass,复用的URLClassLoader的方法。



#### ExtClassLoader

> 关键方法没有重写，即loadClass和findClass均是使用的父类的。

![image-20230212134531813](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212134531813.png)



#### BootClassLoader

> BootClassLoader是在C/C++层实现的，所以java层看不了

> 不过Java层有它的一层封装`BootClassPathHolder`

> 只不过这个不是用来加载类的，是用来加载资源的

> 它是通过内部的一个成员
>
> ```java
> bcp = new URLClassPath(urls, factory, null);
> ```

> 所以可以知道和`URLClassLoader`的实现原理类似



#### 小结

- JDK 9 以前的内置ClassLoader主要是AppClassLoader ExtClassLoader BootClassLoader
- AppClassLoader和ExtClassLoader的功能实现基本上都是复用的URLClassLoader
- BootClassLoader实现在JVM里面，不过在java层有提供`BootClassPathHolder`用以加载系统资源。
- URLClassLoader只是将URL封装并在需要load的时候根据URL的所属协议创建loader，通过Loader加载Resource



## JDK 9以后



### 类继承关系

> 有一定的变动

> ExtClassLoader消失了

> 在继承关系上不再是URLClassLoader的子类了

![image-20230212155611135](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212155611135.png)



继承结构图如下

![image-20230212160352435](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212160352435.png)



其中

- `BuiltinClassLoader`

  > 模板类为子类提供一套通用的模板

- `BootClassLoader`

  > 启动加载器，用于加载启动类加载器路径下的**资源**

- `PlatformClassLoader`

  > 用于和`AppClassLoader`分离开来

- `AppClassLoader`

  > 加载developer自己开放的jar包，通过classpath指定加载路径



### 运行时关系

![image-20230212161515748](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212161515748.png)



### 源码分析



#### BuiltinClassLoader



> 从loadClass开始

> 重写了2参方法

![image-20230212161928435](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212161928435.png)



> 翻看二参源码

> 可以发现与ClassLoader模板中的不一致

```java
 protected Class<?> loadClass(String cn, boolean resolve)
        throws ClassNotFoundException
    {
        Class<?> c = loadClassOrNull(cn, resolve);
        if (c == null)
            throw new ClassNotFoundException(cn);
        return c;
    } 

protected Class<?> loadClassOrNull(String cn, boolean resolve) {
        synchronized (getClassLoadingLock(cn)) {
            // check if already loaded
            //寻找缓存
            Class<?> c = findLoadedClass(cn);

            if (c == null) {
				//jdk 9及之后的模块化
                //查看当前class name是否在已经加载的模块中
                // find the candidate module for this class
                LoadedModule loadedModule = findLoadedModule(cn);
                //在对应的模块里
                if (loadedModule != null) {
                    // package is in a module
                    BuiltinClassLoader loader = loadedModule.loader();
                    //如果模块是由自己加载的 -> 直接从模块中获取class
                    if (loader == this) {
                        if (VM.isModuleSystemInited()) {
                            c = findClassInModuleOrNull(loadedModule, cn);
                        }
                    } else {
                        // delegate to the other loader
                        // 如果不是则委托给模块
                        c = loader.loadClassOrNull(cn);
                    }

                } else { // 当前类不存在于已经加载的模块中
					// 委托双亲加载
                    // check parent
                    if (parent != null) {
                        c = parent.loadClassOrNull(cn);
                    }
					// 双亲无法加载，当前classLoader有classpath，并且已经初始化 -> 当前classloader加载
                    // check class path
                    if (c == null && hasClassPath() && VM.isModuleSystemInited()) {
                        c = findClassOnClassPathOrNull(cn);
                    }
                }

            }

            if (resolve && c != null)
                resolveClass(c);

            return c;
        }
    }
```



> 流程图

> 可以发现在双亲委派的基础上，加入了模块化。

![image-20230212164710399](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230212164710399.png)



> 最后看看findClass

```java
private Class<?> findClassOnClassPathOrNull(String cn) {
    //获取binary name
    String path = cn.replace('.', '/').concat(".class");
    if (System.getSecurityManager() == null) {
        //ucp URLClassPath
        //看到这就知道，实际上和URLClassLoader的加载类似
        //只是相比于URLClassLoader加入了模块化的加持
        Resource res = ucp.getResource(path, false);
        if (res != null) {
            try {
                return defineClass(cn, res);
            } catch (IOException ioe) {
                // TBD on how I/O errors should be propagated
            }
        }
        return null;
    } else {
        // avoid use of lambda here
        PrivilegedAction<Class<?>> pa = new PrivilegedAction<>() {
            public Class<?> run() {
                Resource res = ucp.getResource(path, false);
                if (res != null) {
                    try {
                        return defineClass(cn, res);
                    } catch (IOException ioe) {
                        // TBD on how I/O errors should be propagated
                    }
                }
                return null;
            }
        };
        return AccessController.doPrivileged(pa);
    }
}
```





#### BootClassLoader

> 指定了`URLClassPath`,其他都是复用的`BuiltinClassLoader`

```java
private static class BootClassLoader extends BuiltinClassLoader {
    BootClassLoader(URLClassPath bcp) {
        super(null, null, bcp);
    }

    @Override
    protected Class<?> loadClassOrNull(String cn) {
        return JLA.findBootstrapClassOrNull(this, cn);
    }
};
```

```java
String append = VM.getSavedProperty("jdk.boot.class.path.append");
BOOT_LOADER =
    new BootClassLoader((append != null && !append.isEmpty())
        ? new URLClassPath(append, true)
        : null);
```



#### PlatformClassLoader

> 没有指定ClassPath，但是它其实是**可以loadClass**的。

> 但是实际上因为loadClass中加入了模块化，一些特定的模块的loader会是PlatformClassLoader,所以可以通过`findClassInModuleOrNull(loadedModule, cn);`加载Class，这样`PlatformClassLoader`也具有加载特定模块的功能了。

```java
 private static class PlatformClassLoader extends BuiltinClassLoader {
        static {
            if (!ClassLoader.registerAsParallelCapable())
                throw new InternalError();
        }

        PlatformClassLoader(BootClassLoader parent) {
            super("platform", parent, null);
        }

        /**
         * Called by the VM to support define package for AppCDS.
         *
         * Shared classes are returned in ClassLoader::findLoadedClass
         * that bypass the defineClass call.
         */
        private Package definePackage(String pn, Module module) {
            return JLA.definePackage(this, pn, module);
        }
    }
```

```java
 PLATFORM_LOADER = new PlatformClassLoader(BOOT_LOADER);
```

#### AppClassLoader 

> 用以加载-classpath下的class文件的

> 除了指定了`URLClassPath`功能基本上都是复用的BuiltinClassLoader

```java
private static class AppClassLoader extends BuiltinClassLoader {
    static {
        if (!ClassLoader.registerAsParallelCapable())
            throw new InternalError();
    }

    final URLClassPath ucp;

    AppClassLoader(PlatformClassLoader parent, URLClassPath ucp) {
        super("app", parent, ucp);
        this.ucp = ucp;
    }

    @Override
    protected Class<?> loadClass(String cn, boolean resolve)
        throws ClassNotFoundException
    {
        // for compatibility reasons, say where restricted package list has
        // been updated to list API packages in the unnamed module.
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            int i = cn.lastIndexOf('.');
            if (i != -1) {
                sm.checkPackageAccess(cn.substring(0, i));
            }
        }

        return super.loadClass(cn, resolve);
    }

    @Override
    protected PermissionCollection getPermissions(CodeSource cs) {
        PermissionCollection perms = super.getPermissions(cs);
        perms.add(new RuntimePermission("exitVM"));
        return perms;
    }

    /**
     * Called by the VM to support dynamic additions to the class path
     *
     * @see java.lang.instrument.Instrumentation#appendToSystemClassLoaderSearch
     */
    void appendToClassPathForInstrumentation(String path) {
        ucp.addFile(path);
    }

    /**
     * Called by the VM to support define package for AppCDS
     *
     * Shared classes are returned in ClassLoader::findLoadedClass
     * that bypass the defineClass call.
     */
    private Package definePackage(String pn, Module module) {
        return JLA.definePackage(this, pn, module);
    }

    /**
     * Called by the VM to support define package for AppCDS
     */
    protected Package defineOrCheckPackage(String pn, Manifest man, URL url) {
        return super.defineOrCheckPackage(pn, man, url);
    }
}
```

```java
String cp = System.getProperty("java.class.path");
        if (cp == null || cp.isEmpty()) {
            String initialModuleName = System.getProperty("jdk.module.main");
            cp = (initialModuleName == null) ? "" : null;
        }
        URLClassPath ucp = new URLClassPath(cp, false);
        APP_LOADER = new AppClassLoader(PLATFORM_LOADER, ucp);
```





#### 小结

- JDK9 之后内置的ClassLoader有`BootClassLoader`,`PlatformClassLoader`,`AppClassLoader`，他们负责不同JDK模块的加载，根据[jsr](https://openjdk.org/jeps/261)文档具体如下

> The Java SE and JDK modules defined to the platform class loader are:
>
> `PlatformClassLoader`加载模块如下
>
> ```
> java.activation*            jdk.accessibility
> java.compiler*              jdk.charsets
> java.corba*                 jdk.crypto.cryptoki
> java.scripting              jdk.crypto.ec
> java.se                     jdk.dynalink
> java.se.ee                  jdk.incubator.httpclient
> java.security.jgss          jdk.internal.vm.compiler*
> java.smartcardio            jdk.jsobject
> java.sql                    jdk.localedata
> java.sql.rowset             jdk.naming.dns
> java.transaction*           jdk.scripting.nashorn
> java.xml.bind*              jdk.security.auth
> java.xml.crypto             jdk.security.jgss
> java.xml.ws*                jdk.xml.dom
> java.xml.ws.annotation*     jdk.zipfs
> ```
>
> 
>
> JDK modules that provide tools or export tool APIs are defined to the application class loader:
>
> `ApplicationClassLoader`加载模块如下（除此之外还有开发者自己的模块）
>
> ```
> jdk.aot                     jdk.jdeps
> jdk.attach                  jdk.jdi
> jdk.compiler                jdk.jdwp.agent
> jdk.editpad                 jdk.jlink
> jdk.hotspot.agent           jdk.jshell
> jdk.internal.ed             jdk.jstatd
> jdk.internal.jvmstat        jdk.pack
> jdk.internal.le             jdk.policytool
> jdk.internal.opt            jdk.rmic
> jdk.jartool                 jdk.scripting.nashorn.shell
> jdk.javadoc                 jdk.xml.bind*
> jdk.jcmd                    jdk.xml.ws*
> jdk.jconsole
> ```
>
> 
>
> All other Java SE and JDK modules are defined to the bootstrap class loader:
>
> `BootClassLoader`加载模块
>
> ```
> java.base                   java.security.sasl
> java.datatransfer           java.xml
> java.desktop                jdk.httpserver
> java.instrument             jdk.internal.vm.ci
> java.logging                jdk.management
> java.management             jdk.management.agent
> java.management.rmi         jdk.naming.rmi
> java.naming                 jdk.net
> java.prefs                  jdk.sctp
> java.rmi                    jdk.unsupported
> ```

- JDK9 的内置ClassLoader有一定的变动，但是也不是完全不一样，只是在JDK 8的基础上加入了模块化的支持，除此之外类结构发生了些许的变动。



## 小结

- JDK 9前后虽然类加载不完全相同，但是都满足双亲委派机制
- JDK 9前后的ClassLoader并没有完全变换，本质上就是一个URL的包装，当指令执行过程中缺少Class时JVM通过调用loadClass获取Class字节码。
- JDK 9前后ClassLoader都只负责装载Class字节码的二进制流，之后链接，初始化等过程都与它无关。
- 双亲委派只是一种规范，目的是为了保护类的安全性，以及防止类重复加载。程序员应该遵循，但是如果它与业务相违，违背也是可以的。





# 自定义ClassLoader



> 自定义ClassLoader是业务场景所需

> 比如我们需要一个能运行远程jar包的ClassLoader

> 或者我们需要一个能实现Class隔离的ClassLoader,比如一个Web容器，一个Web容器可能需要为多个进程服务，每一个进程的Class需要互相隔离。



自定义`ClassLoader`一般需要继承一个`ClassLoader `然后重写`findClass`方法或者`defineClass`



## way1

> 重写findClass

> 这应该是比较常见的一种方法。

> 前面源码分析了findClass会在双亲委托以后调用

> 也就是说这种定义方式是遵循默认的双亲委派机制的

```java
public class MyClassLoader extends ClassLoader{
    
    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        //读取class字节码
        byte[] clz = readClassFileAllBytes();
        return defineClass(name,clz,0,clz.length);
    }
}
```



## way2

> 重写loadClass

> 完全接管Class的加载过程。

> loadClass是 ClassLoader总调度方法。

> 这里我们可以自定义加载策略

> 比如预先去服务器轮循，或者调用某个特定的ClassLoader，等等。

> 这种方式最为自由，当然也有可能会出错，因为不同ClassLoader的Class默认是不共享。
>
> 可能出现一个Class被重复Load，或者部分的Class被篡改。

```java
public class MyClassLoader extends ClassLoader{

    @Override
    public Class<?> loadClass(String name) throws ClassNotFoundException {
        //自定义策略
        //....

        //如果前面策略没有加载
        //再读取class字节码
        byte[] clz = readClassFileAllBytes();
        return defineClass(name,clz,0,clz.length);
    }
    
}
```







