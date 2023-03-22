---
title: ViewModel
date: 2022-05-08 12:58:11
tags:
- android
- jetpack
categories:
- android
---



# viewmodel

> ViewModel作为Android的元老级别的内容，你不知道就out了

> ViewModel的实现主要就是能在activity配置发生变化的时候还能保存值。



## 保存策略

突破点

viewModel的获取

```kotlin
val vm = ViewModelProvider(this).get<LiveDataEventVM>()
```

总是有这样一段代码

```java
public constructor(
    owner: ViewModelStoreOwner
) : this(owner.viewModelStore, defaultFactory(owner), defaultCreationExtras(owner))

public constructor(owner: ViewModelStoreOwner, factory: Factory) : this(
    owner.viewModelStore,
    factory,
    defaultCreationExtras(owner)
```

获取viewmodel的Store owner

```java
public interface ViewModelStoreOwner {
    /**
     * Returns owned {@link ViewModelStore}
     *
     * @return a {@code ViewModelStore}
     */
    @NonNull
    ViewModelStore getViewModelStore();
}
```

```java
public ViewModelStore getViewModelStore() {
    if (getApplication() == null) {
        throw new IllegalStateException("Your activity is not yet attached to the "
                + "Application instance. You can't request ViewModel before onCreate call.");
    }
    ensureViewModelStore();
    return mViewModelStore;
}
```



然而他是获取的上一个配置的

```java
void ensureViewModelStore() {
    // null-> 进行初始化
    if (mViewModelStore == null) {
        // 优先获取上一次残留的
        NonConfigurationInstances nc =
                (NonConfigurationInstances) getLastNonConfigurationInstance();
        if (nc != null) {
            // Restore the ViewModelStore from NonConfigurationInstances
            mViewModelStore = nc.viewModelStore;
        }
        if (mViewModelStore == null) {
            mViewModelStore = new ViewModelStore();
        }
    }
}

 @Nullable
    public Object getLastNonConfigurationInstance() {
        return mLastNonConfigurationInstances != null
                ? mLastNonConfigurationInstances.activity : null;
    }
```

源码的注释给的很详细

> Retrieve the non-configuration instance data that was previously returned by onRetainNonConfigurationInstance(). This will be available from the initial onCreate and onStart calls to the new instance, allowing you to extract any useful dynamic state from the previous instance.



`nRetainNonConfigurationInstance`和`getLastNonConfigurationInstance`是成套的。

`androidx.activity.ComponentActivity.java`

```java
//  用于将ViewModel存入NonConfigurationInstances
public final Object onRetainNonConfigurationInstance() {
    // Maintain backward compatibility.
    Object custom = onRetainCustomNonConfigurationInstance();

    ViewModelStore viewModelStore = mViewModelStore;
    if (viewModelStore == null) {
        // No one called getViewModelStore(), so see if there was an existing
        // ViewModelStore from our last NonConfigurationInstance
        NonConfigurationInstances nc =
                (NonConfigurationInstances) getLastNonConfigurationInstance();
        if (nc != null) {
            viewModelStore = nc.viewModelStore;
        }
    }

    if (viewModelStore == null && custom == null) {
        return null;
    }

    NonConfigurationInstances nci = new NonConfigurationInstances();
    nci.custom = custom;
    nci.viewModelStore = viewModelStore;
    return nci;
}
```



简单来说就是：

getLastNonConfigurationInstance是取上一个的配置信息，这个配置信息是在onCreate的时候传入的。

onRetainNonConfigurationInstance是存放配置信息，这个配置信息是在配置发生变化，要销毁activity的时候存入的。



### onRetainNonConfigurationInstance



调用栈

`performDestroyActivity` (`ActivityThread`)->

​	`retainNonConfigurationInstances` (`Activity`)-> 

 		`onRetainNonConfigurationInstance`->





```java
void performDestroyActivity(ActivityClientRecord r, boolean finishing,
        int configChanges, boolean getNonConfigInstance, String reason) {
    
    // .......
    r.lastNonConfigurationInstances = r.activity.retainNonConfigurationInstances();
    
    
}    
```



```java
NonConfigurationInstances retainNonConfigurationInstances() {
    // activity配置保存
    Object activity = onRetainNonConfigurationInstance();
    // child配置保存
    HashMap<String, Object> children = onRetainNonConfigurationChildInstances();
    // fragment保存
    FragmentManagerNonConfig fragments = mFragments.retainNestedNonConfig();

    // We're already stopped but we've been asked to retain.
    // Our fragments are taken care of but we need to mark the loaders for retention.
    // In order to do this correctly we need to restart the loaders first before
    // handing them off to the next activity.
    mFragments.doLoaderStart();
    mFragments.doLoaderStop(true);
    ArrayMap<String, LoaderManager> loaders = mFragments.retainLoaderNonConfig();

    if (activity == null && children == null && fragments == null && loaders == null
            && mVoiceInteractor == null) {
        return null;
    }
	// 配置信息
    NonConfigurationInstances nci = new NonConfigurationInstances();
    nci.activity = activity;
    nci.children = children;
    nci.fragments = fragments;
    nci.loaders = loaders;
    if (mVoiceInteractor != null) {
        mVoiceInteractor.retainInstance();
        nci.voiceInteractor = mVoiceInteractor;
    }
    return nci;
}
```



### 恢复

> activity在launch Activity的时候，会通过调用attach装入部分参数，其中`mLastNonConfigurationInstances`就是其中一员

```java
final void attach(Context context, ActivityThread aThread,
            Instrumentation instr, IBinder token, int ident,
            Application application, Intent intent, ActivityInfo info,
            CharSequence title, Activity parent, String id,
            NonConfigurationInstances lastNonConfigurationInstances,
            Configuration config, String referrer, IVoiceInteractor voiceInteractor,
            Window window, ActivityConfigCallback activityConfigCallback, IBinder assistToken) {
        attachBaseContext(context);

       	// .......
        mLastNonConfigurationInstances = lastNonConfigurationInstances;
        
    }
```

