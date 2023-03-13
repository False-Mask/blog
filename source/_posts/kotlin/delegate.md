---
title: Kotlin委托
date: 2021-12-19 19:09:08
tags:
- kotlin
categories:
- kotlin
---





# 委托

Kotlin对于委托是开箱支持的，委托是一种消除样板代码的方式

> The [Delegation pattern](https://en.wikipedia.org/wiki/Delegation_pattern) has proven to be a good alternative to implementation inheritance, and Kotlin supports it natively requiring zero boilerplate code.



## 接口委托

一个类可以实现一个接口，然后把这个接口的公开方法委托给另外一个类。

words is cheap ，give me the code

```kotlin
interface Base {
    fun print()
}

class BaseDelegate: Base {
    override fun print() {
        println("我是Base的Delegate我现在非常的后悔，为啥我要给BaseImp背锅")
    }
}

class BaseImp(delegate: BaseDelegate): Base by delegate {

}

fun main() {
    val baseDelegate = BaseDelegate()
    val baseImp = BaseImp(baseDelegate)
    baseImp.print()
}
```



输出结果

> 我是Base的Delegate我现在非常的后悔，为啥我要给BaseImp背锅



当BaseImp覆写了print方法的时候会覆盖掉delegate的方法。

> Note, however, that members overridden in this way do not get called from the members of the delegate object, which can only access its own implementations of the interface members:

```kotlin
class BaseImp(delegate: BaseDelegate): Base by delegate {
    override fun print() {
        println("我是BaseImp我改过自新了我打算，自己实现print")
    }
}
```





执行结果

> 我是BaseImp我改过自新了我打算，自己实现print







## 委托属性

> With some common kinds of properties, even though you can implement them manually every time you need them, it is more helpful to implement them once, add them to a library, and reuse them later. For example:

委托属性能实现以下的需求

- 懒加载属性
- 将一个不可观察的属性变成可被观察的属性
- 从map里面拿取属性值

> 委托属性本质也就是组合模式将set，get方法委托给一个对象，通过编译器生成一些模板的代码来实现方便开发者的目的

Kotlin支持委托属性

```kotlin
var p:String by StringDelegate()
```

这波委托就弄好了

```kotlin
class StringDelegate {
    operator fun getValue(delegateProperties: Any, property: KProperty<*>): String {
        return "我谢谢${delegateProperties}委托${property.name}给我啊！！！"
    }

    operator fun setValue(delegateProperties: Any, property: KProperty<*>, s: String) {
        println("${property.name}被调用set方法设置值为$s")
    }
}
```

当调用p.set和p.get的时候都会委托调用到StringDelegate的get/set方法。





### 标准的委托——lazy

```kotlin
public actual fun <T> lazy(initializer: () -> T): Lazy<T> = SynchronizedLazyImpl(initializer)
```

其实就是把东西委托给了Lazy接口

```kotlin
public inline operator fun <T> Lazy<T>.getValue(thisRef: Any?, property: KProperty<*>): T = value
```

使用了委托属性的方法来实现的。



### 可被观察的属性

其实内部也是依靠属性的委托来实现的。

```kotlin
var name:String by Delegates.observable("this is initial value"){property, oldValue, newValue ->
    println("${property.name}:$oldValue->$newValue")
}
```



```kotlin
val delegateProperties:DelegateProperties = DelegateProperties()
delegateProperties.name = "1"
delegateProperties.name = "2"
delegateProperties.name = "3"
delegateProperties.name = "4"
delegateProperties.name = "4"
```

输出结果

> name:this is initial value->1
> name:1->2
> name:2->3
> name:3->4
> name:4->4



### vetoable属性

除此之外还有一个vetoable这个能再setValue以前决定是否要接受这种修改。

```kotlin
var vetoableStr:String by Delegates.vetoable("vetoable"){property: KProperty<*>, oldValue: String, newValue: String ->
    println("${property.name}:$oldValue->$newValue")
    false
}
```



```kotlin
delegateProperties.vetoableStr = "1"
delegateProperties.vetoableStr = "2"
delegateProperties.vetoableStr = "3"
delegateProperties.vetoableStr = "4"
delegateProperties.vetoableStr = "4"
```



输出结果

> vetoableStr:vetoable->1
> vetoableStr:vetoable->2
> vetoableStr:vetoable->3
> vetoableStr:vetoable->4
> vetoableStr:vetoable->4



### map的委托

```kotlin
class User(
   val map: Map<String, Any>
) {
    val name: String by map
    val age: Any by map
}
```



```kotlin
fun main() {
    val user = User(
        mapOf(
            "name" to "John Doe",
            "age" to 25
        )
    )
    println(user.name)
    println(user.age)
}
```



> 这样达到的效果和map["name"]和map["age"]是一样的



###  委托实行其他的新方式

通常情况下，我们如果要委托得自己的创建一个类。

比如一个Int的委托类

```kotlin
class IntDelegate {
    var delegateInt = 0
    operator fun getValue(nothing: Nothing?, property: KProperty<*>): Int {
        return delegateInt
    }

    operator fun setValue(nothing: Nothing?, property: KProperty<*>, i: Int) {
        delegateInt = i + 1
    }
}
```



但是我们其实是可以不新建类的。(因为委托是给对象委托的，如果你by后是对象而且还是这个对象重载了get/set就可以被委托)

```kotlin
fun plusOneIntDelegate(): ReadWriteProperty<Any?, Int> {
    return object : ReadWriteProperty<Any?, Int> {

        var intDelegate = 0

        override fun getValue(thisRef: Any?, property: KProperty<*>): Int {
            return intDelegate
        }

        override fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
            intDelegate = value + 1
        }
    }
}
```

委托还能委托给泛型参数

```kotlin
class C<Type>(private var impl:Type){
    var group:Type by ::impl
}
```
