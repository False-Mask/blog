---
title: JNI基础
tags:
- java
- jni
date: 2023-12-17 17:57:42
---


# 基础概念



## JNI是什么

> JNI是Java的一种功能接口，全称叫Java Native Interface

## 为什么需要 JNI

> 1. Java 运行是借助 JVM 的，但是 JVM 其实只是一个 C/C++的”应用“（JVM 也需要在计算机上跑）
> 2. 有时候我们可能需要比较底层的调用，比如涉及到 OS 的相关操作，JVM 其实是无法实现的，所以需要 JNI对接 C/C++

![jni](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogjni.png)



# Demo



编程语言中都流行 Hello World，JNI 的 Hello World 是？

笔者是一个 Android/Kotlin 开发者，所以具体 Demo 使用 Kotlin

- Kotlin

```kotlin
class MainActivity : AppCompatActivity() {

  private lateinit var binding: ActivityMainBinding

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    binding = ActivityMainBinding.inflate(layoutInflater)
    setContentView(binding.root)

    // Example of a call to a native method
    binding.sampleText.text = stringFromJNI()
  }
  
  // 如果是 Java 就定义 native 方法 
  external fun stringFromJNI(): String

  // 加载 JNI So
  companion object {
    // Used to load the 'jni_demo' library on application startup.
    init {
      System.loadLibrary("jni_demo")
    }
  }
}
```

- C++

```cpp
#include <jni.h>
#include <string>

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_jni_1demo_MainActivity_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) {
    std::string hello = "Hello from C++";
    return env->NewStringUTF(hello.c_str());
}
```



这个 Demo 内容：

使用 Kotlin 通过 JNI 调用（native 方法） Cpp 方法返回了一个字符串



## 解析



- Kotlin

> 这部分没什么可以分析的，语言特性由 JVM 内部做对接，笔者能力有限。

- Cpp

> 引入了一个 jni.h头文件，调用了函数部分功能

接着我们分析下函数的定义

```cpp
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_jni_1demo_MainActivity_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) {
    // ......
}
```



### external "C"



>  Cpp由于需要支持重载，所以会对函数在编译的时候重命名。然而 C 语言并不支持这个特性也就是说不会对函数进行 rename。



个人以为，这里 extern "C"，可能不是为了兼容 C 与 C 互调，而是为了JNI 在加载的时候能找到相关的函数。



### JNIEXPORT



JNIEXPORT是一个宏定义

```cpp
#define JNIEXPORT  __attribute__ ((visibility ("default")))
```



控制库的可见性

![image-20231216111248882](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231216111248882.png)



### 方法名称



> 值得注意的是 JNI 的方法名称是 Java\_包名\_方法名称



### JNICALL



```cpp
#define JNICALL
```



不知道是什么原因，MacOS 上的 JNICALL 标记的是空的



### 参数列表



```cpp
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_jni_1demo_MainActivity_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) 
```



参数列表中会强行塞入两个参数

- JNIEnv

> 方法的 JNI 环境信息，相当于一个桥梁，或者说是 helper 类

- jobject

> Java 对象和 Cpp 对象是不一样的，内部的差异JNI 底层都自动消除了
>
> Java 的类型和 Cpp 类型有对应的映射关系。后文基础使用会详细讲解
>
> 而 jobject 映射的就是 Java 的 Object，Kotlin 的 Any



### 小结

方法最后会被编译成为

```cpp
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_jni_1demo_MainActivity_stringFromJNI(...)
```



```cpp
extern "C" __attribute__ ((visibility ("default"))) jstring 
Java_com_example_jni_1demo_MainActivity_stringFromJNI(...)
```



所以 JNI方法的定义其实就是稍微复杂点的方法定义。



# 基础使用



## 类型映射



基本数据类型

| JNI 类型 | Java 类型 |
| -------- | --------- |
| jboolean | boolean   |
| jbyte    | byte      |
| jchar    | char      |
| jshort   | short     |
| jint     | int       |
| jlong    | long      |
| jfloat   | float     |
| jdouble  | double    |



引用类型

| JNI 类型      | Java 类型 |
| ------------- | --------- |
| jobject       | Object    |
| jclass        | Class     |
| jstring       | String    |
| jarray        |           |
| jobjectArraty | Object[]  |
| jbooleanArray | boolean[] |
| jbyteArray    | byte[]    |
| jcharArray    | char[]    |
| jshortArray   | short[]   |
| jintArray     | int[]     |
| jlongArray    | long[]    |
| jfloatArray   | float[]   |
| jdoubleArray  | double[]  |
| jthrowable    | Throwable |
| jweak         | 弱引用    |



## 属性访问

> 1. 获取jclass对象
> 2. 获取 jmethodId
> 3. 获取 field



- Kotlin

```kotlin
class MainActivity : AppCompatActivity() {
  
  private val value = "Hello From Java"
  
  // 打印 MainActivity 的 value
  external fun test(): Unit
  // 通过 JNI 获取一个字符串
  external fun stringFromJNI(): String
  
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    binding = ActivityMainBinding.inflate(layoutInflater)
    setContentView(binding.root)

    // Example of a call to a native method
    binding.sampleText.text = stringFromJNI()

    // 测试打印Log
    test()
  }
  
}
```

- JNI

```cpp
extern "C"
JNIEXPORT void JNICALL
Java_com_example_jni_1demo_MainActivity_test(JNIEnv *env, jobject thiz) {

    // activity clz对象
  	// 1. 获取jclass对象
    jclass clz = env->GetObjectClass(thiz);

    // 获取 value 遍历的 fieldId
  	// 2. 获取 jmethodId
    jfieldID jfi = env->GetFieldID(clz, "value", "Ljava/lang/String;");

    // 获取 value
  	// 3. 获取 field
    jstring value = static_cast<jstring>(env->GetObjectField(thiz, jfi));

    // 获取 string 指
    jboolean copy = true;
    const char * jc = env->GetStringUTFChars(value, &copy);
		
    //  Log.e 打印
    ALOGE("%s", jc);
    
}
```



## 方法调用



> 1. 获取jclass 对象
> 2. 获取 jmethod 对象
> 3. 调用 method



- Kotlin

```kotlin
class MainActivity : AppCompatActivity() {
 	fun testFromJni() {
    Log.e("Call-From-JNI", "testFromJni: ")
  } 
  
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // ......

    // 使用 jni 回调 testFromJni
    testMethodCall()
  }
  
}
```



- Cpp

```cpp
extern "C"
JNIEXPORT void JNICALL
Java_com_example_jni_1demo_MainActivity_testMethodCall(JNIEnv *env, jobject thiz) {

    // activity clz 对象
  	// 1. 获取jclass 对象
    jclass clz = env->GetObjectClass(thiz);

    // 获取 方法id
   	// 2. 获取 jmethod 对象
    jmethodID jmi = env->GetMethodID(clz,"testFromJni", "()V");

    // 调用
  	// 3. 调用 method
    env->CallVoidMethod(thiz,jmi);

}
```









## 对象创建



- Way1 通过NewObject

**签名：** `jobject NewObject(jclass clazz, jmethodID methodID, ...);`

**描述：** 在Java堆上创建一个新的对象，调用构造方法。参数以可变数量的参数列表（`...`）的形式传递。



- Way2 通过**NewObjectV**

**签名：** `jobject NewObjectV(jclass clazz, jmethodID methodID, va_list args);`

**描述：** 在Java堆上创建一个新的对象，调用构造方法。与 `NewObject` 类似，但是参数以 `va_list` 的形式传递，可以用于处理可变数量的参数。



- Way3 **NewObjectA**

**签名：** `jobject NewObjectA(jclass clazz, jmethodID methodID, const jvalue *args);`

**描述：** 在Java堆上创建一个新的对象，调用构造方法。与 `NewObject` 类似，但参数以 `jvalue` 结构体数组的形式传递，该结构体可以表示各种Java数据类型。



- Way4 通过AllocObject + 构造方法调用

**签名：**`jobject AllocObject(jclass clazz)`

**描述：** 创建引用，类似于 java 字节码 new，只是创建了对象，但是不会调用构造方法。











 







