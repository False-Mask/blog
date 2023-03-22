---
title: Lifecycle
date: 2022-05-05 19:57:29
tags:
- android
- jetpack
categories:
- android
---





# Lifecycle



Lifecycle不是什么奇怪的的东西，就是一个`Lifecycle-aware components`



![image-20230322121343597](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322121343597.png)



lifecycle中有三个东西，viewmodel，livedata，lifecycle，本文着重分析lifecycle。

![image-20230322121503307](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322121503307.png)

即

```
androidx.lifecycle:lifecycle-runtime
```





## 具体分析

> 项目依赖结构

![image-20230322122421034](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322122421034.png)





由于库的代码不多，就先直接从库的源码开始。

少的可怜的runtime

![image-20230322121811958](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322121811958.png)



一共就4个类

- LifecycleRegistry

  > An implementation of Lifecycle that can handle multiple observers.
  > It is used by Fragments and Support Library Activities. You can also directly use it if you have a custom LifecycleOwner.
  >
  > Lifecycle的实现类，用于处理监听者。
  >
  > 它主要是用于Fragment和一些Activity，我们也可以直接使用它，如果我们有自定义的LifecycleOwner（也就是说如果我们有一个组件需要自定义生命周期，可以考虑使用它）

- ~~LifecycleRegistryOwner~~ （Deprecated）

  > Deprecated
  > Use androidx.appcompat.app.AppCompatActivity which extends LifecycleOwner, so there are no use cases for this class.
  >
  > 考虑使用AppCompatActivity，它实现了LifecycOwne的接口

- ReportFragment

  > Internal class that dispatches initialization events..
  >
  > 如果查看类结构会发现，它就是一个Fragment。
  >
  > 它用于监听和分发Event的。

- ViewTreeLifecycleOwner

  > Accessors for finding a view tree-local LifecycleOwner that reports the lifecycle for the given view
  >
  > 简单来说就是为view设置lifecycleOwner



common呢，稍微多一点



![image-20230322122458709](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322122458709.png)



但是呢好像基本上都是internal，内部使用的。只有几个稍微用得稍微多点，比如LifecycleOwner，LifecycleObserver，LifecycleEventObservert这些。





## activity周期回调

关于lifecycle，从activity的lifecycle为切入点。

- lifecycle获取

```kotlin
private final LifecycleRegistry mLifecycleRegistry = new LifecycleRegistry(this);


@NonNull
@Override
public Lifecycle getLifecycle() {
    return mLifecycleRegistry;
}
```

- lifecycle的状态更新

lifecycle内部只有一个成员变量来表征组件目前所处的生命周期，并没有什么特殊的地方，所以说，lifecycle的状态偏移实则还是需要一个生命周期组件在对应的生命周期去调用。那是在什么时候调用呢？

```java
protected void onCreate(@Nullable Bundle savedInstanceState) {
    // Restore the Saved State first so that it is available to
    // OnContextAvailableListener instances
    mSavedStateRegistryController.performRestore(savedInstanceState);
    mContextAwareHelper.dispatchOnContextAvailable(this);
    super.onCreate(savedInstanceState);
    ReportFragment.injectIfNeededIn(this);
    if (BuildCompat.isAtLeastT()) {
        mOnBackPressedDispatcher.setOnBackInvokedDispatcher(
                Api33Impl.getOnBackInvokedDispatcher(this)
        );
    }
    if (mContentLayoutId != 0) {
        setContentView(mContentLayoutId);
    }
}
```

代码好像不多，但是就是其中毫不起眼的一行代码完成了生命周期的监听。

```java
ReportFragment.injectIfNeededIn(this);
```

它干了什么?

也就是往Activity里面注入了fragment而已。

它先会通过fragmentManager依据tag

“androidx.lifecycle.LifecycleDispatcher.report_fragment_tag”去那fragment如果拿到了，那就什么都不做，如果没拿到就往里面注入一个fragment。

```java
public static void injectIfNeededIn(Activity activity) {
    // sdk 29及其以上
    if (Build.VERSION.SDK_INT >= 29) {
        // On API 29+, we can register for the correct Lifecycle callbacks directly
        LifecycleCallbacks.registerIn(activity);
    }
    // sdk 29以下
    // Prior to API 29 and to maintain compatibility with older versions of
    // ProcessLifecycleOwner (which may not be updated when lifecycle-runtime is updated and
    // need to support activities that don't extend from FragmentActivity from support lib),
    // use a framework fragment to get the correct timing of Lifecycle events
    android.app.FragmentManager manager = activity.getFragmentManager();
    if (manager.findFragmentByTag(REPORT_FRAGMENT_TAG) == null) {
        manager.beginTransaction().add(new ReportFragment(), REPORT_FRAGMENT_TAG).commit();
        // Hopefully, we are the first to make a transaction.
        manager.executePendingTransactions();
    }
}
```



> 生命周期回调（SDK 29以上）

```java
@RequiresApi(29)
static class LifecycleCallbacks implements Application.ActivityLifecycleCallbacks {

    static void registerIn(Activity activity) {
        activity.registerActivityLifecycleCallbacks(new LifecycleCallbacks());
    }

    @Override
    public void onActivityCreated(@NonNull Activity activity,
            @Nullable Bundle bundle) {
    }

    @Override
    public void onActivityPostCreated(@NonNull Activity activity,
            @Nullable Bundle savedInstanceState) {
        dispatch(activity, Lifecycle.Event.ON_CREATE);
    }

    @Override
    public void onActivityStarted(@NonNull Activity activity) {
    }

    @Override
    public void onActivityPostStarted(@NonNull Activity activity) {
        dispatch(activity, Lifecycle.Event.ON_START);
    }

    @Override
    public void onActivityResumed(@NonNull Activity activity) {
    }

    @Override
    public void onActivityPostResumed(@NonNull Activity activity) {
        dispatch(activity, Lifecycle.Event.ON_RESUME);
    }

    @Override
    public void onActivityPrePaused(@NonNull Activity activity) {
        dispatch(activity, Lifecycle.Event.ON_PAUSE);
    }

    @Override
    public void onActivityPaused(@NonNull Activity activity) {
    }

    @Override
    public void onActivityPreStopped(@NonNull Activity activity) {
        dispatch(activity, Lifecycle.Event.ON_STOP);
    }

    @Override
    public void onActivityStopped(@NonNull Activity activity) {
    }

    @Override
    public void onActivitySaveInstanceState(@NonNull Activity activity,
            @NonNull Bundle bundle) {
    }

    @Override
    public void onActivityPreDestroyed(@NonNull Activity activity) {
        dispatch(activity, Lifecycle.Event.ON_DESTROY);
    }

    @Override
    public void onActivityDestroyed(@NonNull Activity activity) {
    }
}
```



> sdk 29以下

```java

@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP_PREFIX)
public class ReportFragment extends android.app.Fragment {
    private static final String REPORT_FRAGMENT_TAG = "androidx.lifecycle"
            + ".LifecycleDispatcher.report_fragment_tag";

    public static void injectIfNeededIn(Activity activity) {
        if (Build.VERSION.SDK_INT >= 29) {
            // On API 29+, we can register for the correct Lifecycle callbacks directly
            LifecycleCallbacks.registerIn(activity);
        }
        // Prior to API 29 and to maintain compatibility with older versions of
        // ProcessLifecycleOwner (which may not be updated when lifecycle-runtime is updated and
        // need to support activities that don't extend from FragmentActivity from support lib),
        // use a framework fragment to get the correct timing of Lifecycle events
        android.app.FragmentManager manager = activity.getFragmentManager();
        if (manager.findFragmentByTag(REPORT_FRAGMENT_TAG) == null) {
            manager.beginTransaction().add(new ReportFragment(), REPORT_FRAGMENT_TAG).commit();
            // Hopefully, we are the first to make a transaction.
            manager.executePendingTransactions();
        }
    }

    @SuppressWarnings("deprecation")
    static void dispatch(@NonNull Activity activity, @NonNull Lifecycle.Event event) {
        if (activity instanceof LifecycleRegistryOwner) {
            ((LifecycleRegistryOwner) activity).getLifecycle().handleLifecycleEvent(event);
            return;
        }

        if (activity instanceof LifecycleOwner) {
            Lifecycle lifecycle = ((LifecycleOwner) activity).getLifecycle();
            if (lifecycle instanceof LifecycleRegistry) {
                ((LifecycleRegistry) lifecycle).handleLifecycleEvent(event);
            }
        }
    }

    static ReportFragment get(Activity activity) {
        return (ReportFragment) activity.getFragmentManager().findFragmentByTag(
                REPORT_FRAGMENT_TAG);
    }

    private ActivityInitializationListener mProcessListener;

    private void dispatchCreate(ActivityInitializationListener listener) {
        if (listener != null) {
            listener.onCreate();
        }
    }

    private void dispatchStart(ActivityInitializationListener listener) {
        if (listener != null) {
            listener.onStart();
        }
    }

    private void dispatchResume(ActivityInitializationListener listener) {
        if (listener != null) {
            listener.onResume();
        }
    }

    @Override
    public void onActivityCreated(Bundle savedInstanceState) {
        super.onActivityCreated(savedInstanceState);
        dispatchCreate(mProcessListener);
        dispatch(Lifecycle.Event.ON_CREATE);
    }

    @Override
    public void onStart() {
        super.onStart();
        dispatchStart(mProcessListener);
        dispatch(Lifecycle.Event.ON_START);
    }

    @Override
    public void onResume() {
        super.onResume();
        dispatchResume(mProcessListener);
        dispatch(Lifecycle.Event.ON_RESUME);
    }

    @Override
    public void onPause() {
        super.onPause();
        dispatch(Lifecycle.Event.ON_PAUSE);
    }

    @Override
    public void onStop() {
        super.onStop();
        dispatch(Lifecycle.Event.ON_STOP);
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        dispatch(Lifecycle.Event.ON_DESTROY);
        // just want to be sure that we won't leak reference to an activity
        mProcessListener = null;
    }

    private void dispatch(@NonNull Lifecycle.Event event) {
        if (Build.VERSION.SDK_INT < 29) {
            // Only dispatch events from ReportFragment on API levels prior
            // to API 29. On API 29+, this is handled by the ActivityLifecycleCallbacks
            // added in ReportFragment.injectIfNeededIn
            dispatch(getActivity(), event);
        }
    }

    void setProcessListener(ActivityInitializationListener processListener) {
        mProcessListener = processListener;
    }

    interface ActivityInitializationListener {
        void onCreate();

        void onStart();

        void onResume();
    }

    // this class isn't inlined only because we need to add a proguard rule for it (b/142778206)
    // In addition to that registerIn method allows to avoid class verification failure,
    // because registerActivityLifecycleCallbacks is available only since api 29.
    @RequiresApi(29)
    static class LifecycleCallbacks implements Application.ActivityLifecycleCallbacks {

        static void registerIn(Activity activity) {
            activity.registerActivityLifecycleCallbacks(new LifecycleCallbacks());
        }

        @Override
        public void onActivityCreated(@NonNull Activity activity,
                @Nullable Bundle bundle) {
        }

        @Override
        public void onActivityPostCreated(@NonNull Activity activity,
                @Nullable Bundle savedInstanceState) {
            dispatch(activity, Lifecycle.Event.ON_CREATE);
        }

        @Override
        public void onActivityStarted(@NonNull Activity activity) {
        }

        @Override
        public void onActivityPostStarted(@NonNull Activity activity) {
            dispatch(activity, Lifecycle.Event.ON_START);
        }

        @Override
        public void onActivityResumed(@NonNull Activity activity) {
        }

        @Override
        public void onActivityPostResumed(@NonNull Activity activity) {
            dispatch(activity, Lifecycle.Event.ON_RESUME);
        }

        @Override
        public void onActivityPrePaused(@NonNull Activity activity) {
            dispatch(activity, Lifecycle.Event.ON_PAUSE);
        }

        @Override
        public void onActivityPaused(@NonNull Activity activity) {
        }

        @Override
        public void onActivityPreStopped(@NonNull Activity activity) {
            dispatch(activity, Lifecycle.Event.ON_STOP);
        }

        @Override
        public void onActivityStopped(@NonNull Activity activity) {
        }

        @Override
        public void onActivitySaveInstanceState(@NonNull Activity activity,
                @NonNull Bundle bundle) {
        }

        @Override
        public void onActivityPreDestroyed(@NonNull Activity activity) {
            dispatch(activity, Lifecycle.Event.ON_DESTROY);
        }

        @Override
        public void onActivityDestroyed(@NonNull Activity activity) {
        }
    }
}
```



可以发现在fragment能监听的所有的生命周期都会通过dispatch来调用lifecycle的handleLifecycleEvent。

```java
public void handleLifecycleEvent(@NonNull Lifecycle.Event event) {
    enforceMainThreadIfNeeded("handleLifecycleEvent");
    moveToState(event.getTargetState());
}
```

然后调用moveToState改变lifecycle内部state的状态

```java
private void moveToState(State next) {
    if (mState == next) {
        return;
    }
    mState = next;
    if (mHandlingEvent || mAddingObserverCounter != 0) {
        mNewEventOccurred = true;
        // we will figure out what to do on upper level.
        return;
    }
    mHandlingEvent = true;
    sync();
    mHandlingEvent = false;
}
```







## fragment周期回调

fragment有两个两个生命周期。

- lifecycle

  > 即是fragment本身的生命周期

- viewLifecycleOwner

  > 即是fragment内的rootview的生命周期。



### fragment-lifecycle

![image-20230322123541589](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322123541589.png)

create，start，resume，pause，stop，destroy都有调用对应的dispatch方法。



### fragment-viewLifecycle



![image-20230322124019476](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322124019476.png)



如果点开会发现他会在view对应的生命周期被调用。



其中Viewlifecycle和Lifecycle其实是基本上一致的（除了Create和Destroy事件），ViewTreeLifecycleOwner只有在onCreate和onDestroyView之间可见，其余均处于不可见状态。



## ViewTreeLifecycleOwner

> Accessors for finding a view tree-local LifecycleOwner that reports the lifecycle for the given view.
>
> 一个存储器，用于存储view树中本地的lifecycle。

代码非常短



![image-20230322143919809](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322143919809.png)



就两个方法。

### set

在view中打个tag

```java
public static void set(@NonNull View view, @Nullable LifecycleOwner lifecycleOwner) {
    view.setTag(R.id.view_tree_lifecycle_owner, lifecycleOwner);
}
```



### get

```java
public static LifecycleOwner get(@NonNull View view) {
    LifecycleOwner found = (LifecycleOwner) view.getTag(R.id.view_tree_lifecycle_owner);
    if (found != null) return found;
    ViewParent parent = view.getParent();
    while (found == null && parent instanceof View) {
        final View parentView = (View) parent;
        found = (LifecycleOwner) parentView.getTag(R.id.view_tree_lifecycle_owner);
        parent = parentView.getParent();
    }
    return found;
}
```

逻辑也很简单。

先从传入的view中拿tag。如果没有那就从父view里面去拿。



然后我们看看代码的注解，详细了解以下它的使用时机。

这个ViewTreeLifecycleOwner是用于rootview的设置的。

> Accessors for finding a view tree-local LifecycleOwner that reports the lifecycle for the given view.



因为get的时候他会一层层的往那上拿，这样一定能拿到最顶层。也就是说只要root设置了，那么子view是一定可以拿到的。





### 用途



#### ComponentActivity

```java
@Override
public void setContentView(@SuppressLint({"UnknownNullness", "MissingNullability"}) View view) {
    initViewTreeOwners();
    super.setContentView(view);
}

private void initViewTreeOwners() {
        // Set the view tree owners before setting the content view so that the inflation process
        // and attach listeners will see them already present
        ViewTreeLifecycleOwner.set(getWindow().getDecorView(), this);
        ViewTreeViewModelStoreOwner.set(getWindow().getDecorView(), this);
        ViewTreeSavedStateRegistryOwner.set(getWindow().getDecorView(), this);
        ViewTreeOnBackPressedDispatcherOwner.set(getWindow().getDecorView(), this);
}
```



#### AppCompatActivity

和`ComponentActivity`是几乎一样的。为什么他们会重复？可能是考虑有些人可能会自定义Activity（不基于AppCompatActivity。这也是猜的。）

（不过事实是AppCompatActivity重写了ComponentActivity的方法，所以导致ComponentActivity的initViewTreeOwners不会被调用。）

```java
@Override
public void setContentView(View view) {
    initViewTreeOwners();
    getDelegate().setContentView(view);
}

private void initViewTreeOwners() {
        // Set the view tree owners before setting the content view so that the inflation process
        // and attach listeners will see them already present
        ViewTreeLifecycleOwner.set(getWindow().getDecorView(), this);
        ViewTreeViewModelStoreOwner.set(getWindow().getDecorView(), this);
        ViewTreeSavedStateRegistryOwner.set(getWindow().getDecorView(), this);
        ViewTreeOnBackPressedDispatcherOwner.set(getWindow().getDecorView(), this);
}
```



#### DialogFragment

```java
public void onStart() {
    super.onStart();

    if (mDialog != null) {
        mViewDestroyed = false;
        mDialog.show();
        // Only after we show does the dialog window actually return a decor view.
        View decorView = mDialog.getWindow().getDecorView();
        ViewTreeLifecycleOwner.set(decorView, this);
        ViewTreeViewModelStoreOwner.set(decorView, this);
        ViewTreeSavedStateRegistryOwner.set(decorView, this);
    }
}
```



#### Fragment

```java
void performCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container,
        @Nullable Bundle savedInstanceState) {
    mChildFragmentManager.noteStateNotSaved();
    mPerformedCreateView = true;
    mViewLifecycleOwner = new FragmentViewLifecycleOwner(this, getViewModelStore());
    mView = onCreateView(inflater, container, savedInstanceState);
    if (mView != null) {
        // Initialize the view lifecycle
        mViewLifecycleOwner.initialize();
        // Tell the fragment's new view about it before we tell anyone listening
        // to mViewLifecycleOwnerLiveData and before onViewCreated, so that calls to
        // ViewTree get() methods return something meaningful
        ViewTreeLifecycleOwner.set(mView, mViewLifecycleOwner);
        ViewTreeViewModelStoreOwner.set(mView, mViewLifecycleOwner);
        ViewTreeSavedStateRegistryOwner.set(mView, mViewLifecycleOwner);
        // Then inform any Observers of the new LifecycleOwner
        mViewLifecycleOwnerLiveData.setValue(mViewLifecycleOwner);
    } else {
        if (mViewLifecycleOwner.isInitialized()) {
            throw new IllegalStateException("Called getViewLifecycleOwner() but "
                    + "onCreateView() returned null");
        }
        mViewLifecycleOwner = null;
    }
}
```



## 小结

lifecycle的源码内容不多，难度也不大。lifecycle就是一个带有标准生命周期枚举类的一个bean类，你可以往里面添加观察者，他会在你生命周期发生变化的时候调用对应的回调。

它在api29版本有个分叉。

- api29以下都是通过往activity里面注入一个没有大小的fragment监听生命周期。
- api29及其以上是通过向activity中添加生命周期回调。不过在内容上都是大同小异。



lifecycle库有3个比较重要的角色

- lifecycle

  > 生命周期本身

- lifecycleOwner

  > 生命周期的拥有者。比如Activity，Fragment，Service，Process，或者其他自定义的组件

- lifecyleObserver

  > 生命周期的观察者。一般是一个lambda。可以写入一些生命周期的回调。
