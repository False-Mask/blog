---
title: Kotlin契约
date: 2021-12-04 15:51:33
tags:
- kotlin
categories:
- kotlin
---





# Contract

Contract的中文叫做协议，协约，合同。

这个合同呢是和编译器签订的。

kotlin的编译器比较聪明但是不是太聪明。

所以有的时候会犯傻hh。



## 引入Contract

比如这同样。

ensureNotNullAndEmpty已经确定了str不为空，也不为""

但是使用的时候编译器还是认为这个东西可能是空的。

![image-20211204155346628](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com//PicsAndGifs/image-20211204155346628.png)



如果这个时候我们想告诉编译器这个东西不是空的，那该怎么弄。



这就得使用contract了

很简单就修改一下代码

```kotlin
@OptIn(ExperimentalContracts::class)
fun String?.ensureNotNullAndEmpty(): Boolean {

    contract {
        returns(true) implies (this@ensureNotNullAndEmpty != null)
    }

    return this != null && !isEmpty()
}
```

这样就不报错了

![image-20211204155911729](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com//PicsAndGifs/image-20211204155911729.png)



## Contract使用

Contract内部的内容比较少

- returns()
- returnsNotNull()
- callsInPlace()

前两个就不做过多解释

第三个是告诉编译器这个函数会在在函数作用域内部执行几次

比如run

```kotlin
public inline fun <R> run(block: () -> R): R {
    contract {
        callsInPlace(block, InvocationKind.EXACTLY_ONCE)
    }
    return block()
}
```

也就是说在执行run这个内联函数期间，block会被调用一次。

这有啥用？

当然有用

```kotlin
fun main() {
    val x:Boolean
    run {
        x = false
    }
}
```

这个代码编译会报错嘛？

答案是不会。

因为编译器知道lambda会被调用一次，所以不存在Val cannot be reassigned的报错。

如果去除这个contract你会发现报错了。

![image-20211204164002321](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com//PicsAndGifs/image-20211204164002321.png)



## Contract的注意事项

不知道你是否有类似的想法。

我告诉编译器这个block会被调用一次，但是我在内部调用了多次，欸就是玩。我不遵循Contract欸。编译器会报错吗？

```kotlin
fun main() {
    val x:Boolean

    myRun {
        println("嘿嘿")
    }
}

@OptIn(ExperimentalContracts::class)
inline fun <R> myRun(block:()->R): R {
    contract {
        callsInPlace(block,InvocationKind.EXACTLY_ONCE)
    }
    block()
    return block()
}
```

会发现编译器正常执行了两次。

没有报错欸。

执行结果

> 嘿嘿
> 嘿嘿



那如果这样呢

```kotlin
fun main() {
    val x:Boolean

    myRun {
        x = false
         println("当前 x的值 $x")
    }
}

@OptIn(ExperimentalContracts::class)
inline fun <R> myRun(block:()->R): R {
    contract {
        callsInPlace(block,InvocationKind.EXACTLY_ONCE)
    }
    block()
    return block()
}
```

欸，编译通过了。

run一下

很奇怪没报错

> 当前 x的值 false
> 当前 x的值 false



再改一下

![image-20211204165103495](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com//PicsAndGifs/image-20211204165103495.png)



```kotlin
fun main() {
    val x:Long

    myRun {
        x = System.currentTimeMillis()
        println("当前 x的值 $x")
    }
}

@OptIn(ExperimentalContracts::class)
inline fun <R> myRun(block:()->R): R {
    contract {
        callsInPlace(block,InvocationKind.EXACTLY_ONCE)
    }
    block()
    return block()
}
```

并不会，所以这个Contract只是告诉编译器。编译器知道了以后，以前不能编译通过的代码可以通过了，但是如果运行时期出问题了那也没办法。这不是编译器的问题，所以使用Contract得注意。你不遵循编译器并不会报错。
