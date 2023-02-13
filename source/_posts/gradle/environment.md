---
title: gradle源码环境搭建
date: 2023-02-08 ‏‎10:43:31
tags: 
- gradle
---





# Gradle源码阅读环境搭建

> 接触了很长一段时间的gradle，也看过一部分源码，但是总是感觉差了点东西，所以重新阅读，并以写作的方式加深理解。



## 源码下载

需要准备两个东西

- [gradle v7.6源代码](https://github.com/gradle/gradle/releases/tag/v7.6.0)

- 配置gradle-wrapper.properties 

```properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-7.6-all.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

> note：
>
> 1. 一定要选择gradle-7.6-all，没有all表示只有二进制没有源文件，debug的时候就看不到源文件。
> 2.  其中`gradle v7.6源代码`不是必须的，主要是为了防止idea抽风。有时候代码看不了。其实gradle-wrapper.properties配置的gradle-7.6-all.zip就已经包含了gradle的源代码。



## 阅读目标



- 了解gradle的启动过程
- 了解gradle的生命周期
- 了解项目代码是如何打包出来的
- 了解build.gradle和settings.gradle配置是如何生效的