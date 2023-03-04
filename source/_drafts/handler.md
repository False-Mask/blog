---
title: Android线程通信
tags:
- androidx
---



# Handler 



> Android是支持多线程的，不同线程如何进行通信，底层就是依靠的Handler进行通信





## 结构

跨线程通信需要用到如下类

- Handler

  > 信息的传递者，如果某个线程有通信的需要就需要持有一个Handler对象，由Handler对象完成线程间信息的传递。
  >
  > 同时也是消息的处理者

- Looper

  > 默认情况下的线程是不支持通信的，因为默认情况线程是顺序执行，停下来时线程就停止了。而Looper即是对于线程的一层封装让其死循环去寻找事件。

- MessageQueue

  > 事件的容器

- Message

  > 事件实体，包含了信息





## 使用



> Looper准备

```kotlin
Looper.prepare()
```



> handler实例化

```kotlin
val handler = Handler(Looper.myLooper()!!
) {
 // do ....
    true
}
```



> 开启事件循环

```kotlin
Looper.loop()
```





## Android main线程

> Android和所有其他支持多线程的平台一样都是有main线程的

`ActivityThread.java`

```java
public static void main(String[] args) {
	// ......
    
	//准备main线程的looper
    Looper.prepareMainLooper();

    //......
    
   	// 创建handler
    ActivityThread thread = new ActivityThread();
    thread.attach(false, startSeq);

    if (sMainThreadHandler == null) {
        sMainThreadHandler = thread.getHandler();
    }

 	//......

  	// 开启事件循环
    Looper.loop();
	// loop是一个死循环，如果loop执行结束说明程序执行过程中出现了异常
    throw new RuntimeException("Main thread loop unexpectedly exited");
}
```



`Looper.java`

```java
public static void prepareMainLooper() {
    // 准备looper，传入false表明不允许中途退出，main线程挂了app就crash了所以永远不允许退出
    prepare(false);
    // 由于main线程是比较特殊的线程，要供其他所有的线程使用，所以需要保存一份静态实例。
    synchronized (Looper.class) {
        if (sMainLooper != null) {
            throw new IllegalStateException("The main Looper has already been prepared.");
        }
        sMainLooper = myLooper();
    }
}
```





## Handler实现原理



### Looper



#### Looper准备

```java
public static void prepare() {
    prepare(true);
}
```

> 在ThreadLocal中设置一个Looper实例

```java
private static void prepare(boolean quitAllowed) {
    if (sThreadLocal.get() != null) {
        throw new RuntimeException("Only one Looper may be created per thread");
    }
    sThreadLocal.set(new Looper(quitAllowed));
}
```



#### Looper事件循环

```java
public static void loop() {
    // 获取当前线程的looper对象
    final Looper me = myLooper();
    if (me == null) {
        throw new RuntimeException("No Looper; Looper.prepare() wasn't called on this thread.");
    }
    if (me.mInLoop) {
        Slog.w(TAG, "Loop again would have the queued messages be executed"
                + " before this one completed.");
    }
	
    me.mInLoop = true;

    // Make sure the identity of this thread is that of the local process,
    // and keep track of what that identity token actually is.
    Binder.clearCallingIdentity();
    final long ident = Binder.clearCallingIdentity();

    // Allow overriding a threshold with a system prop. e.g.
    // adb shell 'setprop log.looper.1000.main.slow 1 && stop && start'
    final int thresholdOverride =
            SystemProperties.getInt("log.looper."
                    + Process.myUid() + "."
                    + Thread.currentThread().getName()
                    + ".slow", 0);

    me.mSlowDeliveryDetected = false;
	// 死循环loop处理消息
    for (;;) {
        if (!loopOnce(me, ident, thresholdOverride)) {
            return;
        }
    }
}
```

> 提取一次消息

```java
private static boolean loopOnce(final Looper me,
        final long ident, final int thresholdOverride) {
    // 从MessageQueue中获取消息
    Message msg = me.mQueue.next(); // might block
    // 如果消息为null不合理，退出loop
    if (msg == null) {
        // No message indicates that the message queue is quitting.
        return false;
    }

  // ......
    
    try {
        // 将message分发给handler
        msg.target.dispatchMessage(msg);
        if (observer != null) {
            observer.messageDispatched(token, msg);
        }
        dispatchEnd = needEndTime ? SystemClock.uptimeMillis() : 0;
    } 
    //......

    
    // 将msg存入Message池，以便后续使用，避免大量的Message创建
    msg.recycleUnchecked();

    return true;
}
```

### MessageQueue

> 从前面`Looper`的分析可以发现Looper所作的职责很少就是从MessageQueue中取Message并执行，如此往复

> 从`Message`中获取一个Message

> next执行一定会返回一个需要分发非null的`Message`（除非出现异常或者用户退出事件循环）。
>
> 当没有`Message`满足分发条件时会通过native调用阻塞。（防止CPU空转）

#### 消息获取（）

```java
Message next() {
    // 此队列需要native实现，mPtr既是native指针的地址。
    final long ptr = mPtr;
    if (ptr == 0) {
        return null;
    }

    int pendingIdleHandlerCount = -1; // -1 only during first iteration
    int nextPollTimeoutMillis = 0;
    for (;;) {
        if (nextPollTimeoutMillis != 0) {
            Binder.flushPendingCommands();
        }
		// native poll
        nativePollOnce(ptr, nextPollTimeoutMillis);

        synchronized (this) {
            // Try to retrieve the next message.  Return if found.
            final long now = SystemClock.uptimeMillis();
            Message prevMsg = null;
            Message msg = mMessages;
            // 同步消息屏障。
            if (msg != null && msg.target == null) {
                // 寻找之后的第一个异步消息
                do {
                    prevMsg = msg;
                    msg = msg.next;
                } while (msg != null && !msg.isAsynchronous());
            }
            // 消息队列中有消息
            if (msg != null) {
                // 如果时机还不到执行的时候
                if (now < msg.when) {
                    // 计算下一次执行poll操作的时间
                    nextPollTimeoutMillis = (int) Math.min(msg.when - now, Integer.MAX_VALUE);
                } else { // 如果执行时机已到
                    // 阻塞标记
                    mBlocked = false;
              		// 移除msg
                    if (prevMsg != null) {
                        prevMsg.next = msg.next;
                    } else {
                        mMessages = msg.next;
                    }
                    msg.next = null;
                    if (DEBUG) Log.v(TAG, "Returning message: " + msg);
                    msg.markInUse();
                    return msg;
                }
            } else { // 如果没有消息。
                nextPollTimeoutMillis = -1;
            }

            // 处理退出
            if (mQuitting) {
                dispose();
                return null;
            }

            // 第一次处于空闲状态，计算idleHandler个数
            if (pendingIdleHandlerCount < 0
                    && (mMessages == null || now < mMessages.when)) {
                pendingIdleHandlerCount = mIdleHandlers.size();
            }
            // 如果没有idleHandler，阻塞
            if (pendingIdleHandlerCount <= 0) {
                // No idle handlers to run.  Loop and wait some more.
                mBlocked = true;
                continue;
            }
			
            // 如果有idlehandler但是目前还没有装配，
            if (mPendingIdleHandlers == null) {
                mPendingIdleHandlers = new IdleHandler[Math.max(pendingIdleHandlerCount, 4)];
            }
            mPendingIdleHandlers = mIdleHandlers.toArray(mPendingIdleHandlers);
        }

        // Run the idle handlers.
        // 运行idleHandler
        for (int i = 0; i < pendingIdleHandlerCount; i++) {
            final IdleHandler idler = mPendingIdleHandlers[i];
            mPendingIdleHandlers[i] = null; // release the reference to the handler
			
            boolean keep = false;
            try {
                keep = idler.queueIdle();
            } catch (Throwable t) {
                Log.wtf(TAG, "IdleHandler threw exception", t);
            }
			// 依据执行结果判断是否保留
            if (!keep) {
                synchronized (this) {
                    mIdleHandlers.remove(idler);
                }
            }
        }

        // Reset the idle handler count to 0 so we do not run them again.
        pendingIdleHandlerCount = 0;

        // While calling an idle handler, a new message could have been delivered
        // so go back and look again for a pending message without waiting.
        nextPollTimeoutMillis = 0;
    }
}
```



> 流程

![image-20230304004950238](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230304004950238.png)



#### nativePollOnce

```c++
static void android_os_MessageQueue_nativePollOnce(JNIEnv* env, jobject obj,
        jlong ptr, jint timeoutMillis) {
    NativeMessageQueue* nativeMessageQueue = reinterpret_cast<NativeMessageQueue*>(ptr);
    nativeMessageQueue->pollOnce(env, obj, timeoutMillis);
}
```



