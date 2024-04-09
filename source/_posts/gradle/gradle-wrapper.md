---
title: Gradle启动之gradle-wrapper
date: 2023-02-09 23:19:49
tags:
- gradle
categories:
- gradle
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gradle-dark-green-primary.png
---





# Gradle启动之gradle-wrapper

> gradle-wrapper即gradle的包装器。
>
> gradle它完成了gradle的环境配置以及gradle的启动。（也就是说到这一步gradle才开始启动起来）





## EntryPoint

> 前面分析到了，gradlew shell脚本执行java 程序启动了gradle-wrapper.jar，接着就从这里开始进行分析。

> 代码量还是比较少的。

> 美中不足的是没有gradle-wrapper的源代码，代码没注释可读性稍差，不过好在逻辑简单。就不去翻gradle源码了。
>
> Notes:
>
> 如果对代码有洁癖的bro，可以打开gradle源代码
>
> - subprojects/wapper
> - subprojects/cli
> - subprojects/wrapper-shared

![image-20230209234306357](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230209234306357.png)



```java
public static void main(String[] args) throws Exception {
    //获取jar包文件对象
    File wrapperJar = wrapperJar();
    //获取gradle-wrapper.properties文件路径
    File propertiesFile = wrapperProperties(wrapperJar);、
    //获取项目的根路径即 ./../../../
    //gradle-wrapper.jar存放在rootProject/gradle/wrapper/gradle-wrapper.jar
    File rootDir = rootDir(wrapperJar);
    //创建命令行解析器(解析gradlew的参数)
    CommandLineParser parser = new CommandLineParser();
    //配置参数
    parser.allowUnknownOptions();
    parser.option(new String[]{"g", "gradle-user-home"}).hasArgument();
    parser.option(new String[]{"q", "quiet"});
    //配置property并进行解析
    SystemPropertiesCommandLineConverter converter = new SystemPropertiesCommandLineConverter();
    converter.configure(parser);
    ParsedCommandLine options = parser.parse(args);
    //获取系统变量并放入
    Properties systemProperties = System.getProperties();
    systemProperties.putAll(converter.convert(options, new HashMap()));
    File gradleUserHome = gradleUserHome(options);
    addSystemProperties(systemProperties, gradleUserHome, rootDir);
	//获取logger
    Logger logger = logger(options);
    WrapperExecutor wrapperExecutor = WrapperExecutor.forWrapperPropertiesFile(propertiesFile);
    //执行下载和启动
    wrapperExecutor.execute(args, new Install(logger, new Download(logger, "gradlew", "0"), new PathAssembler(gradleUserHome, rootDir)), new BootstrapMainStarter());
}
```



## 参数配置



> 参数配置需要如下类
>
> - CommandLineParser
>
>   进行参数的解析获取ParsedCommandLine
>
> - SystemPropertiesCommandLineConverter
>
>   进行参数的转换，将解析后的参数转化为 Map<String, String> 。
>
> - Properties
>
>   参数最后的存放容器



数据转化图如下

![gradle-properties.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gradle-properties.drawio.png)



## 执行启动

> 整个过程涉及
>
> - Install
>
>   下载并配置gradle
>
> - BootstrapMainStarter
>
>   引导启动gradle



> 在执行下载之前会进行下载的配置，配置是存在于gradle-warpper.properties文件下
>
> ```java
> WrapperExecutor wrapperExecutor = WrapperExecutor.forWrapperPropertiesFile(propertiesFile);
> //触发下载和gradle执行
> wrapperExecutor.execute(...);
> ```

> WrapperExecutor.execute
>
> ```java
> //执行下载
> File gradleHome = install.createDist(this.config);
> //启动gradle
> bootstrapMainStarter.start(args, gradleHome);
> ```



### Install

> 过程如下：
>
> 1. 通过exclusiveFileAccessManager.access进行进程的互斥操作（其通过FileLock实现）
> 2. 获取File操作权以后进行文件的下载操作。
> 3. 下载完成后解压。



过程图如下：

![download.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/download.drawio.png)



### BootstrapMainStarter

```java
public void start(String[] args, File gradleHome) throws Exception {
    //寻找gradlehome/lib/gradle-launcher-.*\.jar文件
    File gradleJar = findLauncherJar(gradleHome);
    if (gradleJar == null) {
        throw new RuntimeException(String.format("Could not locate the Gradle launcher JAR in Gradle distribution '%s'.", gradleHome));
    } else {
        //获取并设置classLoader
        URLClassLoader contextClassLoader = new URLClassLoader(new URL[]{gradleJar.toURI().toURL()}, ClassLoader.getSystemClassLoader().getParent());
        Thread.currentThread().setContextClassLoader(contextClassLoader);
        //等效于GradleMain.main(args);
        Class<?> mainClass = contextClassLoader.loadClass("org.gradle.launcher.GradleMain");
        Method mainMethod = mainClass.getMethod("main", String[].class);
        mainMethod.invoke((Object)null, args);
        //关闭classLoader
        if (contextClassLoader instanceof Closeable) {
            contextClassLoader.close();
        }

    }
}


```



## 小结

- 到目前为止gradle并没有启动
- gradle-wrapper目前所做的也不过是依据gradle-wrapper.properties的文件的配置，下载gradle并启动