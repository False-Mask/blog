---
title: Kotlin内联
date: 2021-12-20 11:47:05
tags:
- kotlin
categories:
- kotlin
---







# 简述

> Inline是用来解决高阶函数的短板的。

高阶函数不是说是函数，而是一个对象。很奇怪对吧

```kotlin
fun noInline(block: () -> Unit){
    block()
}
fun main() {
    for (i in 0..1000){
        testNoInline()
    }
}
fun testNoInline() {
    noInline {
        println("hello world")
    }
}
```

看上去好像没有什么问题的。

但是实际上的话是存在一些性能问题的，这主要的锅在于高阶函数。

高阶函数的实现是new了一个fuction类。上面的函数频繁的调用了含有高阶函数的实例，这样就造成了频繁的对象创建。所以这样就引入了inline函数。

# inline

inline函数的实现很简单，就是把高阶函数去掉。

```kotlin
inline fun inlineFuc(block: () -> Unit) {
    block()
}
fun testInlineFunc() {
    inlineFuc {
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
        println("hello world")
    }
}
fun main() {
    for (i in 0..1000){
        testNoInline()
    }

    for (i in 0..1000) {
        testInlineFunc()
    }
}
```

反编译kt文件就可以得到

```kotlin
public static final void testInlineFunc() {
   int $i$f$inlineFuc = false;
   int var1 = false;
   String var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
   var2 = "hello world";
   System.out.println(var2);
}
```

block没了，hh

简单来说他会把传入的高阶函数的参数结构开来，然后把inline函数的其他内容插入到调用处。

# noinline

如果我们有一个这样的需求。

```
inline fun noInlineModifier(block1: () -> Unit, block2: () -> Boolean): (() -> Unit)? {
    val vote = block2()
    return if (vote) block1 else null
}
```

传入高阶函数，然后返回高阶函数。

会发现报虹了。说

> Illegal usage of inline-parameter 'block1' in 'public inline fun noInlineModifier(block1: () -> Unit, block2: () -> Boolean): (() -> Unit)? defined in root package in file Inline2.kt'. Add 'noinline' modifier to the parameter declaration

也就是说block1被内联了，不存在()->Unit这个类型了。

所以我们如果还想实现这种需求该怎么办呢？

noinline即可

```kotlin
inline fun noInlineModifier(noinline block1: () -> Unit, block2: () -> Boolean): (() -> Unit)? {
    val vote = block2()
    return if (vote) block1 else null
}
```

这样的话block就不会参与内联优化，就不会被扒皮。

```kotlin
fun main() {
    noInlineModifier({
        println("Hello world")
        println("Hello world")
        println("Hello world")
        println("Hello world")
    },{
        System.currentTimeMillis() % 2 == 0L
    })?.let { it() }
}

inline fun noInlineModifier(noinline block1: () -> Unit, block2: () -> Boolean): (() -> Unit)? {
    val vote = block2()
    return if (vote) block1 else null
}
```

会发现block1不会参与内联

```java
public static final void main() {
   Function0 block1$iv = (Function0)null.INSTANCE;
   int $i$f$noInlineModifier = false;
   int vote$iv = false;
   vote$iv = System.currentTimeMillis() % (long)2 == 0L;
   Function0 var10000 = vote$iv ? block1$iv : null;
   if ((vote$iv ? block1$iv : null) != null) {
      block1$iv = var10000;
      vote$iv = false;
      block1$iv.invoke();
   }

}
```

# None-Local-return

来看一个很奇妙的东西

```kotlin
fun main() {
    println("Hello")
    inlineReturn {
        return
    }
    println("World")
}

inline fun inlineReturn(block:()->Unit){
    block()
}
```

这样的输出结果是

> Hello

有些奇怪是是吧，我在高阶函数里面return结果给我调用的函数给return了。

这主要的问题在于block被内联了。所以这个高阶函数会被展开添加到调用处。

然后就把调用它的函数给return了

如果 我不让block内联，给他来个noinline，会发生什么

> 'return' is not allowed here
> 
> change to return@inlineReturn

打印结果为

> Hello
> World

# crossline

如果我在一个函数内使用另一个函数，会发生什么美妙的事情。

```kotlin
inline fun crossLineModifier(block:()->Unit){
    Runnable {
        block()
    }
}
```

> Can't inline 'block' here: it may contain non-local returns. Add 'crossinline' modifier to parameter declaration 'block'

不允许，因为会找出none-local return，什么意思？

也就是说如果你简介电泳这个block，直接return的可能不是最外层调用它的函数，这就是none-local returns。所以它不允许你这样做。但是这样并不是不安全的欸，我如果就是像这样做怎么办？

加上crossinline。

这样内联函数的高阶函数参数就会被内联到Runnable里面。

然后再拼接到函数调用处。

```kotlin
fun main() {
    for (i in 0..1000){
        crossLineModifier {
            println()
            println()
            println()
            println()
            println()
            println()
            println()
            println()
            println()
            println()
            println()
        }
    }
}

inline fun crossLineModifier(crossinline block:()->Unit){
    Runnable {
        block()
    }.run()
}
```

但是需要注意的是这个inline函数不能被频繁调用。

这是编译后的java代码

```java
for(short var1 = 1000; var0 <= var1; ++var0) {
   int $i$f$crossLineModifier = false;
   ((Runnable)(new CrossLineKt$main$$inlined$crossLineModifier$1())).run();
}
```

频繁调用会导致对象的重复建立。

## 注意

crossinline虽然允许我们间接内联高阶函数，但是return是return的高阶函数的scope。

# inline property

属性的get/set函数支持inline

比如这样

## 对get函数进行inline

```kotlin
val foo: Foo
    inline get() = Foo()

class Foo {
    var str: String = "1232"
}

fun main() {
    println(foo)
    println(foo)
}
```

这样每次访问foo的get方法的时候都会返回一个新的Foo对象。

这样的get方法具有inline的特点。

返回结果

> Foo@7f31245a
> Foo@6d6f6e28

## 对set函数进行内联

略

# inline

@PublishedApi

当有这样

```kotlin
class B {
    internal inline fun internalInline(block: () -> Unit) {
        block()
    }

    inline fun publishInline(
        noinline block: () -> Unit, block2: () -> Unit = {
            println("Hello world")
        }
    ) {
        internalInline {

        }
    }
}
```

B中有一个internalInline和一个publishInline，如果我们直接在publishInline中调用internalInline会报错。内容是

> Public-API inline function cannot access non-public-API 'internal final inline fun internalInline(block: () -> Unit): Unit defined in B'

为了编译能通过就可以使用注解

```kotlin
@PublishedApi
```

加到internalInline这个内联函数的头上的时候就可以使用了