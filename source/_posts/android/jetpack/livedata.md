---
title: LiveData
date: 2022-05-05 19:57:29
tags:
- android
- jetpack
categories:
- android
---





# LiveData

LiveData是什么？live-data即有生命的数据。就实现上来说就是lifecycle+data。给data包了一层lifecycle这样减少了在不可见生命周期使用数据的不安全行为。



## 内容



### lifecycle-livedata

也就3个类

![image-20230322145831601](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322145831601.png)



- ComputableLiveData

  > A LiveData class that can be invalidated & computed when there are active observers.
  > It can be invalidated via invalidate(), which will result in a call to compute() if there are active observers (or when they start observing)
  > This is an internal class for now, might be public if we see the necessity.
  >
  > 一个仅有到生命周期处于可见状态的时候才会回调invalidate。
  >
  > 这是一个内部的class。有必要的时候可以用。

- MediatorLiveData

  > LiveData subclass which may observe other LiveData objects and react on OnChanged events from them.
  >
  > 用于观察livedata的livedata。

- Transformations

  > Transformation methods for LiveData.
  >
  > 内有一些实用的工具类。



### arch-core

![image-20230322145925635](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322145925635.png)

封装的线程池。



### livedata-core

![image-20230322145951503](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230322145951503.png)

这么一看，livedata连10个类都没有。够简单的，

- livedata

  > livedata 本data了

- MutableLiveData

  > mutable

- Observer

  > dddd

只能说dddd。不懂那我也很难给你讲懂。用都不会，看什么源码。





## 文档

> 我说自己其实对于livedata没有想象中那么地熟练。所以学习以前一定还是得看看官方文档说了点啥，

[链接](https://developer.android.google.cn/topic/libraries/architecture/livedata#the_advantages_of_using_livedata)

Livedata的优势

- 确保ui和数据的一致性

  > livedata采用了观察者模式，使得ui和数据绑定在一起。

- 无内存泄漏

  > 观察者绑定到了Lifecycle对象，并到相应的lifecycle消亡的时候会对Observer进行清除。

- 不会因为activity关闭而crash

  > 如果观察者的生命周期处于不活跃的状态，比如activity在后台，它将不会接受activity的任何数据，

- 不需要手动管理生命周期

  > lifecycle内部已经帮我们管理好了

- 兼容activity的配置变化

  > 当activity由于配置变化而重建 的时候，他会立即接受最新的数据。

- 共享资源

  > 可以把System Server用LiveData包一层，然后把LiveData做成一个单例，然后观察者区观察这个值



## 源码分析

> livedata的api比较少。除了observe就没有了。

- observe

  > 传入一个lifecycleOwner，这种observe在livedata发生变化的时候，会检验observer的状态，只有当处于活跃状态的时候才会调用对应的observer。

- observeForever

  > 不需要传入lifecycleOwner，他会认为观察者一直处于活跃状态。也即是是只要值发生了变化就会通知观察者。



### observe 

```kotlin
liveData.observe({ lifecycle }) {
    Log.e("TAG", it)
}
```





点开看源码

```java
public void observe(@NonNull LifecycleOwner owner, @NonNull Observer<? super T> observer) {
    //
    assertMainThread("observe");
    if (owner.getLifecycle().getCurrentState() == DESTROYED) {
        // ignore
        return;
    }
    LifecycleBoundObserver wrapper = new LifecycleBoundObserver(owner, observer);
    ObserverWrapper existing = mObservers.putIfAbsent(observer, wrapper);
    if (existing != null && !existing.isAttachedTo(owner)) {
        throw new IllegalArgumentException("Cannot add the same observer"
                + " with different lifecycles");
    }
    if (existing != null) {
        return;
    }
    owner.getLifecycle().addObserver(wrapper);
}
```



不能说简单，只能说非常简单

1.先对执行的线程进行断言，强制指定为Main线程。

2.然后把传入的observer包装一层，然后放入到livedata的观察者集合里面去（mObservers）

3.如果这个observer已经添加过了那么就不重复添加，否则就往lifecycle中添加observer



#### addObserver

addObserver只有一个实现类，那也就是`androidx.lifecycle.LifecycleRegistry`

先在把observer加入到map里面，

```java
public void addObserver(@NonNull LifecycleObserver observer) {
    enforceMainThreadIfNeeded("addObserver");
    State initialState = mState == DESTROYED ? DESTROYED : INITIALIZED;
    ObserverWithState statefulObserver = new ObserverWithState(observer, initialState);
    ObserverWithState previous = mObserverMap.putIfAbsent(observer, statefulObserver);

    if (previous != null) {
        return;
    }
    LifecycleOwner lifecycleOwner = mLifecycleOwner.get();
    if (lifecycleOwner == null) {
        // it is null we should be destroyed. Fallback quickly
        return;
    }

    boolean isReentrance = mAddingObserverCounter != 0 || mHandlingEvent;
    State targetState = calculateTargetState(observer);
    mAddingObserverCounter++;
    while ((statefulObserver.mState.compareTo(targetState) < 0
            && mObserverMap.contains(observer))) {
        pushParentState(statefulObserver.mState);
        final Event event = Event.upFrom(statefulObserver.mState);
        if (event == null) {
            throw new IllegalStateException("no event up from " + statefulObserver.mState);
        }
        statefulObserver.dispatchEvent(lifecycleOwner, event);
        popParentState();
        // mState / subling may have been changed recalculate
        targetState = calculateTargetState(observer);
    }

    if (!isReentrance) {
        // we do sync only on the top level.
        sync();
    }
    mAddingObserverCounter--;
}
```

紧接着一步步移动到当前lifecycle的state（这个是之前lifecycle没分析的，它不是发送最新的lifecycle状态，而是一步步移动到最新的状态。）

```java
private void sync() {
    LifecycleOwner lifecycleOwner = mLifecycleOwner.get();
    if (lifecycleOwner == null) {
        throw new IllegalStateException("LifecycleOwner of this LifecycleRegistry is already"
                + "garbage collected. It is too late to change lifecycle state.");
    }
    while (!isSynced()) {
        mNewEventOccurred = false;
        // no need to check eldest for nullability, because isSynced does it for us.
        if (mState.compareTo(mObserverMap.eldest().getValue().mState) < 0) {
            backwardPass(lifecycleOwner);
        }
        Map.Entry<LifecycleObserver, ObserverWithState> newest = mObserverMap.newest();
        if (!mNewEventOccurred && newest != null
                && mState.compareTo(newest.getValue().mState) > 0) {
            forwardPass(lifecycleOwner);
        }
    }
    mNewEventOccurred = false;
}
```



然后回调用dispatchEvent，然后DispatchEvent又会调用LifecycEventObserver的onStateChanged方法。

```java
void dispatchEvent(LifecycleOwner owner, Event event) {
    State newState = event.getTargetState();
    mState = min(mState, newState);
    mLifecycleObserver.onStateChanged(owner, event);
    mState = newState;
}
```



也就是说这里会直接调用LiveData中被包裹一层的Observer，即`LifecycleBoundObserver`



#### onStateChanged

`LifecycleBoundObserver`是怎么处理的呢？

```java
public void onStateChanged(@NonNull LifecycleOwner source,
        @NonNull Lifecycle.Event event) {
    Lifecycle.State currentState = mOwner.getLifecycle().getCurrentState();
    if (currentState == DESTROYED) {
        removeObserver(mObserver);
        return;
    }
    Lifecycle.State prevState = null;
    while (prevState != currentState) {
        prevState = currentState;
        activeStateChanged(shouldBeActive());
        currentState = mOwner.getLifecycle().getCurrentState();
    }
}
```

1.拿当前的状态

2.判断当前状态是否是Destroy，如果是就移除观察者

3.然后通过shouldBeActive判断当前lifecycle的状态是否处于活跃状态

4.然后调用activeStateChanged





##### shouldBeActive

很简单

就判断一下是不是start或者resume状态

```java
boolean shouldBeActive() {
    return mOwner.getLifecycle().getCurrentState().isAtLeast(STARTED);
}
```

##### activeStateChanged

```java
void activeStateChanged(boolean newActive) {
            if (newActive == mActive) {
                return;
            }
            // immediately set active state, so we'd never dispatch anything to inactive
            // owner
            mActive = newActive;
            changeActiveCounter(mActive ? 1 : -1);
            if (mActive) {
                dispatchingValue(this);
            }
}
```



如果Active状态改变了就更新它，然后还记录active的次数以及判断是否要往下分发值(处于active状态就分发，否者就不。)



#### 小结

我们根据上面的源码分析能发现一下端倪

- livedata 的 observe实则是往lifecycle中添加observer
- livedata如果切入到active状态（即start或者resume状态）会接受到最新的值，如果不处于active状态，那么也只是添加了lifecycle的监听而已
- livedata的observer会在接受到onDestroy实现的时候自动取消订阅



### observeForever

处了不需要传入lifecycle和一直处于活跃状态外其实是一模一样的。

值得注意的是因为activeStateChange传入的是true，所以它永远不会处于inactive状态，也就是说如果需要取消订阅，需要自己手动取消。

```java
private class AlwaysActiveObserver extends ObserverWrapper {

    AlwaysActiveObserver(Observer<? super T> observer) {
        super(observer);
    }

    @Override
    boolean shouldBeActive() {
        return true;
    }
}
```



### 小结

总的来说

- observeForever

  就是只管把传入的observer塞入到livedata的订阅队列里面去。（因为在定位上来说他就是永久活跃的观察者）

- observer

  这种观察是一种安全的观察，他在observeForever的基础上还加想lifecycle中加入了一个生命周期监听，如果生命周期处于非活跃状态就直接把observer设置为不活跃。如果处于从livedata的观察者队列中移除。



## setValue

好像代码不多欸。

```java
protected void setValue(T value) {
    assertMainThread("setValue");
    mVersion++;
    mData = value;
    dispatchingValue(null);
}
```

做了3件事

- 版本++
- 修改内部的数据
- 分发值(notify观察者)



### dispatchingValue

```java
void dispatchingValue(@Nullable ObserverWrapper initiator) {
    if (mDispatchingValue) {
        mDispatchInvalidated = true;
        return;
    }
    mDispatchingValue = true;
    do {
        mDispatchInvalidated = false;
        if (initiator != null) {
            considerNotify(initiator);
            initiator = null;
        } else {
            for (Iterator<Map.Entry<Observer<? super T>, ObserverWrapper>> iterator =
                    mObservers.iteratorWithAdditions(); iterator.hasNext(); ) {
                considerNotify(iterator.next().getValue());
                if (mDispatchInvalidated) {
                    break;
                }
            }
        }
    } while (mDispatchInvalidated);
    mDispatchingValue = false;
}
```

核心代码只有一行considerNotify

逻辑也就是遍历观察者队列，然后依次调用considerNotify



需要3个条件

```java
private void considerNotify(ObserverWrapper observer) {
    // 1
    if (!observer.mActive) {
        return;
    }
    // 2
    if (!observer.shouldBeActive()) {
        observer.activeStateChanged(false);
        return;
    }
    // 3
    if (observer.mLastVersion >= mVersion) {
        return;
    }
    observer.mLastVersion = mVersion;
    observer.mObserver.onChanged((T) mData);
}
```

1.如果observer不处于活跃状态return

2.二次确认当前状态处于active

3.查看observer中最近一次接受的版本号是否大于等于livedata的版本好，如果大于等于那就直接return，否者触发observer。





## postValue

```java
protected void postValue(T value) {
    boolean postTask;
    synchronized (mDataLock) {
        postTask = mPendingData == NOT_SET;
        mPendingData = value;
    }
    if (!postTask) {
        return;
    }
    ArchTaskExecutor.getInstance().postToMainThread(mPostValueRunnable);
}
```



1.拿同步锁。

2.然后比对mPendingData如果为NOT_SET，就将任务post到主线程，否则就直接return。



### postToMainThread



```java
@Override
public void postToMainThread(Runnable runnable) {
    mDelegate.postToMainThread(runnable);
}
```



加锁，如果mainHandler是空就去创建，否则直接handler.post

```java
public void postToMainThread(Runnable runnable) {
    if (mMainHandler == null) {
        synchronized (mLock) {
            if (mMainHandler == null) {
                mMainHandler = createAsync(Looper.getMainLooper());
            }
        }
    }
    //noinspection ConstantConditions
    mMainHandler.post(runnable);
}
```



最后会在main线程执行这段代码。

```java
private final Runnable mPostValueRunnable = new Runnable() {
    @SuppressWarnings("unchecked")
    @Override
    public void run() {
        Object newValue;
        synchronized (mDataLock) {
            newValue = mPendingData;
            mPendingData = NOT_SET;
        }
        setValue((T) newValue);
    }
};
```



所以到头来postValue也是调用的setValue.





## LiveData的缺点

这可以说是LiveData的痛点了，这部分缺点不是bug，但是却在项目中可能会造成“它就是bug”的错觉。

毕竟，前人植树，后人乘凉。前人挖坑，埋后人。

LiveData的缺点不是因为它代码写的不够好，而是在定位上LiveData不是适合于所有 场景的，所以LiveData之所以有缺陷是由于设计问题。

LiveData一开始在设计的时候可能就只考虑到一点——简单。

因为响应式编程是有门槛的，直接转入Rxjava成本太大，新手们（比如我），又驾驭不了。所以就有了它，简单代表着功能弱，易于上手的同时，牺牲了体系化和，稳定性和实用性。



缺点如下：



### 粘性事件

> 这一点决定了LiveData不适用于事件的订阅。
>
> 也就是生产者消费者的一种模型

假如你有一个需求是这样的，有一个生产者可以生产事件，然后一个消费者来消费事件。

需要强调的是**事件**，他是实时的，也就是说，类似于直播一样，你在直播的时间段内才能看到我直播的内容，过了我直播的时间段那就看不了了。（这里不考虑有回放...懂我意思就好了。）







### 数据丢失

分两个

1.setValue : 当activity处于不可交互状态的时候，observer不会被触发，当activity切换回交互状态的时候，才能接受到livedata的数据，在这两个状态切换的过程中的所有数据都会被丢弃。（这个其实还好。）

2.postValue : postValue底层是通过handler进行的post操作。handler能保证你发送的每一条信息被执行。所以postValue的丢值肯定是livedata自己的问题。所以问题出现在哪？因为livedata在向handler发送第一个消息以后到这个消息被执行的整个过程不会再向handler去post任何信息，而多余的postValue会直接对需要进行修改的值进行更改，这就导致post到主线程的手只会set最新的值。







### 小结



livedata主要的问题就是数据丢失，以及粘性。

数据丢失其实还好，不过对于一些特殊的需求，需要接受到前几个数据状态的情形来说就不是很友好了。

最大的问题就是粘性，因为他在设计的时候就强调了，一直会有值存在，所以只要observer处于active状态，只要observe livedata那么就一定会拿到值（有值的话，没值指的是livedata只是创建了，没有进行任何的setValue和postValue调用，换句话是内部的数据版本号为初值-1）。

这对于事件订阅是毁灭性打击，基本上是不可以用原始的LiveData实现数据订阅的。

因为事件需要保证实时性，（你当然也可以有缓存，但是需要缓存的情况比较少）。

然而如果你使用livedata实现事件订阅，强制性地就有1个缓存。





## 总结

LiveData = Data + Lifecycle

**最核心的就是响应式编程，因为有observer这个东西，所以可以将data的变化映射到ui的变化。**



那为什么叫livedata而不是ObservableData,因为livedata使得数据可以被观察以外还通过给数据绑定一个生命周期确保了数据的安全。

因为livedata的核心是data变化映射到ui的变化。换句话说也是mvvm的核心，数据即ui。

在没有livedata之前，view是生命周期组件独有的，比如activity比如fragment，你不会把textView或者button或者editText暴露给别人使用，你顶多暴露一个set方法。所以在没有livedata之前，大体上view还是安全的，只要你不写太玄幻离奇的代码。

但是在引入livedata以后你的ui虽然是私有的，但是data是暴露的，所以就存在跨生命周期修改ui的风险，ui观察了data，你不知道data是什么时候被谁修改的。这样就很不安全，所以它和lifecycle绑定在一起，这样确保了只有到这个ui处于活跃状态的时候你才能修改，当ui消亡的时候解除订阅关系，让外来者无法修改。减少内存泄漏的风险。



这就是LiveData。



但是LiveData正是由于它是为ui服务的，所以它内部缓存了一个state确保大部分情况下观察者一观察就能拿到值，这样就使得直接使用它完成类似于eventbus这种事件订阅就很难受。



所以：

不要使用LiveData实现事件订阅！！！

不要使用LiveData实现事件订阅！！！

不要使用LiveData实现事件订阅！！！

如果要实现事件订阅请对他进行个性化定义。。 不过官方给过实现方案。SingleLiveEvent。（好像叫这名。



LiveData完。
