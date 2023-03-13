---
title: Kotlin泛型
date: 2021-12-21 9:35:32
tags:
- kotlin
categories:
- kotlin
---





# 泛型

kotlin的类和java一样有类型参数（也就是泛型）

```kotlin
class Box<T>(t: T) {
    var value = t
}
```

创建一个含有类型参数的对象很简单，申明即可。

```kotlin
val box: Box<Int> = Box<Int>(1)
```



## variance(变化)

变化分为几种。

- 协变
- 逆变
- 不变



>  f(x)是**逆变（contravariant）**的，当A≤B时有f(B)≤f(A)成立；
>  f(x)是**协变（covariant）**的，当A≤B时有f(A)≤f(B)成立；
>  f(x)是**不变（invariant）**的，当A≤B时上述两个式子均不成立，即f(A)与f(B)相互之间没有继承关系。

其实协变和逆变的概念不是Java中的概念，他其实是数学中的概念。

在Kotlin里面。

逆变是泛型类型的父类不是发现类型的父类

如：Contravariant<Object>不是Contravariant<Number>的父类

协变即相反，泛型类型的父类是泛型类型的子类的父类。

如：Covariant<Object>是Covariant<Number>的父类



> generic types in Java are *invariant*, meaning that `List<String>` is *not* a subtype of `List<Object>`

```java
// Java
List<String> strs = new ArrayList<String>();
List<Object> objs = strs; // !!! A compile-time error here saves us from a runtime exception later.
objs.add(1); // Put an Integer into a list of Strings
String s = strs.get(0); // !!! ClassCastException: Cannot cast Integer to String
```

会报错

> Required type: List
>
> Provided:List

但是这样是不会报错的。

```java
Collection<Object> objs =  new ArrayList<>();
Collection<String> strs = new ArrayList<>();
objs.addAll(strs);
```

因为addAll这个方法有些特殊

```java
boolean addAll(Collection<? extends E> c);
```

它加入了协变的支持所以可以直接赋值



## covariance 协变

协变就是子类泛型可以赋值给父类泛型

由于前面说的**Java是不可变的**。所以要实现子类泛型可以赋值给父类泛型，只能通过语言提供的通配符。

```java
public class Covariance {
    public static void main(String[] args) {
        List<Integer> ints = new ArrayList<>();
        invariance(ints);//报错类型不匹配
    }

    private static void invariance(List<Number> nums) {
        Number number = nums.get(0);//正常
        nums.add(1);//正常
    }
}
```

下界通配符可以让原本不变的对象具备协变的能力。

但是加入了一个限制你不能调用任何含有泛型参数的方法。简单来说就是不能修改，但是你可以调用含有泛型类型参数返回值的方法。

```java
public class Covariance {
    public static void main(String[] args) {
        List<Integer> ints = new ArrayList<>();
        covariance(ints);
    }

    private static void covariance(List<? extends Number> nums) {
        Number number = nums.get(0);//正常
        nums.add(1);//报错
    }
}
```

### 为何加入限制

因为不加限制会导致类型不安全。

```java
private static void whyConstraint() {
    List<Integer> integers = new ArrayList<>();
    List<? extends Object> objs = integers;
    objs.add("");//如果不做限制
    Integer integer = integers.get(0);
}
```

如果不加限制objs.add不报错。

那么我们就可以向integers中添加一个String，很恐怖的。这样只要使用integers.get()就会在运行的时候报错，ClassCastException。Java一个强类型的语言竟然会出现类型不安全，这开什么国际玩笑。所以为了避免这种情况，强加限制如果加入协变，不允许调用含有泛型类型参数的方法。也就是不允许修改。



## Contravariant

再次强调Java类型是不可变的

假如我有这样的需求把父类泛型对象赋值给子类。有点向下转型的味道了。这里显然会报错的，因为Java类型不可变。



你可能会问，为什么会有这样的需求，父类对象给子类这显然是不太合理的啊。

如果父类只是容器呢？换句话来说。我new ArrayList<Integer>,然后通过addAll把元素添加到ArrayList<Number>里面，这样ArrayList<Number>里面的元素都是Integer，我们直接使用是没问题的。

又或者说这个ArrayList<Integer>它只是一个中转站而已呢。

```java
public class Contravariant {
    public static void main(String[] args) {
        List<Integer> list = Arrays.asList(1, 2, 3, 4, 5, 6, 7, 8);
        
        List<Number> numbers = new ArrayList<>(list);
        invariance(numbers);//报错
    }

    private static void invariance(List<Integer> integers) {
        integers.add(1);
        integers.get(0);
    }
}
```
