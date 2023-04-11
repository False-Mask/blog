---
title: Glide初始化分析
date: 2023-04-10 20:32:23
tags:
- glide
- android
---



# Glide Initial



> Glide的初始化方法比较单一

![image-20230410203418211](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230410203418211.png)



> 无法无法使用
>
> - init
>
>   直接调用初始化，会初始化Glide内的static成员
>
> - get
>
>   初始化并获取Glide的实例
>
> - with
>
>   初始化Glide并依据传入的组件获取绑定响应生命周期的Manager对象，以便后续构建Request。



> 其中最为常用的既是with方法。with基本上包含了init和get方法的所有内容。



![image-20230411215601061](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230411215601061.png)



```java
public static RequestManager with(@NonNull Context context) {
  return getRetriever(context).get(context);
}
```



```java
public static RequestManager with(@NonNull FragmentActivity activity) {
  return getRetriever(activity).get(activity);
}
```



```java
public static RequestManager with(@NonNull Fragment fragment) {
  return getRetriever(fragment.getContext()).get(fragment);
}
```



```java
public static RequestManager with(@NonNull View view) {
  return getRetriever(view.getContext()).get(view);
}
```



## getRetriever

> 获取Retriever

```java
private static RequestManagerRetriever getRetriever(@Nullable Context context) {
  // Context could be null for other reasons (ie the user passes in null), but in practice it will
  // only occur due to errors with the Fragment lifecycle.
  Preconditions.checkNotNull(
      context,
      "You cannot start a load on a not yet attached View or a Fragment where getActivity() "
          + "returns null (which usually occurs when getActivity() is called before the Fragment "
          + "is attached or after the Fragment is destroyed).");
  return Glide.get(context).getRequestManagerRetriever();
}
```



## Glide.get



> 初始化Glide并返回实例

```java
public static Glide get(@NonNull Context context) {
  if (glide == null) {
      // 反射获取类
    GeneratedAppGlideModule annotationGeneratedModule =
        getAnnotationGeneratedGlideModules(context.getApplicationContext());
    synchronized (Glide.class) {
      if (glide == null) {
        checkAndInitializeGlide(context, annotationGeneratedModule);
      }
    }
  }

  return glide;
}
```



> 获取生成的AppGlideModule

```java
private static GeneratedAppGlideModule getAnnotationGeneratedGlideModules(Context context) {
  GeneratedAppGlideModule result = null;
  try {
      // 反射获取
    Class<GeneratedAppGlideModule> clazz =
        (Class<GeneratedAppGlideModule>)
            Class.forName("com.bumptech.glide.GeneratedAppGlideModuleImpl");
      // 反射实例化对象
    result =
        clazz.getDeclaredConstructor(Context.class).newInstance(context.getApplicationContext());
  } catch (ClassNotFoundException e) {
    if (Log.isLoggable(TAG, Log.WARN)) {
      Log.w(
          TAG,
          "Failed to find GeneratedAppGlideModule. You should include an"
              + " annotationProcessor compile dependency on com.github.bumptech.glide:compiler"
              + " in your application and a @GlideModule annotated AppGlideModule implementation"
              + " or LibraryGlideModules will be silently ignored");
    }
    // These exceptions can't be squashed across all versions of Android.
  } catch (InstantiationException e) {
    throwIncorrectGlideModule(e);
  } catch (IllegalAccessException e) {
    throwIncorrectGlideModule(e);
  } catch (NoSuchMethodException e) {
    throwIncorrectGlideModule(e);
  } catch (InvocationTargetException e) {
    throwIncorrectGlideModule(e);
  }
  return result;
}
```



> 初始化Glide

```java
static void checkAndInitializeGlide(
    @NonNull Context context, @Nullable GeneratedAppGlideModule generatedAppGlideModule) {
  // In the thread running initGlide(), one or more classes may call Glide.get(context).
  // Without this check, those calls could trigger infinite recursion.
  if (isInitializing) {
    throw new IllegalStateException(
        "Glide has been called recursively, this is probably an internal library error!");
  }
  isInitializing = true;
  try {
    initializeGlide(context, generatedAppGlideModule);
  } finally {
    isInitializing = false;
  }
}
```



```java
private static void initializeGlide(
    @NonNull Context context, @Nullable GeneratedAppGlideModule generatedAppGlideModule) {
  initializeGlide(context, new GlideBuilder(), generatedAppGlideModule);
}
```



```java
private static void initializeGlide(
    @NonNull Context context,
    @NonNull GlideBuilder builder,
    @Nullable GeneratedAppGlideModule annotationGeneratedModule) {
  Context applicationContext = context.getApplicationContext();
  List<GlideModule> manifestModules = Collections.emptyList();
    // 初始化配置解析对象
  if (annotationGeneratedModule == null || annotationGeneratedModule.isManifestParsingEnabled()) {
    manifestModules = new ManifestParser(applicationContext).parse();
  }

  if (annotationGeneratedModule != null
      && !annotationGeneratedModule.getExcludedModuleClasses().isEmpty()) {
    Set<Class<?>> excludedModuleClasses = annotationGeneratedModule.getExcludedModuleClasses();
    Iterator<GlideModule> iterator = manifestModules.iterator();
    while (iterator.hasNext()) {
      GlideModule current = iterator.next();
      if (!excludedModuleClasses.contains(current.getClass())) {
        continue;
      }
      if (Log.isLoggable(TAG, Log.DEBUG)) {
        Log.d(TAG, "AppGlideModule excludes manifest GlideModule: " + current);
      }
      iterator.remove();
    }
  }
 	// 打印manifest声明的module
  if (Log.isLoggable(TAG, Log.DEBUG)) {
    for (GlideModule glideModule : manifestModules) {
      Log.d(TAG, "Discovered GlideModule from manifest: " + glideModule.getClass());
    }
  }
	
  RequestManagerRetriever.RequestManagerFactory factory =
      annotationGeneratedModule != null
          ? annotationGeneratedModule.getRequestManagerFactory()
          : null;
  builder.setRequestManagerFactory(factory);
    // 配置options
  for (GlideModule module : manifestModules) {
    module.applyOptions(applicationContext, builder);
  }
  if (annotationGeneratedModule != null) {
    annotationGeneratedModule.applyOptions(applicationContext, builder);
  }
    // 构建Glide对象
  Glide glide = builder.build(applicationContext, manifestModules, annotationGeneratedModule);
    // 注册逐渐回调（lowMemory，configurationChange）
  applicationContext.registerComponentCallbacks(glide);
  Glide.glide = glide;
}
```



## componentCallback

> 注册组件的回调（lowMemory，configurationChange）

```java
@Override
public void onConfigurationChanged(Configuration newConfig) {
  // Do nothing.
}

@Override
public void onLowMemory() {
  clearMemory();
}

public void clearMemory() {
    // Engine asserts this anyway when removing resources, fail faster and consistently
    Util.assertMainThread();
    // memory cache needs to be cleared before bitmap pool to clear re-pooled Bitmaps too. See #687.
    memoryCache.clearMemory();
    bitmapPool.clearMemory();
    arrayPool.clearMemory();
}
```



## Glide实例创建



```java
Glide build(
    @NonNull Context context,
    List<GlideModule> manifestModules,
    AppGlideModule annotationGeneratedGlideModule) {
    // 默认的线程池
  if (sourceExecutor == null) {
    sourceExecutor = GlideExecutor.newSourceExecutor();
  }

  if (diskCacheExecutor == null) {
    diskCacheExecutor = GlideExecutor.newDiskCacheExecutor();
  }

  if (animationExecutor == null) {
    animationExecutor = GlideExecutor.newAnimationExecutor();
  }

  if (memorySizeCalculator == null) {
    memorySizeCalculator = new MemorySizeCalculator.Builder(context).build();
  }

  if (connectivityMonitorFactory == null) {
    connectivityMonitorFactory = new DefaultConnectivityMonitorFactory();
  }
	// bitmap缓存池
  if (bitmapPool == null) {
    int size = memorySizeCalculator.getBitmapPoolSize();
      // 有缓存
    if (size > 0) {
      bitmapPool = new LruBitmapPool(size);
    } else { // 无缓冲
      bitmapPool = new BitmapPoolAdapter();
    }
  }
	// 缓存
  if (arrayPool == null) {
    arrayPool = new LruArrayPool(memorySizeCalculator.getArrayPoolSizeInBytes());
  }

  if (memoryCache == null) {
    memoryCache = new LruResourceCache(memorySizeCalculator.getMemoryCacheSize());
  }

  if (diskCacheFactory == null) {
    diskCacheFactory = new InternalCacheDiskCacheFactory(context);
  }
	// 
  if (engine == null) {
    engine =
        new Engine(
            memoryCache,
            diskCacheFactory,
            diskCacheExecutor,
            sourceExecutor,
            GlideExecutor.newUnlimitedSourceExecutor(),
            animationExecutor,
            isActiveResourceRetentionAllowed);
  }

  if (defaultRequestListeners == null) {
    defaultRequestListeners = Collections.emptyList();
  } else {
    defaultRequestListeners = Collections.unmodifiableList(defaultRequestListeners);
  }

  GlideExperiments experiments = glideExperimentsBuilder.build();
  RequestManagerRetriever requestManagerRetriever =
      new RequestManagerRetriever(requestManagerFactory, experiments);

  return new Glide(
      context,
      engine,
      memoryCache,
      bitmapPool,
      arrayPool,
      requestManagerRetriever,
      connectivityMonitorFactory,
      logLevel,
      defaultRequestOptionsFactory,
      defaultTransitionOptions,
      defaultRequestListeners,
      manifestModules,
      annotationGeneratedGlideModule,
      experiments);
}
```



## 总结



> 自此Glide初始化已经完成，可以发现主要对Executors、Engine、BitmapPool、ArrayPool等配置进行初始化。
