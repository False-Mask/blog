---
title: Glide基础使用
date: 2023-04-05 21:51:32
tags:
- glide
---



# Glide



## start up





### 安装



```groovy
plugins {
    //......
    id 'org.jetbrains.kotlin.kapt'
}

dependencies {

    // https://mvnrepository.com/artifact/com.github.bumptech.glide/glide
    implementation("com.github.bumptech.glide:glide:4.15.1")
    kapt("com.github.bumptech.glide:compiler:4.15.1")

	// ......
}
```



### 基础使用



> 加载图片

```java
Glide.with(fragment)
    .load(myUrl)
    .into(imageView);
```



> 取消加载

```java
Glide.with(fragment).clear(imageView);
```





### 自定义request



> Glide提供独立的请求，包含`transformations`,`transitions`,`caching `通常的默认请求可0配置直接使用

```java
Glide.with(fragment)
  .load(myUrl)
  .placeholder(placeholder)
  .fitCenter()
  .into(imageView);
```



> 当然我们也可以进行自定义

```java
RequestOptions sharedOptions = 
    new RequestOptions()
      .placeholder(placeholder)
      .fitCenter();

Glide.with(fragment)
  .load(myUrl)
  .apply(sharedOptions)
  .into(imageView1);
```



### 自定义Target



> Glide不仅支持将`Bitmap`和`View`而且还支持异步装入自定义`Target`



```java
Glide.with(context)
  .load(url)
  .into(new CustomTarget<Drawable>() {
    @Override
    public void onResourceReady(Drawable resource, Transition<Drawable> transition) {
      // Do something with the Drawable here.
    }

    @Override
    public void onLoadCleared(@Nullable Drawable placeholder) {
      // Remove the Drawable provided in onResourceReady from any Views and ensure 
      // no references to it remain.
    }
  });
```



### 后台装入



```java
FutureTarget<Bitmap> futureTarget =
  Glide.with(context)
    .asBitmap()
    .load(url)
    .submit(width, height);
```





## Placeholder



> Glide支持设置3种不同的占位符

- placeholder

  request开始的时候呈现，数据加载完毕后替换为需要加载的数据

  使用

  ```java
  Glide.with(fragment)
    .load(url)
    .placeholder(R.drawable.placeholder)
    .into(view);
  ```

- error

  如果加载过程中发生错误

  使用

  ```java
  Glide.with(fragment)
    .load(url)
    .error(R.drawable.error)
    .into(view);
  ```

- fallback

  当数据为null时呈现

  使用

  ```java
  Glide.with(fragment)
    .load(url)
    .fallback(R.drawable.fallback)
    .into(view);
  ```





## 配置





> Glide大部分的配置可以通过`RequestBuilder`配置

> 相关的配置包括

- Placeholder
- Transformations
- cache strategies
- Component specific options, like encode quality, or decode `Bitmap` configurations



### RequestOptions

> 如果我们想要对一部分内容做抽象的时候，我们可以初始化一个`RequestOptions`对象，并通过apply传入到每一个需要复用的Glide中。

```java
RequestOptions cropOptions = new RequestOptions().centerCrop(context);
...
Glide.with(fragment)
    .load(url)
    .apply(cropOptions)
    .into(imageView);
```





### TransitionOptions



> `TransitionOptions`决定了请求加载完毕以后之后会发生什么。

使用`TransitionOptions`

- View fade in
- Cross fade from placeholder
- No transition

```java
import static com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions.withCrossFade;

Glide.with(fragment)
    .load(url)
    .transition(withCrossFade())
    .into(view);
```



### RequestBuilder



> `RequestBuilder`是request的主干，用于将option和我们所请求的url等信息合并在一起，并开启一个新的加载

使用`RequestBuilder`可以获取

- 加载资源的类型
- url/资源的来源
- 资源加载进的view
- 需要进行配置的`RequestOption`
- 需要进行配置的`TransitionOption`
- `thumbnail`效果的配置



#### 选取资源类型

> 选择bitmap类型

```java
RequestBuilder<Bitmap> requestBuilder = Glide.with(fragment).asBitmap();
```



#### apply配置

```java
RequestBuilder<Drawable> requestBuilder = Glide.with(fragment).asDrawable();
requestBuilder.apply(requestOptions);
requestBuilder.transition(transitionOptions);
```





#### 加载缩略图



> `thumbnail`支持并行开启请求，thumbnail支持本地和远端图片，特别是当缩略图处于Glide缓存内加载会特别迅速

```java
Glide.with(fragment)
  .load(url)
  .thumbnail(
    Glide.with(fragment)
      .load(thumbnailUrl))
  .into(imageView);
```



## Transformations

> Transformatations用于获取一个资源并对资源做变动，通常变动可以是裁剪，过滤或者对一些动画GIF做转换。



内置的Transformations包含

- CenterCrop
- FitCenter
- CircleCrop

> Transformation基础使用

```java
Glide.with(fragment)
  .load(url)
  .fitCenter()
  .into(imageView);
```



```java
Glide.with(this)
    .load(R.drawable.ic_launcher_background)
    .apply(
        RequestOptions()
            .circleCrop()
    )
    .into(binding.ivImage)
```



> Multiple Transformations

```java
Glide.with(fragment)
  .load(url)
  .transform(new MultiTransformation(new FitCenter(), new YourCustomTransformation())
  .into(imageView);
```



```java
Glide.with(fragment)
  .load(url)
  .transform(new FitCenter(), new YourCustomTransformation())
  .into(imageView);
```





> 自定义Transformations

```java
private class MyBitmapTransformation extends BitmapTransformation {

        public MyBitmapTransformation(Context context) {
            super(context);
        }

        @Override
        protected Bitmap transform(BitmapPool pool, Bitmap toTransform, int outWidth, int outHeight) {
            Canvas canvas = new Canvas(toTransform);
            BitmapShader bitmapShader = new BitmapShader(toTransform, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
            int min = Math.min(toTransform.getWidth(), toTransform.getHeight());
            int radius = min / 2;
            RadialGradient radialGradient = new RadialGradient(toTransform.getWidth() / 2 , toTransform.getHeight() / 2, radius, Color.TRANSPARENT, Color.WHITE, Shader.TileMode.CLAMP);
            ComposeShader composeShader = new ComposeShader(bitmapShader, radialGradient, PorterDuff.Mode.SRC_OVER);
            Paint paint = new Paint();
            paint.setShader(composeShader);
            canvas.drawRect(0, 0, toTransform.getWidth(), toTransform.getHeight(), paint);
            return toTransform;
        }

        @Override
        public String getId() {
            return "MyBitmapTransformation";
        }
    }
```



## Targets



> Targets作为请求和请求者的中间者，Targets可以用于负责展示占位符，加载的资源，或是用于决定每一个请求的View宽高，

```java
Glide.with(this)
    .load("")
    .into(object : CustomViewTarget<ImageView, Drawable>() {
        override fun onLoadFailed(errorDrawable: Drawable?) {
            TODO("Not yet implemented")
        }

        override fun onResourceCleared(placeholder: Drawable?) {
            TODO("Not yet implemented")
        }

        override fun onResourceReady(
            resource: Drawable,
            transition: Transition<in Drawable>?
        ) {
            TODO("Not yet implemented")
        }

    })
```



> `ImageView`内有内置的`Target`即——`ImageViewTarget`

```java
Target<Drawable> target = 
  Glide.with(fragment)
    .load(url)
    .into(imageView);
```



### 取消和重用



> `Glide`的into方法会返回一个`Target`对象的实例，当我们复用`Target`进行数据的加载的时候会将以往的`Target`取消

```java
Target<Drawable> target = 
  Glide.with(fragment)
    .load(url)
    .into(new Target<Drawable>() {
      ...
    });
... 
// 加载新的资源，并释放以往的资源
Glide.with(fragment)
  .load(newUrl)
  .into(target);
```



> 清除

```java
Target<Drawable> target = 
  Glide.with(fragment)
    .load(url)
    .into(new Target<Drawable>() {
      ...
    });
... 
// 清除资源
Glide.with(fragment).clear(target);
```





## Transitions



> Transition定义了Glide如何从一个placeholder转变为一个图片的动画特效或者从缩略图到一个全量大学的图片
>
> Transitions通常用于单个请求的转换，而不是横跨多个请求。



> Transition的实例化可以通过`TransitionOptions`声明，并通过RequestBuilder的`transition`方法指定request的transition。

> 默认的有提供`BitmapTransitionOptions`或者`DrawableTransitionOptions`



自定义Transition

- 继承`TransitionFactory`
- 通过`DrawableTransitionOptions#with`方法指定transition



## Configuration



### Application 



> 使用步骤如下

- 只能添加一个`AppGlideModule`
- 添加一个或者更多的`LibraryGlideModule`
- 添加`@GlideModule`注解给`AppGlideModule`和其他的`LibraryGlideModule`
- 添加Glide apt依赖

```java
@GlideModule
public class FlickrGlideModule extends AppGlideModule {
  @Override
  public void registerComponents(Context context, Glide glide, Registry registry) {
    registry.append(Photo.class, InputStream.class, new FlickrModelLoader.Factory());
  }
}
```



#### options

> Glide Application的选项有

- `Memory Cache`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    MemorySizeCalculator calculator = new MemorySizeCalculator.Builder(context)
        .setMemoryCacheScreens(2)
        .build();
      // 设置缓存
    builder.setMemoryCache(new LruResourceCache(calculator.getMemoryCacheSize()));
  }
}
```

- `BitmapPool`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    MemorySizeCalculator calculator = new MemorySizeCalculator.Builder(context)
        .setBitmapPoolScreens(3)
        .build();
    builder.setBitmapPool(new LruBitmapPool(calculator.getBitmapPoolSize()));
  }
}
```

- `DiskCache`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    builder.setDiskCache(new ExternalCacheDiskCacheFactory(context));
  }
}
```

- `Default Request Options`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    builder.setDefaultRequestOptions(
        new RequestOptions()
          .format(DecodeFormat.RGB_565)
          .disallowHardwareBitmaps());
  }
}
```

- `UncaughtThrowableStrategy`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    final UncaughtThrowableStrategy myUncaughtThrowableStrategy = new ...
    builder.setDiskCacheExecutor(newDiskCacheExecutor(myUncaughtThrowableStrategy));
    builder.setResizeExecutor(newSourceExecutor(myUncaughtThrowableStrategy));
  }
}
```

- `Log level`

```java
@GlideModule
public class YourAppGlideModule extends AppGlideModule {
  @Override
  public void applyOptions(Context context, GlideBuilder builder) {
    builder.setLogLevel(Log.DEBUG);
  }
}
```





### Libirary



> `LibraryGlideModule`可以用于注册自定义的组件，例如`ModuleLoader`

- 添加一个或者多个`LibraryGlideModule`
- 添加`@Glide`注解
- 添加apt依赖

```java
@GlideModule
public final class OkHttpLibraryGlideModule extends LibraryGlideModule {
  @Override
  public void registerComponents(Context context, Glide glide, Registry registry) {
    registry.replace(GlideUrl.class, InputStream.class, new OkHttpUrlLoader.Factory());
  }
}
```



### 数据解析



> Glide相关的数据解析分为如下几步

1. Model -> Data (handled by `ModelLoaders`)
2. Data -> Resource (handled by `ResourceDecoders`)
3. Resource -> Transcoded Resource (optional, handled by `ResourceTranscoders`).

> `prepend()`、`append()`、`replace()`方法用于设置GlideModule的尝试顺序
>
> 最先加载的是通过`prepend`设置的`ModuleLoader`或者`ResourceDecorder`

> 再者就是append添加的`ModuleLoader`或者`ResourceDecoder`

> `replace`方法可用于替换内置的`ModuleLoader`或者`ResourceDecoder`



### Conflicts

> 试想假如你现在有一个`GlideModule`定义在你自己的模块里面

> 当我们使用的依赖中也包含`AppGlideModule `的时候这时候可用的`AppGlideModule`就有两个了，超过了最大数，我们称之为冲突

> 我们可以通过`@Excludes`添加冲突时候的排除选项

> 如下我们通过Excludes注解排除了`com.example.unwanted.GlideModule`

```java
@Excludes(com.example.unwanted.GlideModule.class)
@GlideModule
public final class MyAppGlideModule extends AppGlideModule { }
```





### Manifest Parsing



> 早期版本的Glide v3有对Manifest文件进行解析，为了保证向后兼容，新版本也没有对这个特性修改

> 不过我们可以通过AppGlideModule设置是否加载

```java
@GlideModule
public final class MyAppGlideModule extends AppGlideModule {
  @Override
  public boolean isManifestParsingEnabled() {
    return false;
  }
}
```



## Cache缓存



> 默认情况下Glide有如下缓存

1. Active resources 

   > 刚被其他View加载的缓存

2. Memory cache 

   > View虽然不是刚加载的，但是仍然保存在内存中

3. Resource

   > 内存中没有缓存了，但是图片经由Decode，Transform已经写入磁盘

4. Data

   > 前面的缓存均无，查看raw data数据是否在磁盘中

> 前两步是查看缓存是否在内存中（同步且迅速），后两步查看缓存是否在磁盘中（异步且缓慢）。





### Key



> 在Glide 4 所有的Cache Key包含至少两个部分

- 数据模型(Uri,File,Url)，如果使用的是自定义的Model，需要实现`hashCode`或者`equals`方法
- 可选的签名



> 上述1-3部分缓存包含

1. 宽高
2. 可选的`Transformation`
3. 添加的`Options`
4. 请求的数据类型(Bitmap,GIF,其他)



### 缓存配置

- 缓存策略

```java
Glide.with(fragment)
  .load(url)
  .diskCacheStrategy(DiskCacheStrategy.ALL)
  .into(imageView);
```

- 只使用缓存

```java
Glide.with(fragment)
  .load(url)
  .onlyRetrieveFromCache(true)
  .into(imageView);
```

- 跳过缓存

```java
Glide.with(fragment)
  .load(url)
  .skipMemoryCache(true)
  .into(view);
```

or

```java
Glide.with(fragment)
  .load(url)
  .diskCacheStrategy(DiskCacheStrategy.NONE)
  .into(view);
```

- 缓存刷新

```java
Glide.with(yourFragment)
    .load(yourFileDataModel)
    .signature(new ObjectKey(yourVersionMetadata))
    .into(yourImageView);
```

- 资源管理

```java
// 设置缓存的大小
Glide.get(context).setMemoryCategory(MemoryCategory.LOW);
// Or:
Glide.get(context).setMemoryCategory(MemoryCategory.HIGH);
Glide.get(context).setMemoryCategory(MemoryCategory.NORMAL);
```

- 清除Memory

```java
// This method must be called on the main thread.
Glide.get(context).clearMemory();
```

- 清除磁盘缓存

```java
new AsyncTask<Void, Void, Void> {
  @Override
  protected Void doInBackground(Void... params) {
    // This method must be called on a background thread.
    Glide.get(applicationContext).clearDiskCache();
    return null;
  }
}
```



## 总结



Glide 可用的API较多有

- placeholder
- transformation
- transition
- cache
- configuration
- options
  - `RequestOptions`
  - `TransitionOptions`
  - `RequestBuilder`
  - `Component Options`
- target



> 但是上述只有一项是Glide的核心。
>
> 即Bitmap。
>
> - Cache
> - 图片压缩
>
> 别忘了Glide的出现是为了解决图片的问题，**图片太大**占内存，**图片频繁加载**内存抖动。
>
> Cache和图片压缩是为了减少内存的波动，减少GC次数从而提升性能。
