---
title: Gson之基础使用篇
date: 2023-03-28 23:37:58
tags:
- gson
---



# Gson基础使用



> Gson属于是Java生态的必备技能，很有必要深入学习。



## 依赖引入



- `Gradle`

```groovy
dependencies {
  implementation 'com.google.code.gson:gson:2.10.1'
}
```

- `Maven`

```xml
<dependency>
  <groupId>com.google.code.gson</groupId>
  <artifactId>gson</artifactId>
  <version>2.10.1</version>
</dependency>
```



## 什么是Gson

> **Gson**是一个**Google**开源的**JSON**序列化和反序列化框架



## Gson设计目标



- 提供一个简单如`toString`方法般的机制实现Java对象到JSON字符串的互相转化
- 对于预定义的Java Bean实现无侵入式
- 允许自定义对象的序列化和反序列化
- 生成**紧凑的**、**可读的J**SON输出



## 使用Gson



- Gson采用的是门面模式，所有与序列化相关的策略都内聚到一个名为`com.google.gson.Gson`的类里面。

- 使用Gson的第一步就是实例化`com.google.gson.Gson`对象



## 实例化Gson



- way1

```kotlin
val gson = Gson()
```

- way2

```kotlin
 val gsonBuilder = GsonBuilder()
        .setVersion(1.0)
        .disableJdkUnsafe()
        .disableHtmlEscaping()
        .disableInnerClassSerialization()
        .setPrettyPrinting()
        .excludeFieldsWithModifiers()
        .setLenient()
        .addDeserializationExclusionStrategy(...)
        .registerTypeAdapter(...)
        .registerTypeAdapterFactory(...)
        .addReflectionAccessFilter(...)
        .setDateFormat(...)
        .create()
```



## 基本数据类型序列化 & 反序列化

```kotlin
// 序列化 
val gson = Gson()
 gson.toJson(1) // ==> 1
 gson.toJson("abcd") // ==> "abcd"
 gson.toJson(10) // ==> 10
 val values = intArrayOf(1)
 gson.toJson(values) // ==> [1]
```



```java
// 反序列化
val i = gson.fromJson("1", Int::class.java)
val intObj = gson.fromJson("1", Int::class.java)
val longObj = gson.fromJson("1", Long::class.java)
val boolObj = gson.fromJson("false", Boolean::class.java)
val str = gson.fromJson("\"abc\"", String::class.java)
val strArray = gson.fromJson(
    "[\"abc\"]",
    Array<String>::class.java
)
```





## 对象序列化 & 反序列化

```kotlin
fun main() {
    val obj = Obj(1, "2")

    val gson = Gson()
    // 序列化
    val json = gson.toJson(obj)
    println(json)
    // 反序列化
    println(gson.fromJson(json,Obj::class.java))
}


data class Obj(
    val value1: Int,
    val value2: String,
)
```



## 嵌套类



```kotlin
class A {

    val a: String = "A"

    inner class B(
        val b: String = "B"
    ) {
        fun test() {
            println(this@A.hashCode())
        }
    }

}

fun main() {
    // 创建A以及内部类B的对象实例
    val a = A()
    val b = a.B()

    val gson = Gson()
    // 序列化
    val json = gson.toJson(b)

	// 反序列化
    val fromJson = gson.fromJson(json, b::class.java)

	// 打印序列化json字符串
    println(json)
    // 获取反序列化内部类的外部类引用
    println(fromJson.test())
}
```



## 集合序列化



### list



```kotlin
fun main() {
    // gson
    val gson = Gson()
    val ints: List<Int> = listOf(1, 2, 3, 4, 5)
	// 序列化并打印
    val json = gson.toJson(ints) 
    println(json)   
	// 反序列化
    val ints2 = gson.fromJson(json,ints::class.java)


}
```



> 然而结果是报错

![image-20230329184054755](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230329184054755.png)



> 因为listOf，Arrays.asList都会返回一个`java.util.Arrays$ArrayList`而不是`java.util.ArrayList`,强转过程会报错



> 正确的思路

```kotlin
fun main() {
    val gson = Gson()
    val ints: List<Int> = arrayListOf(1, 2, 3, 4, 5)

    val json = gson.toJson(ints) // ==> json is [1,2,3,4,5]

    println(json)


    val ints2 = gson.fromJson(json,ints::class.java)


}
```



> 或者

```kotlin
fun main() {
    val gson = Gson()
    val ints: Array<Int> = arrayOf(1, 2, 3, 4, 5)

    val json = gson.toJson(ints) // ==> json is [1,2,3,4,5]

    println(json)


    val ints2 = gson.fromJson(json,ints::class.java)


}
```



### map

```kotlin
fun main() {
    val gson = Gson()
    val stringMap: MutableMap<String?, String> = LinkedHashMap()
    stringMap["key"] = "value"
    stringMap[null] = "null-entry"
    var json = gson.toJson(stringMap) // ==> json is {"key":"value","null":"null-entry"}
    println(json)


}
```



### 复杂map



```kotlin
fun main() {
    val gson = GsonBuilder().enableComplexMapKeySerialization().create()
    val complexMap: MutableMap<PersonName, Int> = LinkedHashMap()
    complexMap[PersonName("John", "Doe")] = 30
    complexMap[PersonName("Jane", "Doe")] = 35

    val json = gson.toJson(complexMap)
    println(json)



}

class PersonName(
    var firstName: String,
    var lastName: String
)
```



## 泛型



```kotlin
class Foo<T>(
    val data: T?
)

data class Bar(
    val a: Int,
    val b: Int
)

fun main() {


    val gson = Gson()
    val foo: Foo<Bar> = Foo<Bar>(Bar(1,1))
    // 等价写法
    println(gson.toJson(foo)
    println(gson.toJson(foo,foo::class.java)
    println(gson.toJson(foo, object : TypeToken<Foo<Bar>>() {}.type))


}
```



## object数组



```kotlin
fun main() {
    val collection: MutableCollection<Any> = ArrayList<Any>()
    collection.add("hello")
    collection.add(5)
    collection.add(Event("GREETINGS", "guest"))
    val g = Gson()
    println(g.toJson(collection))

}

class Event constructor(
    private val name: String,
    private val source: String
)
```



## 内置的序列化器

```kotlin
fun main() {
    val g = Gson()
    val url = URL("http://blog.tuzhiqiang.top/")
    println(g.toJson(url)) // "http://blog.tuzhiqiang.top/"
}
```

`TypeAdapters.java`

![image-20230329204305380](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230329204305380.png)





## 自定义序列化器



> Gson允许我们自定义序列化器和反序列化器，其中与序列化和反序列化过程相关的包含如下

- JSON Serializers: 参与json的序列化过程
- JSON Deserializers: 参与json的反序列化过程
- Instance Creators: 进行实例的创建，使用了Deserializers可以不对其进行指定



```kotlin
fun main() {
    val gson = GsonBuilder()
        .registerTypeAdapter(MyType::class.java, MySerializer())
        .registerTypeAdapter(MyType::class.java, MyDeserializer())
        .create()

    val mt = MyType(1, 1)

    val json = gson.toJson(mt)
    println(json)

    println(gson.fromJson(json, MyType::class.java))

}

class MySerializer : JsonSerializer<MyType> {
    override fun serialize(
        src: MyType,
        typeOfSrc: Type,
        context: JsonSerializationContext
    ): JsonElement {

        return JsonObject().apply {
            addProperty("aa", src.a)
            addProperty("bb", src.b)
        }

    }

}

class MyDeserializer : JsonDeserializer<MyType> {
    override fun deserialize(
        json: JsonElement,
        typeOfT: Type,
        context: JsonDeserializationContext
    ): MyType {

        val obj = json.asJsonObject
        return MyType(obj["aa"].asInt, obj["bb"].asInt)

    }

}

data class MyType(
    val a: Int,
    val b: Int,
)
```



## Gson配置



### 格式化字符串



```kotlin
fun main() {

    val gson = GsonBuilder()
        .setPrettyPrinting()
        .create()


	// {
  	//	"a": 1,
  	// 	"b": "2",
   	// 	"c": "3"
	//	}
    println(gson.toJson(Test(1, "2", '3')))


}

data class Test(
    val a: Int,
    val b: String,
    val c: Char,
)

data class Test2(
    val a: Int,
    val b: Int,
    val c: Int
)
```



### 空对象序列化



```kotlin
fun main() {
    val nu = NullObj()
    val gson = GsonBuilder()
        .serializeNulls()
        .create()
	// {"t":null}
    // 会对t这个null值进行序列化
    println(gson.toJson(nu))
}


class NullObj(
    val t:String? = null
)
```



### 版本控制



```kotlin
data class VersionedData(
    @Since(1.0)
    val a: Int,
    @Since(2.0)
    val b: String,
    @Since(3.0)
    val c: Char
)

fun main() {

    val gson = GsonBuilder()
        .setVersion(1.0)
        .create()

    val vd = VersionedData(1,"2",'3')
	// 由于是版本1.0只会序列化食醋胡 a
    // 如果是2.0则是 a，b。
    // 3.0则是a，b，c
    println(gson.toJson(vd))

}
```



### 排除序列化元素

```kotlin
val gson = GsonBuilder()
// 排除所有篇private修饰符修饰的元素    
.excludeFieldsWithModifiers(Modifier.PRIVATE)
// 排除所有没有@Expose注解标记的属性
.excludeFieldsWithoutExposeAnnotation()
    .create()
```



```kotlin
data class ExcludeData(
    @Expose
    val a: Int,
    @Expose
    private val b: String,
    val c: Char,
    val d: Boolean
)

fun main() {
    val gson = GsonBuilder()
    // 排除所有没有标记expose的元素（c，d）
        .excludeFieldsWithoutExposeAnnotation()
    // 排除所有private修饰符修饰的属性（b）
        .excludeFieldsWithModifiers(Modifier.PRIVATE)
        .create()

    val ed = ExcludeData(1,"2",'3',false) // {"a":1}

    println(gson.toJson(ed))

}
```



### 自定义排除策略



```kotlin
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FIELD)
annotation class MyAnnotation {}

class SampleObjectForTest {
    @MyAnnotation
    private val annotatedField = 5
    private val stringField = "someDefaultValue"
    private val longField: Long = 1234
    private val clazzField: Class<*>? = null
}

class MyExclusionStrategy constructor(private val typeToSkip: Class<*>) :
    ExclusionStrategy {
        // 排除序列化类型
    override fun shouldSkipClass(clazz: Class<*>): Boolean {
        return clazz == typeToSkip
    }
		// 排除序列化属性
    override fun shouldSkipField(f: FieldAttributes): Boolean {
        return f.getAnnotation(MyAnnotation::class.java) != null
    }
}

fun main() {
    val gson = GsonBuilder()
    // 不对string类型进行序列化，并不对@MyAnnotation标记的属性
        .setExclusionStrategies(MyExclusionStrategy(String::class.java))
    // 对空对象进行序列化
        .serializeNulls()
        .create()
    val src = SampleObjectForTest() 
    val json = gson.toJson(src) // {"longField":1234,"clazzField":null}
    println(json)
}
```



### Json属性重命名

> 简单来说就是json是对对象属性的序列化，其中json与对象的属性对应默认是属性名对应属性名

即如下json对象在反序列化的时候会寻找对象的a,b,c属性。

```json
{
    "a": 1,
    "b": "2",
    "c":'3'
}
```

> 这里**绝对不是鼓励**使用这样**阴间**的field name

```kotlin
data class SerialName(
    @SerializedName("👍")
    val a:Int,
    @SerializedName("😘")
    val b:String,
    @SerializedName("😂")
    val c:Char,
)

fun main() {
    val gson = Gson()
    println(gson.toJson(SerialName(1, "2", '3'))) // {"👍":1,"😘":"2","😂":"3"}
}
```

