---
title: Android线程通信
tags:
- android
- 操作系统
categories:
- android
---



# Handler 



> Android是支持多线程的，不同线程如何进行通信，底层就是依靠的Handler进行通信。
>
> 这里的Handler不是指的Java的Handler，更确切的说是Handler机制。
>
> 熟知的有Java层的Handler，但是被遗忘的有Native 层的Handler。
>
> Java的线程通信事件处理是由Java/Native两层Handler共同协作完成。





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



#### 准备

##### java

`Looper.java`

```java
private static void prepare(boolean quitAllowed) {
        if (sThreadLocal.get() != null) {
            throw new RuntimeException("Only one Looper may be created per thread");
        }
        sThreadLocal.set(new Looper(quitAllowed));
}
```

```java
private Looper(boolean quitAllowed) {
    mQueue = new MessageQueue(quitAllowed);
    mThread = Thread.currentThread();
}
```



> MessageQueue初始化

`MessageQueue.java`

```java
MessageQueue(boolean quitAllowed) {
    mQuitAllowed = quitAllowed;
    mPtr = nativeInit();
}

 private native static long nativeInit();
```



##### native

> native初始化

```C++
static jlong android_os_MessageQueue_nativeInit(JNIEnv* env, jclass clazz) {
    // 创建native 消息队列
    NativeMessageQueue* nativeMessageQueue = new NativeMessageQueue();
    if (!nativeMessageQueue) {
        jniThrowRuntimeException(env, "Unable to allocate native queue");
        return 0;
    }
	
    nativeMessageQueue->incStrong(env);
    return reinterpret_cast<jlong>(nativeMessageQueue);
}
```

> 实例化native 消息队列

```c++
NativeMessageQueue::NativeMessageQueue() :
        mPollEnv(NULL), mPollObj(NULL), mExceptionObj(NULL) {
            // 创建looper
    mLooper = Looper::getForThread();
    if (mLooper == NULL) {
        // 创建looper
        mLooper = new Looper(false);
        Looper::setForThread(mLooper);
    }
}
```

> 创建native looper

```c++
Looper::Looper(bool allowNonCallbacks)
    : mAllowNonCallbacks(allowNonCallbacks),
      mSendingMessage(false),
      mPolling(false),
      mEpollRebuildRequired(false),
      mNextRequestSeq(WAKE_EVENT_FD_SEQ + 1),
      mResponseIndex(0),
      mNextMessageUptime(LLONG_MAX) {
    mWakeEventFd.reset(eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC));
    LOG_ALWAYS_FATAL_IF(mWakeEventFd.get() < 0, "Could not make wake event fd: %s", strerror(errno));
	
    AutoMutex _l(mLock);
    rebuildEpollLocked();
}
```

> 创建epoll

```c++
void Looper::rebuildEpollLocked() {
    // 关闭老的epoll实例
    if (mEpollFd >= 0) {
        mEpollFd.reset();
    }

    // 开辟新的epoll实例
    mEpollFd.reset(epoll_create1(EPOLL_CLOEXEC));
    LOG_ALWAYS_FATAL_IF(mEpollFd < 0, "Could not create epoll instance: %s", strerror(errno));
	// 创建epoll事件
    epoll_event wakeEvent = createEpollEvent(EPOLLIN, WAKE_EVENT_FD_SEQ);
    // 设置事件
    int result = epoll_ctl(mEpollFd.get(), EPOLL_CTL_ADD, mWakeEventFd.get(), &wakeEvent);
    LOG_ALWAYS_FATAL_IF(result != 0, "Could not add wake event fd to epoll instance: %s",
                        strerror(errno));
	// request
    for (const auto& [seq, request] : mRequests) {
        epoll_event eventItem = createEpollEvent(request.getEpollEvents(), seq);

        int epollResult = epoll_ctl(mEpollFd.get(), EPOLL_CTL_ADD, request.fd, &eventItem);
        if (epollResult < 0) {
            ALOGE("Error adding epoll events for fd %d while rebuilding epoll set: %s",
                  request.fd, strerror(errno));
        }
    }
}
```



> 调用过程



`android_os_MessageQueue_nativeInit`->

> 初始化native消息队列

​	`new Looper`->

> 创建native Looper

​		`rebuildEpollLocked`->

> 创建epoll文件描述符

​			`epoll_create`

> 系统调用创建epoll文件描述符









#### 消息获取



##### java

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



##### native

> 根据上述的流程可以发现消息循环的核心过程有一个jni调用，即会通过调用nativePollOnce阻塞调用（防止cpu空转）

```c++
static void android_os_MessageQueue_nativePollOnce(JNIEnv* env, jobject obj,
        jlong ptr, jint timeoutMillis) {
    NativeMessageQueue* nativeMessageQueue = reinterpret_cast<NativeMessageQueue*>(ptr);
    nativeMessageQueue->pollOnce(env, obj, timeoutMillis);
}
```



```c++
void NativeMessageQueue::pollOnce(JNIEnv* env, jobject pollObj, int timeoutMillis) {
    mPollEnv = env;
    mPollObj = pollObj;
    mLooper->pollOnce(timeoutMillis);
    mPollObj = NULL;
    mPollEnv = NULL;

    if (mExceptionObj) {
        env->Throw(mExceptionObj);
        env->DeleteLocalRef(mExceptionObj);
        mExceptionObj = NULL;
    }
}
```



```java
int pollOnce(int timeoutMillis, int* outFd, int* outEvents, void** outData);
    inline int pollOnce(int timeoutMillis) {
        return pollOnce(timeoutMillis, nullptr, nullptr, nullptr);
    }
```



```c++
int Looper::pollOnce(int timeoutMillis, int* outFd, int* outEvents, void** outData) {
    int result = 0;
    for (;;) {
        //.....

        result = pollInner(timeoutMillis);
    }
}
```



```c++
int Looper::pollInner(int timeoutMillis) {
//.....

    // Poll.
    int result = POLL_WAKE;
    mResponses.clear();
    mResponseIndex = 0;

    // We are about to idle.
    mPolling = true;

    struct epoll_event eventItems[EPOLL_MAX_EVENTS];
    // 等待
    int eventCount = epoll_wait(mEpollFd.get(), eventItems, EPOLL_MAX_EVENTS, timeoutMillis);

    // No longer idling.
    mPolling = false;

    // Acquire lock.
    mLock.lock();

    // Rebuild epoll set if needed.
    if (mEpollRebuildRequired) {
        mEpollRebuildRequired = false;
        rebuildEpollLocked();
        goto Done;
    }

    // Check for poll error.
    if (eventCount < 0) {
        if (errno == EINTR) {
            goto Done;
        }
        ALOGW("Poll failed with an unexpected error: %s", strerror(errno));
        result = POLL_ERROR;
        goto Done;
    }

    // Check for poll timeout.
    if (eventCount == 0) {
//......

    for (int i = 0; i < eventCount; i++) {
        const SequenceNumber seq = eventItems[i].data.u64;
        uint32_t epollEvents = eventItems[i].events;
        if (seq == WAKE_EVENT_FD_SEQ) {
            if (epollEvents & EPOLLIN) {
                awoken();
            } else {
                ALOGW("Ignoring unexpected epoll events 0x%x on wake event fd.", epollEvents);
            }
        } else {
            const auto& request_it = mRequests.find(seq);
            if (request_it != mRequests.end()) {
                const auto& request = request_it->second;
                int events = 0;
                if (epollEvents & EPOLLIN) events |= EVENT_INPUT;
                if (epollEvents & EPOLLOUT) events |= EVENT_OUTPUT;
                if (epollEvents & EPOLLERR) events |= EVENT_ERROR;
                if (epollEvents & EPOLLHUP) events |= EVENT_HANGUP;
                mResponses.push({.seq = seq, .events = events, .request = request});
            } else {
                ALOGW("Ignoring unexpected epoll events 0x%x for sequence number %" PRIu64
                      " that is no longer registered.",
                      epollEvents, seq);
            }
        }
    }
Done: ;

    // Invoke pending message callbacks.
    mNextMessageUptime = LLONG_MAX;
    while (mMessageEnvelopes.size() != 0) {
        nsecs_t now = systemTime(SYSTEM_TIME_MONOTONIC);
        const MessageEnvelope& messageEnvelope = mMessageEnvelopes.itemAt(0);
        if (messageEnvelope.uptime <= now) {
            // Remove the envelope from the list.
            // We keep a strong reference to the handler until the call to handleMessage
            // finishes.  Then we drop it so that the handler can be deleted *before*
            // we reacquire our lock.
            { // obtain handler
                sp<MessageHandler> handler = messageEnvelope.handler;
                Message message = messageEnvelope.message;
                mMessageEnvelopes.removeAt(0);
                mSendingMessage = true;
                mLock.unlock();
                handler->handleMessage(message);
            } // release handler

            mLock.lock();
            mSendingMessage = false;
            result = POLL_CALLBACK;
        } else {
            // The last message left at the head of the queue determines the next wakeup time.
            mNextMessageUptime = messageEnvelope.uptime;
            break;
        }
    }

    // Release lock.
    mLock.unlock();

    // Invoke all response callbacks.
    for (size_t i = 0; i < mResponses.size(); i++) {
        Response& response = mResponses.editItemAt(i);
        if (response.request.ident == POLL_CALLBACK) {
            int fd = response.request.fd;
            int events = response.events;
            void* data = response.request.data;
            // Invoke the callback.  Note that the file descriptor may be closed by
            // the callback (and potentially even reused) before the function returns so
            // we need to be a little careful when removing the file descriptor afterwards.
            int callbackResult = response.request.callback->handleEvent(fd, events, data);
            if (callbackResult == 0) {
                AutoMutex _l(mLock);
                removeSequenceNumberLocked(response.seq);
            }

            // Clear the callback reference in the response structure promptly because we
            // will not clear the response vector itself until the next poll.
            response.request.callback.clear();
            result = POLL_CALLBACK;
        }
    }
    return result;
}

```



> 是否你存在这样的疑惑?

> Handler所做的不就只有wait，notify吗 ？为什么需要epoll？在java层使用wait，notify。native使用pthread_wait不就可以了吗？epoll多路复用貌似和设计相悖了，是这样吗？

非也

[link](https://zhuanlan.zhihu.com/p/567982370)



表面上看确实只要wait，notify就够了，但是handler是支持native消息的设置的。也即是native自定义事件的设置，使用epoll实现就会简单高效很多。



`android_os_MessageQueue_nativePollOnce`->

> JNI调用注册

​	`pollOnce`->

> 获取一个事件

​		`pollInner`->

> 内部实现

​			`epoll_wait`->

> 释放时间片，作用有3
>
> - 防止空转浪费资源
> - 为Java层规划等待时间，等待至下一个Java层事件的处理事件
> - 等待Native层事件的到来



#### 消息发送



##### java



> `postAtTime`

```java
public final boolean postAtTime(@NonNull Runnable r, long uptimeMillis) {
   return sendMessageAtTime(getPostMessage(r), uptimeMillis);
}

public final boolean postAtTime(
            @NonNull Runnable r, @Nullable Object token, long uptimeMillis) {
   return sendMessageAtTime(getPostMessage(r, token), uptimeMillis);
}

public boolean sendMessageAtTime(@NonNull Message msg, long uptimeMillis) {
        MessageQueue queue = mQueue;
        if (queue == null) {
            RuntimeException e = new RuntimeException(
                    this + " sendMessageAtTime() called with no mQueue");
            Log.w("Looper", e.getMessage(), e);
            return false;
        }
        return enqueueMessage(queue, msg, uptimeMillis);
}

```

> `postAtFrontQueue`

```java
public final boolean postAtFrontOfQueue(@NonNull Runnable r) {
    return sendMessageAtFrontOfQueue(getPostMessage(r));
}

public final boolean sendMessageAtFrontOfQueue(@NonNull Message msg) {
        MessageQueue queue = mQueue;
        if (queue == null) {
            RuntimeException e = new RuntimeException(
                this + " sendMessageAtTime() called with no mQueue");
            Log.w("Looper", e.getMessage(), e);
            return false;
        }
        return enqueueMessage(queue, msg, 0);
 }
```

> `sendMessageDelayed`

```java
public final boolean sendMessageDelayed(@NonNull Message msg, long delayMillis) {
        if (delayMillis < 0) {
            delayMillis = 0;
        }
        return sendMessageAtTime(msg, SystemClock.uptimeMillis() + delayMillis);
}

 public boolean sendMessageAtTime(@NonNull Message msg, long uptimeMillis) {
        MessageQueue queue = mQueue;
        if (queue == null) {
            RuntimeException e = new RuntimeException(
                    this + " sendMessageAtTime() called with no mQueue");
            Log.w("Looper", e.getMessage(), e);
            return false;
        }
        return enqueueMessage(queue, msg, uptimeMillis);
    }
```

> `postX`

```java
public final boolean post(@NonNull Runnable r) {
   return  sendMessageDelayed(getPostMessage(r), 0);
}

public final boolean postDelayed(
        @NonNull Runnable r, @Nullable Object token, long delayMillis) {
    return sendMessageDelayed(getPostMessage(r, token), delayMillis);
}
public final boolean sendMessageDelayed(@NonNull Message msg, long delayMillis) {
        if (delayMillis < 0) {
            delayMillis = 0;
        }
        return sendMessageAtTime(msg, SystemClock.uptimeMillis() + delayMillis);
    }

```





```java
public final boolean sendEmptyMessage(int what)
{
    return sendEmptyMessageDelayed(what, 0);
}

 public final boolean sendEmptyMessageDelayed(int what, long delayMillis) {
        Message msg = Message.obtain();
        msg.what = what;
        return sendMessageDelayed(msg, delayMillis);
 }

public final boolean sendEmptyMessageDelayed(int what, long delayMillis) {
        Message msg = Message.obtain();
        msg.what = what;
        return sendMessageDelayed(msg, delayMillis);
}

public final boolean sendMessageDelayed(@NonNull Message msg, long delayMillis) {
        if (delayMillis < 0) {
            delayMillis = 0;
        }
        return sendMessageAtTime(msg, SystemClock.uptimeMillis() + delayMillis);
}

public final boolean sendMessageDelayed(@NonNull Message msg, long delayMillis) {
        if (delayMillis < 0) {
            delayMillis = 0;
        }
        return sendMessageAtTime(msg, SystemClock.uptimeMillis() + delayMillis);
}
```



> 经过分析可以知晓
>
> 所有的消息通过通过`enqueueMessage`存入消息队列

```java
private boolean enqueueMessage(@NonNull MessageQueue queue, @NonNull Message msg,
        long uptimeMillis) {
    // 设置target
    msg.target = this;
    msg.workSourceUid = ThreadLocalWorkSource.getUid();
	// 异步消息即加急消息
    if (mAsynchronous) {
        msg.setAsynchronous(true);
    }
    return queue.enqueueMessage(msg, uptimeMillis);
}
```

`MessageQueue.java`

```java
boolean enqueueMessage(Message msg, long when) {
    if (msg.target == null) {
        throw new IllegalArgumentException("Message must have a target.");
    }

    synchronized (this) {
		// 已经被使用抛异常
        if (msg.isInUse()) {
            throw new IllegalStateException(msg + " This message is already in use.");
        }
		// 处理退出
        if (mQuitting) {
            IllegalStateException e = new IllegalStateException(
                    msg.target + " sending message to a Handler on a dead thread");
            Log.w(TAG, e.getMessage(), e);
            msg.recycle();
            return false;
        }
		// 标记为使用状态
        msg.markInUse();
        msg.when = when;
        Message p = mMessages;
        boolean needWake;
        // 如果messageQueue中无消息
        if (p == null || when == 0 || when < p.when) {
            // New head, wake up the event queue if blocked.
            msg.next = p;
            mMessages = msg;
            needWake = mBlocked;
        } else {
            // Inserted within the middle of the queue.  Usually we don't have to wake
            // up the event queue unless there is a barrier at the head of the queue
            // and the message is the earliest asynchronous message in the queue.
            // 如果queue被阻塞并且队首的是同步消息屏障
            // 并且msg是第一个异步消息
            needWake = mBlocked && p.target == null && msg.isAsynchronous();
            Message prev;
            for (;;) {
                prev = p;
                p = p.next;
                // 按照事件先后排序
                if (p == null || when < p.when) {
                    break;
                }
                // 如果有其他的异步消息，不唤醒。
                if (needWake && p.isAsynchronous()) {
                    needWake = false;
                }
            }
            msg.next = p; // invariant: p == prev.next
            prev.next = msg;
        }

        // 唤醒
        if (needWake) {
            // 唤醒
            nativeWake(mPtr);
        }
    }
    return true;
}
```



> wake

```c++
static void android_os_MessageQueue_nativeWake(JNIEnv* env, jclass clazz, jlong ptr) {
    NativeMessageQueue* nativeMessageQueue = reinterpret_cast<NativeMessageQueue*>(ptr);
    nativeMessageQueue->wake();
}
```



```c++
void NativeMessageQueue::wake() {
    mLooper->wake();
}
```



```c++
void Looper::wake() {
    uint64_t inc = 1;
    // 先epoll的wake文件描述符写入内容
    // 这个文件描述符在looper构造函数中初始化，加入epoll
    ssize_t nWrite = TEMP_FAILURE_RETRY(write(mWakeEventFd.get(), &inc, sizeof(uint64_t)));
    if (nWrite != sizeof(uint64_t)) {
        if (errno != EAGAIN) {
            LOG_ALWAYS_FATAL("Could not write wake signal to fd %d (returned %zd): %s",
                             mWakeEventFd.get(), nWrite, strerror(errno));
        }
    }
}
```



##### native

> 添加自定义事件，handler native使用epoll很大一部分原因就是因为这个。

```java
handler
    .looper.queue.addOnFileDescriptorEventListener()
```



```java
public void addOnFileDescriptorEventListener(@NonNull FileDescriptor fd,
        @OnFileDescriptorEventListener.Events int events,
        @NonNull OnFileDescriptorEventListener listener) {
    if (fd == null) {
        throw new IllegalArgumentException("fd must not be null");
    }
    if (listener == null) {
        throw new IllegalArgumentException("listener must not be null");
    }

    synchronized (this) {
        updateOnFileDescriptorEventListenerLocked(fd, events, listener);
    }
}
```



```java
private void updateOnFileDescriptorEventListenerLocked(FileDescriptor fd, int events,
        OnFileDescriptorEventListener listener) {
    // 获取文件描述符
    final int fdNum = fd.getInt$();

    int index = -1;
    // 比对事件监听序列
    FileDescriptorRecord record = null;
    if (mFileDescriptorRecords != null) {
        index = mFileDescriptorRecords.indexOfKey(fdNum);
        if (index >= 0) {
            record = mFileDescriptorRecords.valueAt(index);
            if (record != null && record.mEvents == events) {
                return;
            }
        }
    }
	
    // 事件
    // EVENT_INPUT  = 1
    // EVENT_OUTPUT = 2
    // EVENT_ERROR  = 4
    if (events != 0) {
        // 添加error
        events |= OnFileDescriptorEventListener.EVENT_ERROR;
        // 放入缓存
        if (record == null) {
            if (mFileDescriptorRecords == null) {
                mFileDescriptorRecords = new SparseArray<FileDescriptorRecord>();
            }
            record = new FileDescriptorRecord(fd, events, listener);
            mFileDescriptorRecords.put(fdNum, record);
        } else {
            // 跟新
            record.mListener = listener;
            record.mEvents = events;
            record.mSeq += 1;
        }
        nativeSetFileDescriptorEvents(mPtr, fdNum, events);
    } else if (record != null) {
        record.mEvents = 0;
        mFileDescriptorRecords.removeAt(index);
        nativeSetFileDescriptorEvents(mPtr, fdNum, 0);
    }
}

private native static void nativeSetFileDescriptorEvents(long ptr, int fd, int events);
```



> jni

```c++
static void android_os_MessageQueue_nativeSetFileDescriptorEvents(JNIEnv* env, jclass clazz,
        jlong ptr, jint fd, jint events) {
    NativeMessageQueue* nativeMessageQueue = reinterpret_cast<NativeMessageQueue*>(ptr);
    nativeMessageQueue->setFileDescriptorEvents(fd, events);
}
```



```c++
void NativeMessageQueue::setFileDescriptorEvents(int fd, int events) {
    if (events) {
        int looperEvents = 0;
        if (events & CALLBACK_EVENT_INPUT) {
            looperEvents |= Looper::EVENT_INPUT;
        }
        if (events & CALLBACK_EVENT_OUTPUT) {
            looperEvents |= Looper::EVENT_OUTPUT;
        }
        // 添加文件描述符
        mLooper->addFd(fd, Looper::POLL_CALLBACK, looperEvents,
                sp<WeakLooperCallback>::make(this),
                reinterpret_cast<void*>(events));
    } else {
        mLooper->removeFd(fd);
    }
}
```



```c++
int Looper::addFd(int fd, int ident, int events, const sp<LooperCallback>& callback, void* data) {

    if (!callback.get()) {
        if (! mAllowNonCallbacks) {
            ALOGE("Invalid attempt to set NULL callback but not allowed for this looper.");
            return -1;
        }

        if (ident < 0) {
            ALOGE("Invalid attempt to set NULL callback with ident < 0.");
            return -1;
        }
    } else {
        ident = POLL_CALLBACK;
    }

    { // acquire lock
        AutoMutex _l(mLock);
        // There is a sequence number reserved for the WakeEventFd.
        if (mNextRequestSeq == WAKE_EVENT_FD_SEQ) mNextRequestSeq++;
        const SequenceNumber seq = mNextRequestSeq++;

        Request request;
        request.fd = fd;
        request.ident = ident;
        request.events = events;
        request.callback = callback;
        request.data = data;

        epoll_event eventItem = createEpollEvent(request.getEpollEvents(), seq);
        auto seq_it = mSequenceNumberByFd.find(fd);
        if (seq_it == mSequenceNumberByFd.end()) {
            // 添加事件
            int epollResult = epoll_ctl(mEpollFd.get(), EPOLL_CTL_ADD, fd, &eventItem);
            if (epollResult < 0) {
                ALOGE("Error adding epoll events for fd %d: %s", fd, strerror(errno));
                return -1;
            }
            mRequests.emplace(seq, request);
            mSequenceNumberByFd.emplace(fd, seq);
        } else {
            int epollResult = epoll_ctl(mEpollFd.get(), EPOLL_CTL_MOD, fd, &eventItem);
            if (epollResult < 0) {
                if (errno == ENOENT) {
                    // Tolerate ENOENT because it means that an older file descriptor was
                    // closed before its callback was unregistered and meanwhile a new
                    // file descriptor with the same number has been created and is now
                    // being registered for the first time.  This error may occur naturally
                    // when a callback has the side-effect of closing the file descriptor
                    // before returning and unregistering itself.  Callback sequence number
                    // checks further ensure that the race is benign.
                    //
                    // Unfortunately due to kernel limitations we need to rebuild the epoll
                    // set from scratch because it may contain an old file handle that we are
                    // now unable to remove since its file descriptor is no longer valid.
                    // No such problem would have occurred if we were using the poll system
                    // call instead, but that approach carries other disadvantages.
                    epollResult = epoll_ctl(mEpollFd.get(), EPOLL_CTL_ADD, fd, &eventItem);
                    if (epollResult < 0) {
                        ALOGE("Error modifying or adding epoll events for fd %d: %s",
                                fd, strerror(errno));
                        return -1;
                    }
                    scheduleEpollRebuildLocked();
                } else {
                    ALOGE("Error modifying epoll events for fd %d: %s", fd, strerror(errno));
                    return -1;
                }
            }
            const SequenceNumber oldSeq = seq_it->second;
            mRequests.erase(oldSeq);
            mRequests.emplace(seq, request);
            seq_it->second = seq;
        }
    } // release lock
    return 1;
}

```



> 调用关系

`android_os_MessageQueue_nativeSetFileDescriptorEvents`->

​	`setFileDescriptorEvents`->

​		`addFd`->

​			`epoll_ctl`->





## 总结



- Handler机制分为两层
  - java层
    - android.os.Looper
    - android.os.MessageQueue
  - native层
    - frameworks/base/core/jni/android_os_MessageQueue.cpp
    - system/core/libutils/Looper.cpp
- Java层和Native的消息是不同的
  - Java层的是Message他会被加入到MessageQueue中
  - Native层的消息是一个epoll_event他会被加入到native looper的队列中
- 消息的存取不同
  - Java层的消息是定时的，即每一个消息有一个执行执行，到点了就可以执行
  - Native层的消息并不是定时的，他是随着io而触发的
- Handler的两层实现并非谁替代谁，Native更像是对Java层能力的增强。
- 消息等待是通过epoll_wait实现的，即满足了Java层的定时等待，又实现了Native层的IO事件等待





![handler.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/handler.drawio.png)
