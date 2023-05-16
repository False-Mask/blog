---
title: Glide Request构建
date: 2023-04-13 00:27:37
tags:
- android
- glide
---



# Glide Request



> Glide在加载图片的第一步既是初始化Glide实例

> 接着就会获取RequestManager，然后初始化一个RequestBuilder构建一个Request，

> 本文会对于Glide的RequestBuilder实例化过程做解析



## begin

> Glide的创建是在Glide.with内部进行的，通过with以后就能得到一个`RequestManager`的实例化对象

```java
Glide.with(this)
```





## RequestManager

> 关于`RequestManager`公开的api如下



- request hook

`addDefaultRequestListener`

> 为所有由该RequestManager构建的Request添加监听。

`applyDefaultRequestOptions`

> 对Request进行默认配置



- 加载任务

`as`

> 进行RequestBuilder的实例化

```java
public <ResourceType> RequestBuilder<ResourceType> as(
    @NonNull Class<ResourceType> resourceClass) {
  return new RequestBuilder<>(glide, this, resourceClass, context);
}
```

`asXX`

```java
public RequestBuilder<Bitmap> asBitmap() {
    return as(Bitmap.class).apply(DECODE_TYPE_BITMAP);
}

public RequestBuilder<GifDrawable> asGif() {
    return as(GifDrawable.class).apply(DECODE_TYPE_GIF);
}

public RequestBuilder<Drawable> asDrawable() {
  return as(Drawable.class);
}

public RequestBuilder<File> asFile() {
    return as(File.class).apply(skipMemoryCacheOf(true));
}

public RequestBuilder<File> downloadOnly() {
    return as(File.class).apply(DOWNLOAD_ONLY_OPTIONS);
}
```



- 其他

`setPauseAllRequestsOnTrimMemoryModerate`

> 在内存不足时暂停所有的请求

`clear`

> 取消Glide任务加载





## RequestBuilder

> Request的配置是通过RequestBuilder进行的，他会承载一些Request的参数信息

- `addListener`
- `listener`
- `load`
- `error`
- `thumbnail`
- `transition`
- `fallback`
- `override`
- `placeholder`
- `transform`
- `centerCrop`

......



## Request是如何被创建的

> Request的创建是由RequestManager开启

> asXXX方法几乎是RequestBuilder创建的唯一途径

> 而asXXX底层又调用了as方法

> Glide默认只支持Bitmap，Gif，File，Drawable类型的配置。

![image-20230516220234895](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230516220234895.png)



> 其中RequestBuilder的创建也很干脆

```java
public <ResourceType> RequestBuilder<ResourceType> as(
    @NonNull Class<ResourceType> resourceClass) {
  return new RequestBuilder<>(glide, this, resourceClass, context);
}
```



```java
protected RequestBuilder(
    @NonNull Glide glide,
    RequestManager requestManager,
    Class<TranscodeType> transcodeClass,
    Context context) {
    // 成员初始化
  this.glide = glide;
  this.requestManager = requestManager;
  this.transcodeClass = transcodeClass;
  this.context = context;
  this.transitionOptions = requestManager.getDefaultTransitionOptions(transcodeClass);
  this.glideContext = glide.getGlideContext();
	// 加入监听
  initRequestListeners(requestManager.getDefaultRequestListeners());
    // 应用默认配置
  apply(requestManager.getDefaultRequestOptions());
}
```





## Request是如何进行配置的



> RequestBuilder使用了建筑者模式，无非就是进行大量参数的配置。
>
> 也就是成员变量的设置



```java
public RequestBuilder<TranscodeType> transition(
    @NonNull TransitionOptions<?, ? super TranscodeType> transitionOptions) {
  if (isAutoCloneEnabled()) {
    return clone().transition(transitionOptions);
  }
  this.transitionOptions = Preconditions.checkNotNull(transitionOptions);
  isDefaultTransitionOptionsSet = false;
  return selfOrThrowIfLocked();
}
```



```java
public T error(@DrawableRes int resourceId) {
  if (isAutoCloneEnabled) {
    return clone().error(resourceId);
  }
  this.errorId = resourceId;
  fields |= ERROR_ID;

  this.errorPlaceholder = null;
  fields &= ~ERROR_PLACEHOLDER;

  return selfOrThrowIfLocked();
}
```



```java
public RequestBuilder<TranscodeType> addListener(
    @Nullable RequestListener<TranscodeType> requestListener) {
  if (isAutoCloneEnabled()) {
    return clone().addListener(requestListener);
  }
  if (requestListener != null) {
    if (this.requestListeners == null) {
      this.requestListeners = new ArrayList<>();
    }
    this.requestListeners.add(requestListener);
  }
  return selfOrThrowIfLocked();
}
```



> 之后不再一一例举

