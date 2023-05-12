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





## requestManager

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





## request

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





