---
title: Kotlin Collection
date: 2022-01-31 16:16:13
tags:
- kotlin
categories:
- kotlin
---





# Collection

> Time： 2022-1-31

首先得知道Collection是kotlin-stdlib里面的东西。

## Type

Kotlin的集合框架有如下的类型

- List
  
  > List is an ordered collection with access to elements by indices – integer numbers that reflect their position. Elements can occur more than once in a list. An example of a list is a telephone number: it's a group of digits, their order is important, and they can repeat.
  > 
  > - List是一个有序的几口，通过一个下标来索引与那苏，（一个integer来反映元素的位置）
  > - 元素在List内可以重复出现
  > - 简单的例子如电话号码，他是数字的一个List，可以重复。

- Set
  
  > *Set* is a collection of unique elements. It reflects the mathematical abstraction of set: a group of objects without repetitions. Generally, the order of set elements has no significance. For example, the numbers on lottery tickets form a set: they are unique, and their order is not important.
  > 
  > - Set是独一无二元素的集合，它和数学概念上的集合高度吻合：一组不重复的元素的集合。
  > - 通常情况下Set的顺序是不重要的，或者说是没任何意义的。
  > - 比如彩票的数字组成一个Set，元素与元素间是独一无二的，元素的排列顺序就是每意义的，或者说我们根本不关系Set中元素的顺序问题。

- Map
  
  > *Map* (or *dictionary*) is a set of key-value pairs. Keys are unique, and each of them maps to exactly one value. The values can be duplicates. Maps are useful for storing logical connections between objects, for example, an employee's ID and their position.
  > 
  > - Map（或则说字典）是一个键值对的集合，key必须是独一无二的，并且每个key只能对应一个value，对于value就没有那么多的限制，可以是null，也可以是重复的。
  > - Map在存储对象的逻辑连接是比较有用的，比如一个员工的ID，和员工的位置就可以组成一个Map

Kotlin的集合框架是的我们可以不依靠于具体的类型（也就是说它什么都可以装，这里是使用泛型构建集合的好处。）

集合的类型和相关的函数都在`kotlin.collections`包下

## Collection types

The Kotlin Standard Library provides implementations for basic collection types: sets, lists, and maps. A pair of interfaces represent each collection type:

- A *read-only* interface that provides operations for accessing collection elements.
- A *mutable* interface that extends the corresponding read-only interface with write operations: adding, removing, and updating its elements.

前面讲了Type有三类，list，set，map。

对于这三类还进行了细分。

- 可变
  
  可以添加元素进入，也可以读取元素。

- 不可变
  
  只提供了get的相关方法，只能读取元素，而不可以修改集合内部的元素。

值得注意的是可变的集合不是说需要声明为var，如果声明为var会提示修改为val

```kotlin
val numbers = mutableListOf("one", "two", "three", "four")
numbers.add("five")   // this is OK
println(numbers)
//numbers = mutableListOf("six", "seven")      // compilation error
```

只读的集合类型是协变的。

父类的泛型是泛型类型的父类。好像有些绕。

这样的代码是不会爆任何错误的。

```kotlin
fun main() {
    var numberList = listOf<Number>()
    val intList = listOf<Int>()
    numberList = intList
}
```

为什么会支持协变？

还能为啥，一定是在定义类型的时候加入了 ？ extends的上界修饰呗，默认的Java类型是既不协变也不逆变。类似的Kt也是一样的。

```kotlin
public interface List<out E> : Collection<E> 
```

类关系图

![Collection interfaces hierarchy](https://gitee.com/False_Mask/pics/raw/master/PicsAndGifs/collections-diagram.png)

小结

- 集合实现主要有两种类型，一类是可迭代的类型，如List和Set，一类是不可迭代的Map
- 可迭代的类型又得分两种，一种是可变的，一种是不可变的，可变需要实现MutableIterator接口,...就实现Iterator接口。
- 不可迭代的Map就明确一些，就两个类，Map以及MutableMap，MuatbleMap相比于具有一个set功能，所以是Map的一个子类。

## Collection

Collection是不可变集合的接口，定义了一些公共的行为，它继承自Iteratable

```kotlin
public interface Iterable<out T> {
    public operator fun iterator(): Iterator<T>
}
public interface Collection<out E> : Iterable<E> {
    public val size: Int

    public fun isEmpty(): Boolean

    public operator fun contains(element: @UnsafeVariance E): Boolean

    override fun iterator(): Iterator<E>

    public fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean
}
```

### List

```kotlin
public interface List<out E> : Collection<E> {
    override val size: Int
    override fun isEmpty(): Boolean
    override fun contains(element: @UnsafeVariance E): Boolean
    override fun iterator(): Iterator<E>
    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean
    public operator fun get(index: Int): E
    public fun indexOf(element: @UnsafeVariance E): Int
    public fun lastIndexOf(element: @UnsafeVariance E): Int
    public fun listIterator(): ListIterator<E>
    public fun listIterator(index: Int): ListIterator<E>
    public fun subList(fromIndex: Int, toIndex: Int): List<E>
}
```

一个接口

通常情况下我们使用的是它的实现类ArrayList。

### ArrayList

```kotlin、
@SinceKotlin("1.1") public actual typealias ArrayList<E> = java.util.ArrayList<E>
```

#### 构造函数

```kotlin
public ArrayList() {
    this.elementData = DEFAULTCAPACITY_EMPTY_ELEMENTDATA;
}
```

赋值了一个空的object数组。

```kotlin
public ArrayList(Collection<? extends E> c) {
    Object[] a = c.toArray();
    if ((size = a.length) != 0) {
        if (c.getClass() == ArrayList.class) {
            elementData = a;
        } else {
            elementData = Arrays.copyOf(a, size, Object[].class);
        }
    } else {
        // replace with empty array.
        elementData = EMPTY_ELEMENTDATA;
    }
}
```

如果传入的是一个Collection，那就把内容全部加入到这个collection里面，如果这个Collection是空的那就给一个空的集合。

```kotlin
public ArrayList(int initialCapacity) {
    if (initialCapacity > 0) {
        this.elementData = new Object[initialCapacity];
    } else if (initialCapacity == 0) {
        this.elementData = EMPTY_ELEMENTDATA;
    } else {
        throw new IllegalArgumentException("Illegal Capacity: "+
                                           initialCapacity);
    }
}
```

如果初始化长度大于0就new一个对应长度的数组。

如果为0，直接赋值为一个空的数组。

否则就是抛异常。

实现嘛好像都比较简单就是new 一个数组，如果给定了初始化长度就new对应长度的数组。

如果没有给定长度，那就new一个空的object数组。

#### add

add内部public的方法有两种种

- public boolean add(E e) 
- public void add(int index, E element)

```kotlin
public boolean add(E e) {
    modCount++;
    add(e, elementData, size);
    return true;
}
```

调用了内部的一个private方法。然后return true

```kotlin
private void add(E e, Object[] elementData, int s) {
    if (s == elementData.length)
        elementData = grow();
    elementData[s] = e;
    size = s + 1;
}
```

先判断list内部已近容纳的元素数量是否等于object数组的最大大小。

如果是说明空间已近满了，需要扩容。

```kotlin
private Object[] grow() {
    return grow(size + 1);
}
private Object[] grow(int minCapacity) {
    int oldCapacity = elementData.length;
    if (oldCapacity > 0 || elementData != DEFAULTCAPACITY_EMPTY_ELEMENTDATA) {
        int newCapacity = ArraysSupport.newLength(oldCapacity,
                minCapacity - oldCapacity, /* minimum growth */
                oldCapacity >> 1           /* preferred growth */);
        return elementData = Arrays.copyOf(elementData, newCapacity);
    } else {
        return elementData = new Object[Math.max(DEFAULT_CAPACITY, minCapacity)];
    }
}
```

ArraysSupport.newLength是决定数组扩容多少的关键。

实现不难。就是将默认扩容策略和最小需要扩容大小进行对比，选最大的那个。

除此之外还给出了一个最大长度的限制 Integer.MAX_VALUE - 8，之所以要减去这个8是为了给对象头腾空间，对象的引用是会消耗一定的长度的。减8很大程度上为了比较oom。

```kotlin
public static int newLength(int oldLength, int minGrowth, int prefGrowth) {
    // assert oldLength >= 0
    // assert minGrowth > 0

    int newLength = Math.max(minGrowth, prefGrowth) + oldLength;
    if (newLength - MAX_ARRAY_LENGTH <= 0) {
        return newLength;
    }
    return hugeLength(oldLength, minGrowth);
}
private static int hugeLength(int oldLength, int minGrowth) {
    int minLength = oldLength + minGrowth;
    if (minLength < 0) { // overflow
        throw new OutOfMemoryError("Required array length too large");
    }
    if (minLength <= MAX_ARRAY_LENGTH) {
        return MAX_ARRAY_LENGTH;
    }
    return Integer.MAX_VALUE;
}
```

然后扩容完毕以后就是存储数据了。

另外一个add的内部实现也是类似的。

#### remove

```kotlin
public boolean remove(Object o) {
    final Object[] es = elementData;
    final int size = this.size;
    int i = 0;
    found: {
        if (o == null) {
            for (; i < size; i++)
                if (es[i] == null)
                    break found;
        } else {
            for (; i < size; i++)
                if (o.equals(es[i]))
                    break found;
        }
        return false;
    }
    fastRemove(es, i);
    return true;
}
private void fastRemove(Object[] es, int i) {
    modCount++;
    final int newSize;
    if ((newSize = size - 1) > i)
        System.arraycopy(es, i + 1, es, i, newSize - i);
    es[size = newSize] = null;
}
```

for循环遍历，然后把后续的元素给移除。

### 总结

ArrayList的实现就核心实现来看不难理解，就是封装一个object数组。

由于它在明面上看来是一个动态数组，所以需要动态扩容，而动态扩容策略是一个指数扩容策略，数组大小指数倍增长。在扩容完以后直接插入。

### listOf

listOf总算是kt自己的东西了。

不过呢listOf有几个

```kotlin
public inline fun <T> listOf(): List<T> = emptyList()
public fun <T> emptyList(): List<T> = EmptyList
internal object EmptyList : List<Nothing>, Serializable, RandomAccess {
    private const val serialVersionUID: Long = -7390468764508069838L

    override fun equals(other: Any?): Boolean = other is List<*> && other.isEmpty()
    override fun hashCode(): Int = 1
    override fun toString(): String = "[]"

    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true
    override fun contains(element: Nothing): Boolean = false
    override fun containsAll(elements: Collection<Nothing>): Boolean = elements.isEmpty()

    override fun get(index: Int): Nothing = throw IndexOutOfBoundsException("Empty list doesn't contain element at index $index.")
    override fun indexOf(element: Nothing): Int = -1
    override fun lastIndexOf(element: Nothing): Int = -1

    override fun iterator(): Iterator<Nothing> = EmptyIterator
    override fun listIterator(): ListIterator<Nothing> = EmptyIterator
    override fun listIterator(index: Int): ListIterator<Nothing> {
        if (index != 0) throw IndexOutOfBoundsException("Index: $index")
        return EmptyIterator
    }

    override fun subList(fromIndex: Int, toIndex: Int): List<Nothing> {
        if (fromIndex == 0 && toIndex == 0) return this
        throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex")
    }

    private fun readResolve(): Any = EmptyList
}
```

new了一个单例的List的实现方法。实现了List<Nothing>表示内部什么都没有。

```kotlin
public fun <T> listOf(element: T): List<T> = java.util.Collections.singletonList(element)
```

单类型的话就调用了java里面的方法

```java
public static <T> List<T> singletonList(T o) {
    return new SingletonList<>(o);
}
SingletonList
public fun <T> listOf(vararg elements: T): List<T> = if (elements.size > 0) elements.asList() else emptyList()
public fun <T> listOf(vararg elements: T): List<T> = if (elements.size > 0) elements.asList() else emptyList()
public actual fun <T> Array<out T>.asList(): List<T> {
    return ArraysUtilJVM.asList(this)
}
static <T> List<T> asList(T[] array) {
    return Arrays.asList(array);
}
public static <T> List<T> asList(T... a) {
    return new ArrayList<>(a);
}
```

所以呢底层还是复用的Java的ArrayList

### 总结

listOf虽然写的还是kt代码，不过呢它实际上就只是一个工具类，它直接使用的大多还是java提供的集合框架。

### Collection.kt

CollectionKt内部有比较多的集合用的方法，（公共方法。）

```kotlin
public fun <T> emptyList(): List<T> = EmptyList
public fun <T> listOf(vararg elements: T): List<T> ...
public inline fun <T> listOf(): List<T> = emptyList()
public inline fun <T> mutableListOf(): MutableList<T> = ArrayList()
public inline fun <T> arrayListOf(): ArrayList<T> = ArrayList()
public fun <T> mutableListOf(vararg elements: T): MutableList<T> ...
public fun <T> arrayListOf(vararg elements: T): ArrayList<T> ...
public fun <T : Any> listOfNotNull(element: T?): List<T> ...
public fun <T : Any> listOfNotNull(vararg elements: T?): List<T>  ...
public inline fun <T> List(size: Int, init: (index: Int) -> T): List<T>  ...
...
```

这里做一个总结

构建相关

- public fun <T> emptyList()
- public inline fun <T> listOf()
- public fun <T> listOf(vararg elements: T)
- public inline fun <T> mutableListOf()
- public inline fun <T> arrayListOf()
- public fun <T> mutableListOf(vararg elements: T)
- public fun <T> arrayListOf(vararg elements: T)
- public inline fun <T> List(size: Int, init: (index: Int) -> T)
- public inline fun <T> MutableList(size: Int, init: (index: Int) -> T)
- public inline fun <E> buildList(@BuilderInference builderAction: MutableList<E>.() -> Unit)
- public inline fun <E> buildList(capacity: Int, @BuilderInference builderAction: MutableList<E>.() -> Unit)

扩展属性

- public val Collection<*>.indices: IntRange
- public val <T> List<T>.lastIndex: Int

工具

#### 扩展函数

- public inline fun <T> Collection<T>.isNotEmpty()
- public inline fun <T> Collection<T>?.isNullOrEmpty()
- public inline fun <T> Collection<T>?.orEmpty()
- public inline fun <T> List<T>?.orEmpty()
- public inline fun <C, R> C.ifEmpty(defaultValue: () -> R): R
- public inline fun <@kotlin.internal.OnlyInputTypes T> Collection<T>.containsAll(elements: Collection<T>)
- public fun <T> Iterable<T>.shuffled(random: Random)
- public fun <T : Comparable<T>> List<T?>.binarySearch(element: T?, fromIndex: Int = 0, toIndex: Int = size)

#### 顶层函数

- public fun <T : Any> listOfNotNull(element: T?)
- public fun <T : Any> listOfNotNull(vararg elements: T?)