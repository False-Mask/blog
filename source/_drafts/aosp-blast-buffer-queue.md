---
title: aosp-blast-buffer-queue
tags:
cover:
---
# BLASTBufferQueue原理分析

本文分析基于 Android14.0.0_r73

# 分析入口

```java
mBlastBufferQueue = new BLASTBufferQueue(mTag, mSurfaceControl,
                mSurfaceSize.x, mSurfaceSize.y, mWindowAttributes.format)
```


# 构造函数分析

```java
public BLASTBufferQueue(String name, SurfaceControl sc, int width, int height,
		@PixelFormat.Format int format) {
	this(name, true /* updateDestinationFrame */);
	update(sc, width, height, format);
}
```

## nativeCreate

调用 JNI 方法
```java
public BLASTBufferQueue(String name, boolean updateDestinationFrame) {
	mNativeObject = nativeCreate(name, updateDestinationFrame);
}
```

JNI 方法实现
```java
// android_graphics_BLASTBufferQueue.cpp
static jlong nativeCreate(JNIEnv* env, jclass clazz, jstring jName,
                          jboolean updateDestinationFrame) {
    ScopedUtfChars name(env, jName);
    // 创建 BLASTBufferQueue
    sp<BLASTBufferQueue> queue = new BLASTBufferQueue(name.c_str(), updateDestinationFrame);
    // 累计应用数
    queue->incStrong((void*)nativeCreate);
    // 返回指针
    return reinterpret_cast<jlong>(queue.get());
}
```

创建BLASTBufferQueue对象
```java
BLASTBufferQueue::BLASTBufferQueue(const std::string& name, bool updateDestinationFrame)
      : mSurfaceControl(nullptr),
        mSize(1, 1),
        mRequestedSize(mSize),
        mFormat(PIXEL_FORMAT_RGBA_8888),
        mTransactionReadyCallback(nullptr),
        mSyncTransaction(nullptr),
        mUpdateDestinationFrame(updateDestinationFrame) {
    // 1. 创建 BufferQueue (此处会创建 mProducer, mConsumer)
    createBufferQueue(&mProducer, &mConsumer);
    // since the adapter is in the client process, set dequeue timeout
    // explicitly so that dequeueBuffer will block
    mProducer->setDequeueTimeout(std::numeric_limits<int64_t>::max());

    // safe default, most producers are expected to override this
    mProducer->setMaxDequeuedBufferCount(2);
    // 2. 利用mConsumer创建BLASTBufferItemConsumer
    mBufferItemConsumer = new BLASTBufferItemConsumer(mConsumer,
                                                      GraphicBuffer::USAGE_HW_COMPOSER |
                                                              GraphicBuffer::USAGE_HW_TEXTURE,
                                                      1, false, this);
    // 3. 设置变量值                                                
    static std::atomic<uint32_t> nextId = 0;
    mProducerId = nextId++;
    mName = name + "#" + std::to_string(mProducerId);
    auto consumerName = mName + "(BLAST Consumer)" + std::to_string(mProducerId);
    mQueuedBufferTrace = "QueuedBuffer - " + mName + "BLAST#" + std::to_string(mProducerId);
    mBufferItemConsumer->setName(String8(consumerName.c_str()));
    mBufferItemConsumer->setFrameAvailableListener(this);

    ComposerServiceAIDL::getComposerService()->getMaxAcquiredBufferCount(&mMaxAcquiredBuffers);
    mBufferItemConsumer->setMaxAcquiredBufferCount(mMaxAcquiredBuffers);
    mCurrentMaxAcquiredBufferCount = mMaxAcquiredBuffers;
    mNumAcquired = 0;
    mNumFrameAvailable = 0;

    TransactionCompletedListener::getInstance()->addQueueStallListener(
            [&](const std::string& reason) {
                std::function<void(const std::string&)> callbackCopy;
                {
                    std::unique_lock _lock{mMutex};
                    callbackCopy = mTransactionHangCallback;
                }
                if (callbackCopy) callbackCopy(reason);
            },
            this);

    BQA_LOGV("BLASTBufferQueue created");
}
```


创建 BLASTBufferQueue
```c++
void BLASTBufferQueue::createBufferQueue(sp<IGraphicBufferProducer>* outProducer,
                                         sp<IGraphicBufferConsumer>* outConsumer) {
    LOG_ALWAYS_FATAL_IF(outProducer == nullptr, "BLASTBufferQueue: outProducer must not be NULL");
    LOG_ALWAYS_FATAL_IF(outConsumer == nullptr, "BLASTBufferQueue: outConsumer must not be NULL");

    sp<BufferQueueCore> core(new BufferQueueCore());
    LOG_ALWAYS_FATAL_IF(core == nullptr, "BLASTBufferQueue: failed to create BufferQueueCore");

    sp<IGraphicBufferProducer> producer(new BBQBufferQueueProducer(core, this));
    LOG_ALWAYS_FATAL_IF(producer == nullptr,
                        "BLASTBufferQueue: failed to create BBQBufferQueueProducer");

    sp<BufferQueueConsumer> consumer(new BufferQueueConsumer(core));
    consumer->setAllowExtraAcquire(true);
    LOG_ALWAYS_FATAL_IF(consumer == nullptr,
                        "BLASTBufferQueue: failed to create BufferQueueConsumer");

    *outProducer = producer;
    *outConsumer = consumer;
}
```


### BLASTBufferQueue::createBufferQueue

先创建 BufferQueueCore，基于 BufferQueueCore 对象创建 BBQBufferQueueProducer、BufferQueueConsumer
```c++
void BLASTBufferQueue::createBufferQueue(sp<IGraphicBufferProducer>* outProducer,
                                         sp<IGraphicBufferConsumer>* outConsumer) {
    LOG_ALWAYS_FATAL_IF(outProducer == nullptr, "BLASTBufferQueue: outProducer must not be NULL");
    LOG_ALWAYS_FATAL_IF(outConsumer == nullptr, "BLASTBufferQueue: outConsumer must not be NULL");
	
    sp<BufferQueueCore> core(new BufferQueueCore());
    LOG_ALWAYS_FATAL_IF(core == nullptr, "BLASTBufferQueue: failed to create BufferQueueCore");

    sp<IGraphicBufferProducer> producer(new BBQBufferQueueProducer(core, this));
    LOG_ALWAYS_FATAL_IF(producer == nullptr,
                        "BLASTBufferQueue: failed to create BBQBufferQueueProducer");

    sp<BufferQueueConsumer> consumer(new BufferQueueConsumer(core));
    consumer->setAllowExtraAcquire(true);
    LOG_ALWAYS_FATAL_IF(consumer == nullptr,
                        "BLASTBufferQueue: failed to create BufferQueueConsumer");

    *outProducer = producer;
    *outConsumer = consumer;
}
```


- BufferQueueCore
```c++
// 创建 BufferQueueCore
sp<BufferQueueCore> core(new BufferQueueCore());

// BufferQueueCore 构造函数实现
BufferQueueCore::BufferQueueCore()
      : mMutex(),
        mIsAbandoned(false),
        mConsumerControlledByApp(false),
        mConsumerName(getUniqueName()),
        mConsumerListener(),
        mConsumerUsageBits(0),
        mConsumerIsProtected(false),
        mConnectedApi(NO_CONNECTED_API),
        mLinkedToDeath(),
        mConnectedProducerListener(),
        mBufferReleasedCbEnabled(false),
        mSlots(),
        mQueue(),
        mFreeSlots(),
        mFreeBuffers(),
        mUnusedSlots(),
        mActiveBuffers(),
        mDequeueCondition(),
        mDequeueBufferCannotBlock(false),
        mQueueBufferCanDrop(false),
        mLegacyBufferDrop(true),
        mDefaultBufferFormat(PIXEL_FORMAT_RGBA_8888),
        mDefaultWidth(1),
        mDefaultHeight(1),
        mDefaultBufferDataSpace(HAL_DATASPACE_UNKNOWN),
        mMaxBufferCount(BufferQueueDefs::NUM_BUFFER_SLOTS),
        mMaxAcquiredBufferCount(1),
        mMaxDequeuedBufferCount(1),
        mBufferHasBeenQueued(false),
        mFrameCounter(0),
        mTransformHint(0),
        mIsAllocating(false),
        mIsAllocatingCondition(),
        mAllowAllocation(true),
        mBufferAge(0),
        mGenerationNumber(0),
        mAsyncMode(false),
        mSharedBufferMode(false),
        mAutoRefresh(false),
        mSharedBufferSlot(INVALID_BUFFER_SLOT),
        mSharedBufferCache(Rect::INVALID_RECT, 0, NATIVE_WINDOW_SCALING_MODE_FREEZE,
                           HAL_DATASPACE_UNKNOWN),
        mLastQueuedSlot(INVALID_BUFFER_SLOT),
        mUniqueId(getUniqueId()),
        mAutoPrerotation(false),
        mTransformHintInUse(0) {
    int numStartingBuffers = getMaxBufferCountLocked();
    for (int s = 0; s < numStartingBuffers; s++) {
        mFreeSlots.insert(s);
    }
    for (int s = numStartingBuffers; s < BufferQueueDefs::NUM_BUFFER_SLOTS;
            s++) {
        mUnusedSlots.push_front(s);
    }
}
```


- BBQBufferQueueProducer
```c++
// 1. 创建BBQBufferQueueProducer
sp<IGraphicBufferProducer> producer(new BBQBufferQueueProducer(core, this));

// 2. 调用构造函数
BBQBufferQueueProducer(const sp<BufferQueueCore>& core, wp<BLASTBufferQueue> bbq)
          : BufferQueueProducer(core, false /* consumerIsSurfaceFlinger*/),
            mBLASTBufferQueue(std::move(bbq)) {}
            
BufferQueueProducer::BufferQueueProducer(const sp<BufferQueueCore>& core,
        bool consumerIsSurfaceFlinger) :
    mCore(core),
    mSlots(core->mSlots),
    mConsumerName(),
    mStickyTransform(0),
    mConsumerIsSurfaceFlinger(consumerIsSurfaceFlinger),
    mLastQueueBufferFence(Fence::NO_FENCE),
    mLastQueuedTransform(0),
    mCallbackMutex(),
    mNextCallbackTicket(0),
    mCurrentCallbackTicket(0),
    mCallbackCondition(),
    mDequeueTimeout(-1),
    mDequeueWaitingForAllocation(false) {}
```

- BufferQueueConsumer
```c++
// 1. 创建 BufferQueueConsumer
sp<BufferQueueConsumer> consumer(new BufferQueueConsumer(core));

// 2. 调用构造函数
BufferQueueConsumer::BufferQueueConsumer(const sp<BufferQueueCore>& core) :
    mCore(core),
    mSlots(core->mSlots),
    mConsumerName() {}

BufferQueueConsumer::BufferQueueConsumer(const sp<BufferQueueCore>& core) :
    mCore(core),
    mSlots(core->mSlots),
    mConsumerName() {}
```


### BLASTBufferItemConsumer初始化

BufferItemConsumer是一个 BufferQueue Consumer 的终端，允许客户端访问使用整个 BufferItem。
```c++
// 1. 包裹一层 Consumer
new BLASTBufferItemConsumer(mConsumer,
						  GraphicBuffer::USAGE_HW_COMPOSER |
								  GraphicBuffer::USAGE_HW_TEXTURE,
						  1, false, this);

// 2. 构造函数
BLASTBufferItemConsumer(const sp<IGraphicBufferConsumer>& consumer, uint64_t consumerUsage,
                            int bufferCount, bool controlledByApp, wp<BLASTBufferQueue> bbq)
          : BufferItemConsumer(consumer, consumerUsage, bufferCount, controlledByApp),
            mBLASTBufferQueue(std::move(bbq)),
            mCurrentlyConnected(false),
            mPreviouslyConnected(false) {}
```


## nativeUpdate

```java
// BLASTBufferQueue.java
public void update(SurfaceControl sc, int width, int height, @PixelFormat.Format int format) {
	// 调用 JNI方法
	nativeUpdate(mNativeObject, sc.mNativeObject, width, height, format);
}
```


```c++
// JNI 方法实现
static void nativeUpdate(JNIEnv* env, jclass clazz, jlong ptr, jlong surfaceControl, jlong width,
                         jlong height, jint format) {
    // 将 JNI 传入的参数转为 BLASTBufferQueue
    sp<BLASTBufferQueue> queue = reinterpret_cast<BLASTBufferQueue*>(ptr);
    // 调用 update 方法
    queue->update(reinterpret_cast<SurfaceControl*>(surfaceControl), width, height, format);
}
```



BLASTBufferQueue::update的主要逻辑如下：
1. 更新 SurfaceControl
2. 构建 Transaction
3. 设置 BLASTBufferItemConsumer
4. 调用 Transaction.apply 提交事务

```c++
void BLASTBufferQueue::update(const sp<SurfaceControl>& surface, uint32_t width, uint32_t height,
                              int32_t format) {
    // ......

    std::lock_guard _lock{mMutex};
    // 更新 format
    if (mFormat != format) {
        mFormat = format;
        mBufferItemConsumer->setDefaultBufferFormat(convertBufferFormat(format));
    }
	// 判断 surfaceControl 是否发生变化
    const bool surfaceControlChanged = !SurfaceControl::isSameSurface(mSurfaceControl, surface);
    // ......
    bool applyTransaction = false;

    // 构建 Transaction
    mSurfaceControl = surface;
    SurfaceComposerClient::Transaction t;
    if (surfaceControlChanged) {
        t.setFlags(mSurfaceControl, layer_state_t::eEnableBackpressure,
                   layer_state_t::eEnableBackpressure);
        applyTransaction = true;
    }
    mTransformHint = mSurfaceControl->getTransformHint();
    mBufferItemConsumer->setTransformHint(mTransformHint);
    // ......

    ui::Size newSize(width, height);
    // 设置 Consumer，设置 size
    if (mRequestedSize != newSize) {
        mRequestedSize.set(newSize);
        mBufferItemConsumer->setDefaultBufferSize(mRequestedSize.width, mRequestedSize.height);
        if (mLastBufferInfo.scalingMode != NATIVE_WINDOW_SCALING_MODE_FREEZE) {
            // If the buffer supports scaling, update the frame immediately since the client may
            // want to scale the existing buffer to the new size.
            mSize = mRequestedSize;
            if (mUpdateDestinationFrame) {
                t.setDestinationFrame(mSurfaceControl, Rect(newSize));
                applyTransaction = true;
            }
        }
    }
    
    // Transaction apply
    if (applyTransaction) {
        // All transactions on our apply token are one-way. See comment on mAppliedLastTransaction
        t.setApplyToken(mApplyToken).apply(false, true);
    }
}
```



# createSurface

用于创建 Surface 
```java
// BLASTBufferQueue.java
public Surface createSurface() {
	return nativeGetSurface(mNativeObject, false /* includeSurfaceControlHandle */);
}

// android_graphics_BLASTBufferQueue.cpp
static jobject nativeGetSurface(JNIEnv* env, jclass clazz, jlong ptr,
                                jboolean includeSurfaceControlHandle) {
    sp<BLASTBufferQueue> queue = reinterpret_cast<BLASTBufferQueue*>(ptr);
    return android_view_Surface_createFromSurface(env,
                                                  queue->getSurface(includeSurfaceControlHandle));
}
```

## getSurface

调用 `BBQSurface` 构造函数创建对象实例。
```cpp
// 创建 native Surface 对象
sp<Surface> BLASTBufferQueue::getSurface(bool includeSurfaceControlHandle) {
    std::lock_guard _lock{mMutex};
    sp<IBinder> scHandle = nullptr;
    // 默认为 false
    if (includeSurfaceControlHandle && mSurfaceControl) {
        scHandle = mSurfaceControl->getHandle();
    }
    return new BBQSurface(mProducer, true, scHandle, this);
}
```

构造函数实现。
```c++
// BLASTBufferQueue.cpp
BBQSurface(const sp<IGraphicBufferProducer>& igbp, bool controlledByApp,
               const sp<IBinder>& scHandle, const sp<BLASTBufferQueue>& bbq)
          : Surface(igbp, controlledByApp, scHandle), mBbq(bbq) {}
          

// Surface.cpp       
Surface::Surface(const sp<IGraphicBufferProducer>& bufferProducer, bool controlledByApp,
                 const sp<IBinder>& surfaceControlHandle)
      : mGraphicBufferProducer(bufferProducer),
        mCrop(Rect::EMPTY_RECT),
        mBufferAge(0),
        mGenerationNumber(0),
        mSharedBufferMode(false),
        mAutoRefresh(false),
        mAutoPrerotation(false),
        mSharedBufferSlot(BufferItem::INVALID_BUFFER_SLOT),
        mSharedBufferHasBeenQueued(false),
        mQueriedSupportedTimestamps(false),
        mFrameTimestampsSupportsPresent(false),
        mEnableFrameTimestamps(false),
        mFrameEventHistory(std::make_unique<ProducerFrameEventHistory>()) {
    // Initialize the ANativeWindow function pointers.
    ANativeWindow::setSwapInterval  = hook_setSwapInterval;
    ANativeWindow::dequeueBuffer    = hook_dequeueBuffer;
    ANativeWindow::cancelBuffer     = hook_cancelBuffer;
    ANativeWindow::queueBuffer      = hook_queueBuffer;
    ANativeWindow::query            = hook_query;
    ANativeWindow::perform          = hook_perform;

    ANativeWindow::dequeueBuffer_DEPRECATED = hook_dequeueBuffer_DEPRECATED;
    ANativeWindow::cancelBuffer_DEPRECATED  = hook_cancelBuffer_DEPRECATED;
    ANativeWindow::lockBuffer_DEPRECATED    = hook_lockBuffer_DEPRECATED;
    ANativeWindow::queueBuffer_DEPRECATED   = hook_queueBuffer_DEPRECATED;

    const_cast<int&>(ANativeWindow::minSwapInterval) = 0;
    const_cast<int&>(ANativeWindow::maxSwapInterval) = 1;

    mReqWidth = 0;
    mReqHeight = 0;
    mReqFormat = 0;
    mReqUsage = 0;
    mTimestamp = NATIVE_WINDOW_TIMESTAMP_AUTO;
    mDataSpace = Dataspace::UNKNOWN;
    mScalingMode = NATIVE_WINDOW_SCALING_MODE_FREEZE;
    mTransform = 0;
    mStickyTransform = 0;
    mDefaultWidth = 0;
    mDefaultHeight = 0;
    mUserWidth = 0;
    mUserHeight = 0;
    mTransformHint = 0;
    mConsumerRunningBehind = false;
    mConnectedToCpu = false;
    mProducerControlledByApp = controlledByApp;
    mSwapIntervalZero = false;
    mMaxBufferCount = NUM_BUFFER_SLOTS;
    mSurfaceControlHandle = surfaceControlHandle;
}
```

## android_view_Surface_createFromSurface

创建 Surface Java 层对象并返回。
```cpp
jobject android_view_Surface_createFromSurface(JNIEnv* env, const sp<Surface>& surface) {
	// 调用 android.view.Surface(long) 构造函数，创建对象
    jobject surfaceObj = env->NewObject(gSurfaceClassInfo.clazz,
            gSurfaceClassInfo.ctor, (jlong)surface.get());
    if (surfaceObj == NULL) {
        if (env->ExceptionCheck()) {
            ALOGE("Could not create instance of Surface from IGraphicBufferProducer.");
            LOGE_EX(env);
            env->ExceptionClear();
        }
        return NULL;
    }
    surface->incStrong(&sRefBaseOwner);
    // 返回对象
    return surfaceObj;
}
```


# 案例分析


## queueBuffer 逻辑分析



## dequeueBuffer 逻辑分析

# Refs

https://juejin.cn/post/7397424623959080998