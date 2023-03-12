---
title: RxJava之Observable
date: 2023-03-10 18:36:36
tags:
- rxjava3
- android
---



# Observable



## 创建操作符



### just

> 用于依此发送指定的元素

> 1参方法到10参方法

![image-20230311160518373](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230311160518373.png)

```java
Observable.just(1,2,3,4);
```



关于实现分为两类

- 1参

```java
public static <@NonNull T> Observable<T> just(@NonNull T item) {
        Objects.requireNonNull(item, "item is null");
        return RxJavaPlugins.onAssembly(new ObservableJust<>(item));
}
```

```kotlin
public final class ObservableJust<T> extends Observable<T> implements ScalarSupplier<T> {

    private final T value;
    public ObservableJust(final T value) {
        this.value = value;
    }

    @Override
    protected void subscribeActual(Observer<? super T> observer) {
        ScalarDisposable<T> sd = new ScalarDisposable<>(observer, value);
        // 向上订阅
        observer.onSubscribe(sd);
        sd.run();
    }

    @Override
    public T get() {
        return value;
    }
    
    public static final class ScalarDisposable<T>
    extends AtomicInteger
    implements QueueDisposable<T>, Runnable {
        // ......
     
         @Override
        public void run() {
            // 发送一个
            if (get() == START && compareAndSet(START, ON_NEXT)) {
                observer.onNext(value);
                if (get() == ON_NEXT) {
                    lazySet(ON_COMPLETE);
                    observer.onComplete();
                }
            }
        }
        
        
    }  
    
    
}      
```

- 多参

```java
public static <@NonNull T> Observable<T> just(@NonNull T item1, @NonNull T item2) {
    Objects.requireNonNull(item1, "item1 is null");
    Objects.requireNonNull(item2, "item2 is null");

    return fromArray(item1, item2);
}

 public static <@NonNull T> Observable<T> fromArray(@NonNull T... items) {
        Objects.requireNonNull(items, "items is null");
        if (items.length == 0) {
            return empty();
        }
        if (items.length == 1) {
            return just(items[0]);
        }
        return RxJavaPlugins.onAssembly(new ObservableFromArray<>(items));
}
```



```java
public final class ObservableFromArray<T> extends Observable<T> {
    
    public void subscribeActual(Observer<? super T> observer) {
        FromArrayDisposable<T> d = new FromArrayDisposable<>(observer, array);

        observer.onSubscribe(d);

        if (d.fusionMode) {
            return;
        }

        d.run();
    }
    
    static final class FromArrayDisposable<T> extends BasicQueueDisposable<T> { 
     	// ......
        void run() {
            T[] a = array;
            int n = a.length;

            for (int i = 0; i < n && !isDisposed(); i++) {
                T value = a[i];
                if (value == null) {
                    downstream.onError(new NullPointerException("The element at index " + i + " is null"));
                    return;
                }
                downstream.onNext(value);
            }
            if (!isDisposed()) {
                downstream.onComplete();
            }
        }
        
    }    
    
}
```





