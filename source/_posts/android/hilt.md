---
title: Hilt学习笔记
date: 2021-08-16 16:25:58
tags: 
- android
categories:
- android
---





# Hilt

> Hilt 是 一个依赖注入框架，对此Google并没有强迫我们去使用依赖注入。主要是因为**我们需要**依赖注入，而且对于大型项目更是如此。

假想你有一个项目，里面用了很多的官方框架，第三方框架，对于一些其中的工具的实例你肯定不能在使用的时候直接new。

主要有两个原因

***1.资源浪费***

如果是通用的‘工具’通常情况下是会将其声明为Application作用域下的单例，因为每new一个会消耗大量的资源，比如Retrofit和Gson等。

***2.耦合性***

如果我们在使用的时候自己配置或者new一个工具，当项目的依赖库发生变动的时候，haha，只能一个一个自己去改，小项目倒也没啥，如果是大项目，开篇一搜索就是1w+的引用就问你怕不怕。



> 另外

*依赖注入**不是**Hilt的特殊功能，依赖注入是一种实现依赖关系解耦合的方法。*

说到这里了那就讲讲什么是依赖注入

依赖注入即dependency injection，只要变量是由外部初始化的都叫依赖注入

实现依赖注入有三种

- 构造函数注入：依赖关系是通过 class 构造器提供的。

  像这样

  ```kotlin
  fun main() {
      DI01("1",0)
  }
  
  class DI01(val str:String,val num:Long)
  ```

  通过构造函数注入了str，num

- Setter注入：注入程序用客户端的 setter 方法注入依赖项。

  这样就对DI02进行了set注入

  ```kotlin
  fun main() {
      val dI01 = DI01("1", 0)
      DI02().dI01 = dI01
  }
  
  class DI02(
  ) {
      lateinit var dI01: DI01
  }
  
  class DI01(val str:String,val num:Long)
  ```

- 接口注入：依赖项提供了一个注入方法，该方法将把依赖项注入到传递给它的任何客户端中。客户端必须实现一个接口，该接口的 setter 方法接收依赖。

  ```kotlin
  fun main() {
      val dI03 = DI03()
      dI03.setDiInterface(Concrete01())
  }
  
  class DI03(){
      var dI03:DIInterface? = null
      fun setDiInterface(dI03:DIInterface){
          this.dI03 = dI03
      }
  }
  
  interface DIInterface{
      fun dI()
  }
  
  class Concrete01():DIInterface{
      override fun dI() {
          println("我是实现类1")
      }
  }
  
  class Concrete02():DIInterface{
      override fun dI() {
          println("我是实现类2")
      }
  
  }
  ```



这样虽然看上去很简单，但是确实使用了依赖注入，那为什么我们不直接使用这个进行依赖注入呢？主要是面对着不同的需求上述的方法虽然能用但是实现起来过于复杂，所以就有了Dagger2，Dagger2由于不容易使用，所以Google开发了Hilt供给我们Android开发者使用。



## Hilt实现依赖注入

注意是Hilt实现依赖注入，不是只有Hilt才能实现依赖注入，我们用Hilt是因为它方便，它是专注于Android的静态依赖注入框架。

### 1.Hilt能注入哪些Android类

- `Application`
- `ViewModel`
- `Activity`
- `Fragment`
- `View`
- `Service`
- `BroadcastReceiver`

热血沸腾了有没有。

但是注入这些类其实也是由一定的限制的

![image-20210816175056607](https://gitee.com/False_Mask/pics/raw/master/PicsAndGifs/image-20210816175056607.png)

我们如果使用@AndroidEntryPoint注解，我们还得对它依赖的Android组件加上注解。

比如我使用Activity，我就必须对Activity所依赖的Application加上注解。

如果我使用Fragment我就必须对所依赖的Activity和Application加上注解。

如果我使用View那......Fragment，Activity，Application......。

除此之外还有几个注意点

- 对于Activity只支持ComponentActivity和它的子类比如ComponentActivity和AppCompatActivity就行，Activity就不行了。
- 对于Fragment只支持 `androidx.Fragment`.以及他的子类
- 而且不支持retained fragments.

这个retained fragments其实也是fragment只不过做了一个设置

![image-20210816175806412](https://gitee.com/False_Mask/pics/raw/master/PicsAndGifs/image-20210816175806412.png)

![image-20210816175829394](https://gitee.com/False_Mask/pics/raw/master/PicsAndGifs/image-20210816175829394.png)

Control whether **a fragment instance is retained across Activity re-creation** (**such as from a configuration change**). If set, the fragment lifecycle will be slightly different when an activity is recreated:

不过这个Fragment方法已经被遗弃鸟，由于它的生命周期发生了细微的变化。

![image-20210816180030865](https://gitee.com/False_Mask/pics/raw/master/PicsAndGifs/image-20210816180030865.png)

推荐使用ViewModel替换



### 2.关于Hilt的一些注入的注解初步了解

#### 1).@AndroidEntryPoint

这个注解标注的是Android的类，他会生成一些Hilt的组件帮我们实现依赖的注入。

#### 2).@Inject

标注需要注入的内容，只有标注后Hilt才会知道哪个类需要注入，然后对注入的类进行一系列的操作。

**Note:** Fields injected by Hilt cannot be private. Attempting to inject a private field with Hilt results in a compilation error.

需要注入的类不能是private，否者编译期间就会报错。



Classes that Hilt injects can have other base classes that also use injection. Those classes don't need the `@AndroidEntryPoint` annotation if they're abstract.

如果父类使用了Hilt的注入，而且子类不是抽象的那么就可以不适用@AndroidEntryPoint注入。

### 3.定义Hilt注入的绑定关系

注入一个变量的过程中需要new一个变量，但是这个变量如何提供我们并不能忽略，因为Hilt它是人写的，他也不知道你到底要做啥，所以**我们在注入过程中需要提供变量如何创建**。比如我注入一个User类，我就必须提供User类的创建方法，然后通过对应的注解“暗示”Hilt。**Hilt是用来解耦合的，不是用来自动创建变量的，所以Hilt不能帮我们简化变量的创建，而且人家的定位也不是简化变量的创建**。

比如下面这样这样是在暗示Hilt通过构造函数来创建AnalyticsAdapter

```kotlin
class AnalyticsAdapter @Inject constructor(
  private val service: AnalyticsService
) { ... }
```



### 4.Hilt的Module

有的时候构造函数是无法直接创建变量的，所以就有了Module

@Module注解的类是提供类创建方法的一个类，也就是里面包含一些方法，这些方法是用来在注入过程中创建变量的。

除此之外还有一个@InstallIn注解这个表示我们将Module装载到哪里去



### 5.使用@Binds注入接口

接口注入的写法和前面Module写法类似但是也有少量的区别

```kotlin
interface AnalyticsService {
  fun analyticsMethods()
}

// Constructor-injected, because Hilt needs to know how to
// provide instances of AnalyticsServiceImpl, too.
class AnalyticsServiceImpl @Inject constructor(
  ...
) : AnalyticsService { ... }

@Module
@InstallIn(ActivityComponent::class)
abstract class AnalyticsModule {

  @Binds
  abstract fun bindAnalyticsService(
    analyticsServiceImpl: AnalyticsServiceImpl
  ): AnalyticsService
}
```

@Module注解是一个抽象类，然后@Binds注解一个抽象方法。

这个抽象需要传入抽象方法的具体实现，然后返回值是对应的需要注入的接口。



### 6.使用@Provides注入实例

除了接口外还有一些其他注入类型不能直接注入。

带有@Provides注解的方法会向Hilt提供下列的信息。

- 函数的返回值类型会告知Hilt提供哪个类型的实例
- 函数参数会告诉Hilt该类型的创建需要依赖什么。
- 函数体会告诉Hilt该实例是如何创建出来的。

```kotlin
@Module
@InstallIn(ActivityComponent::class)
object AnalyticsModule {

  @Provides
  fun provideAnalyticsService(
    // Potential dependencies of this type
  ): AnalyticsService {
      return Retrofit.Builder()
               .baseUrl("https://example.com")
               .build()
               .create(AnalyticsService::class.java)
  }
}
```





### 7.为同一类型提供多个绑定

前面的Provides以及Binds直接使用的话会发现只能绑定一个类型，比如我提供了对A类的创建，但是如果A的创建其实不只有一种创建方法那该如何去实现呢？

那就是通过自定义限定符完成。

对于限定符的简单理解可以认为是一种**对于同种类型的依赖注入的区分**。



那我们来看看自定义的限定符长啥样子吧

```kotlin
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AuthInterceptorOkHttpClient

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class OtherInterceptorOkHttpClient
```

我们可以看出限定符其实就是注解。

@Qualifier赋予了我们自己定义的注解限定的能力，@Retention

指定了我们注解的存活期。





然后就将上面的自定义注解加入到我们的Module里对应的的Provides或者Binds上就欧克了

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

  @AuthInterceptorOkHttpClient
  @Provides
  fun provideAuthInterceptorOkHttpClient(
    authInterceptor: AuthInterceptor
  ): OkHttpClient {
      return OkHttpClient.Builder()
               .addInterceptor(authInterceptor)
               .build()
  }

  @OtherInterceptorOkHttpClient
  @Provides
  fun provideOtherInterceptorOkHttpClient(
    otherInterceptor: OtherInterceptor
  ): OkHttpClient {
      return OkHttpClient.Builder()
               .addInterceptor(otherInterceptor)
               .build()
  }
}
```

然后我们在使用的时候就可以通过自定义的注解确定我们选用的是哪一个注入项

```kotlin
// At field injection.
@AndroidEntryPoint
class ExampleActivity: AppCompatActivity() {

  @AuthInterceptorOkHttpClient
  @Inject lateinit var okHttpClient: OkHttpClient
}
```



### 8.Hilt 中的预定义限定符

预限定符就是说Hilt库为我们提供的限定符。

在Android开发中有一个类我们非常常见的，Context，然而使用Contex就面临着生命周期的问题，对于Context我们可以获取的Context有两种Application的Contex，以及Activity的Context.



那对于这样的Context我们如何区分呢。

那就是通过`@ApplicationContext` 和 `@ActivityContext` 限定符。

如下这样写表示使用的是Activity的Context

```kotlin
class AnalyticsAdapter @Inject constructor(
    @ActivityContext private val context: Context,
    private val service: AnalyticsService
) { ... }
```

### 9.Hilt & Android

|          Hilt 组件          |              注入器面向的对象              |
| :-------------------------: | :----------------------------------------: |
|   `ApplicationComponent`    |               `Application`                |
| `ActivityRetainedComponent` |                `ViewModel`                 |
|     `ActivityComponent`     |                 `Activity`                 |
|     `FragmentComponent`     |                 `Fragment`                 |
|       `ViewComponent`       |                   `View`                   |
| `ViewWithFragmentComponent` | 带有 `@WithFragmentBindings` 注释的 `View` |
|     `ServiceComponent`      |                 `Service`                  |



#### 1).组件的作用对象

|          Hilt 组件          |              注入器面向的对象              |
| :-------------------------: | :----------------------------------------: |
|   `ApplicationComponent`    |               `Application`                |
| `ActivityRetainedComponent` |                `ViewModel`                 |
|     `ActivityComponent`     |                 `Activity`                 |
|     `FragmentComponent`     |                 `Fragment`                 |
|       `ViewComponent`       |                   `View`                   |
| `ViewWithFragmentComponent` | 带有 `@WithFragmentBindings` 注释的 `View` |
|     `ServiceComponent`      |                 `Service`                  |



#### 2).组件的生命周期

|         生成的组件          |         创建时机         | 销毁时机                  |
| :-------------------------: | :----------------------: | :------------------------ |
|   `ApplicationComponent`    | `Application#onCreate()` | `Application#onDestroy()` |
| `ActivityRetainedComponent` |  `Activity#onCreate()`   | `Activity#onDestroy()`    |
|     `ActivityComponent`     |  `Activity#onCreate()`   | `Activity#onDestroy()`    |
|     `FragmentComponent`     |  `Fragment#onAttach()`   | `Fragment#onDestroy()`    |
|       `ViewComponent`       |      `View#super()`      | 视图销毁时                |
| `ViewWithFragmentComponent` |      `View#super()`      | 视图销毁时                |
|     `ServiceComponent`      |   `Service#onCreate()`   | `Service#onDestroy()`     |

**注意**：`ActivityRetainedComponent` 在配置更改后仍然存在，因此它在第一次调用 `Activity#onCreate()` 时创建，在最后一次调用 `Activity#onDestroy()` 时销毁。

类似于ViewModel的生命周期呢



#### 3).组件的作用域注解

|                 Android 类                 |         生成的组件          |          作用域          |
| :----------------------------------------: | :-------------------------: | :----------------------: |
|               `Application`                |   `ApplicationComponent`    |       `@Singleton`       |
|                `View Model`                | `ActivityRetainedComponent` | `@ActivityRetainedScope` |
|                 `Activity`                 |     `ActivityComponent`     |    `@ActivityScoped`     |
|                 `Fragment`                 |     `FragmentComponent`     |    `@FragmentScoped`     |
|                   `View`                   |       `ViewComponent`       |      `@ViewScoped`       |
| 带有 `@WithFragmentBindings` 注释的 `View` | `ViewWithFragmentComponent` |      `@ViewScoped`       |
|                 `Service`                  |     `ServiceComponent`      |     `@ServiceScoped`     |

这个需要注意的是加上注解以后**只能保证在该组件的生命周期内单例，不加表示每次注入就新创建一个**。**而且你只有两个选择要么加要么不加，而不能将这些注解随意组合**。比如我一个Activity的注入项，我要么就是使用Activity的注解达到Activity作用域内单例，要么就不使用注解，每次注入都新创建。





### 10.在Hilt不支持的类中注入依赖项

之前说过Hilt支持最为常见的Android的类，不过有的时候我们需要在一些“Hilt不支持的类中进行注入”。

```kotlin
class ExampleContentProvider : ContentProvider() {

  @EntryPoint
  @InstallIn(ApplicationComponent::class)
  interface ExampleContentProviderEntryPoint {
    fun analyticsService(): AnalyticsService
  }

  ...
}
class ExampleContentProvider: ContentProvider() {
    ...

  override fun query(...): Cursor {
    val appContext = context?.applicationContext ?: throw IllegalStateException()
    val hiltEntryPoint =
      EntryPointAccessors.fromApplication(appContext, ExampleContentProviderEntryPoint::class.java)

    val analyticsService = hiltEntryPoint.analyticsService()
    ...
  }
}
```

不是很懂但是还是先贴一下，保证知识的完整性
