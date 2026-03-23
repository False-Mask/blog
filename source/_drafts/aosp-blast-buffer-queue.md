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


```plaintText
Surface::queueBuffer
-> BufferQueueProducer::queueBuffer
-> ProxyConsumerListener::onFrameAvailable
-> BLASTBufferQueue::onFrameAvailable
-> BLASTBufferQueue::acquireNextBufferLocked
```

### Surface::queueBuffer

BLASTBufferQueue::getSurface获取的Buffer对象为BBQSurface
BBQSurface没有重写queueBuffer方法，因此queueBuffer的实现在Surface类里面.

```c++
int Surface::queueBuffer(android_native_buffer_t* buffer, int fenceFd) {
    // ......
    Mutex::Autolock lock(mMutex);
	// 获取buffer中slot
    int i = getSlotFromBufferLocked(buffer);
    // slot index异常
    if (i < 0) {
        if (fenceFd >= 0) {
            close(fenceFd);
        }
        return i;
    }
    if (mSharedBufferSlot == i && mSharedBufferHasBeenQueued) {
        if (fenceFd >= 0) {
            close(fenceFd);
        }
        return OK;
    }

    IGraphicBufferProducer::QueueBufferOutput output;
    IGraphicBufferProducer::QueueBufferInput input;
    getQueueBufferInputLocked(buffer, fenceFd, mTimestamp, &input);
    applyGrallocMetadataLocked(buffer, input);
    sp<Fence> fence = input.fence;

    nsecs_t now = systemTime();

    status_t err = mGraphicBufferProducer->queueBuffer(i, input, &output);
    mLastQueueDuration = systemTime() - now;
    // ......

    onBufferQueuedLocked(i, fence, output);
    return err;
}
```

注：其中mGraphicBufferProducer是BBQBufferQueueProducer的实例。
其中mGraphicBufferProducer的传入逻辑如下
```c++

// 1. 调用构造方法创建BLASTBufferQueue实例
BLASTBufferQueue::BLASTBufferQueue(const std::string& name, bool updateDestinationFrame)
      : mSurfaceControl(nullptr),
        mSize(1, 1),
        mRequestedSize(mSize),
        mFormat(PIXEL_FORMAT_RGBA_8888),
        mTransactionReadyCallback(nullptr),
        mSyncTransaction(nullptr),
        mUpdateDestinationFrame(updateDestinationFrame) {
	// 创建BufferQueue赋值mProducer
	createBufferQueue(&mProducer, &mConsumer);
	// ......
}

// 2. 赋值BLASTBufferQueue::mProducer实例
void BLASTBufferQueue::createBufferQueue(sp<IGraphicBufferProducer>* outProducer,
                                         sp<IGraphicBufferConsumer>* outConsumer) {
    
	
    sp<BufferQueueCore> core(new BufferQueueCore());

    sp<IGraphicBufferProducer> producer(new BBQBufferQueueProducer(core, this));

    sp<BufferQueueConsumer> consumer(new BufferQueueConsumer(core));
    consumer->setAllowExtraAcquire(true);
	// 创建producer
    *outProducer = producer;
    *outConsumer = consumer;
}

// 3. 传入mProducer创建BBQSurface
// 自此mProducer就传入到了Surface::mGraphicBufferProducer中了
sp<Surface> BLASTBufferQueue::getSurface(bool includeSurfaceControlHandle) {
    std::lock_guard _lock{mMutex};
    sp<IBinder> scHandle = nullptr;
    if (includeSurfaceControlHandle && mSurfaceControl) {
        scHandle = mSurfaceControl->getHandle();
    }
    // 此处mProducer
    return new BBQSurface(mProducer, true, scHandle, this);
}

```

#### BBQBufferQueueProducer::queueBuffer

该方法的逻辑是准备BufferItem，然后调用frameAvailableListener.onFrameAvailable

```c++
status_t BufferQueueProducer::queueBuffer(int slot,
        const QueueBufferInput &input, QueueBufferOutput *output) {
	// ......

    int64_t requestedPresentTimestamp;
    bool isAutoTimestamp;
    android_dataspace dataSpace;
    Rect crop(Rect::EMPTY_RECT);
    int scalingMode;
    uint32_t transform;
    uint32_t stickyTransform;
    sp<Fence> acquireFence;
    bool getFrameTimestamps = false;
    input.deflate(&requestedPresentTimestamp, &isAutoTimestamp, &dataSpace,
            &crop, &scalingMode, &transform, &acquireFence, &stickyTransform,
            &getFrameTimestamps);
    const Region& surfaceDamage = input.getSurfaceDamage();
    const HdrMetadata& hdrMetadata = input.getHdrMetadata();

    // ......

    sp<IConsumerListener> frameAvailableListener;
    sp<IConsumerListener> frameReplacedListener;
    int callbackTicket = 0;
    uint64_t currentFrameNumber = 0;
    BufferItem item;
    int connectedApi;
    sp<Fence> lastQueuedFence;
	
	// 设置BufferItem
    { // Autolock scope
		// ......
		// 创建listener实例(mCore->mConsumerListener)
		if (mCore->mQueue.empty()) {
            // ......
            mCore->mQueue.push_back(item);
            frameAvailableListener = mCore->mConsumerListener;
        } else {
            // ......
            if (last.mIsDroppable) {
                // ......
            } else {
                mCore->mQueue.push_back(item);
                frameAvailableListener = mCore->mConsumerListener;
            }
        }
    } // Autolock scope

    // ......

    // Update and get FrameEventHistory.
    nsecs_t postedTime = systemTime(SYSTEM_TIME_MONOTONIC);
    NewFrameEventsEntry newFrameEventsEntry = {
        currentFrameNumber,
        postedTime,
        requestedPresentTimestamp,
        std::move(acquireFenceTime)
    };
    addAndGetFrameTimestamps(&newFrameEventsEntry,
            getFrameTimestamps ? &output->frameTimestamps : nullptr);

    // Call back without the main BufferQueue lock held, but with the callback
    // lock held so we can ensure that callbacks occur in order

    { // scope for the lock
        std::unique_lock<std::mutex> lock(mCallbackMutex);
        while (callbackTicket != mCurrentCallbackTicket) {
            mCallbackCondition.wait(lock);
        }
		// 回调listener
        if (frameAvailableListener != nullptr) {
            frameAvailableListener->onFrameAvailable(item);
        } else if (frameReplacedListener != nullptr) {
            frameReplacedListener->onFrameReplaced(item);
        }

        ++mCurrentCallbackTicket;
        mCallbackCondition.notify_all();
    }

    // Wait without lock held
    // ......

    return NO_ERROR;
}
```

因此frameAvailableListener是一个关键点，其中frameAvailableListener是mCore->mConsumerListener中获取的。而mCore->mConsumerListener是从如下的堆栈调用中获取的：
```c++
// 1. 创建BLASTBufferItemConsumer
mBufferItemConsumer = new BLASTBufferItemConsumer(mConsumer,
                                                      GraphicBuffer::USAGE_HW_COMPOSER |
                                                              GraphicBuffer::USAGE_HW_TEXTURE,
                                                      1, false, this);
// 2. 其中BLASTBufferItemConsumer的构造函数会触发父类构造方法的调用
// 原因为BLASTBufferItemConsumer继承关系如下:
// BLASTBufferItemConsumer -> BufferItemConsumer -> ConsumerBase
// 因此构造函数的调用会调到ConsumerBase::ConsumerBase的构造方法。
ConsumerBase::ConsumerBase(const sp<IGraphicBufferConsumer>& bufferQueue, bool controlledByApp) :
        mAbandoned(false),
        mConsumer(bufferQueue),
        mPrevFinalReleaseFence(Fence::NO_FENCE) {
    // Choose a name using the PID and a process-unique ID.
    mName = String8::format("unnamed-%d-%d", getpid(), createProcessUniqueId());

    // Note that we can't create an sp<...>(this) in a ctor that will not keep a
    // reference once the ctor ends, as that would cause the refcount of 'this'
    // dropping to 0 at the end of the ctor.  Since all we need is a wp<...>
    // that's what we create.
    wp<ConsumerListener> listener = static_cast<ConsumerListener*>(this);
    sp<IConsumerListener> proxy = new BufferQueue::ProxyConsumerListener(listener);
	// 向BufferQueueConsumer中设置listener
    status_t err = mConsumer->consumerConnect(proxy, controlledByApp);
    if (err != NO_ERROR) {
        CB_LOGE("ConsumerBase: error connecting to BufferQueue: %s (%d)",
                strerror(-err), err);
    } else {
        mConsumer->setConsumerName(mName);
    }
}

// 3. 设置listener
status_t BufferQueueConsumer::connect(
        const sp<IConsumerListener>& consumerListener, bool controlledByApp) {
    ATRACE_CALL();

    if (consumerListener == nullptr) {
        BQ_LOGE("connect: consumerListener may not be NULL");
        return BAD_VALUE;
    }

    BQ_LOGV("connect: controlledByApp=%s",
            controlledByApp ? "true" : "false");

    std::lock_guard<std::mutex> lock(mCore->mMutex);

    if (mCore->mIsAbandoned) {
        BQ_LOGE("connect: BufferQueue has been abandoned");
        return NO_INIT;
    }

    mCore->mConsumerListener = consumerListener;
    mCore->mConsumerControlledByApp = controlledByApp;

    return NO_ERROR;
}                                       
```


####  ProxyConsumerListener::onFrameAvailable

前一步已经分析了frameAvailableListener的创建逻辑，接着我们进一步进行分析.
不难发现该方法核心逻辑就是代理调用mConsumerListener.onFrameAvailable方法
```c++
void BufferQueue::ProxyConsumerListener::onFrameAvailable(
        const BufferItem& item) {
    sp<ConsumerListener> listener(mConsumerListener.promote());
    if (listener != nullptr) {
        listener->onFrameAvailable(item);
    }
}
```


问题来了mConsumerListener是从那里来的呢？其实不难发现之前mCore->mConsumerListener设置逻辑中已经包含了mConsumerListener的设置逻辑。
在**BLASTBufferQueue的父类构造函数**中会将BLASTBufferQueue**强转为ConsumerListener**传入到**ProxyConsumerListener的构造函数中**。
而此处传入的ConsumerListener会被设置到**ProxyConsumerListener::mConsumerListener**
```c++
ConsumerBase::ConsumerBase(const sp<IGraphicBufferConsumer>& bufferQueue, bool controlledByApp) :
        mAbandoned(false),
        mConsumer(bufferQueue),
        mPrevFinalReleaseFence(Fence::NO_FENCE) {
    // Choose a name using the PID and a process-unique ID.
    mName = String8::format("unnamed-%d-%d", getpid(), createProcessUniqueId());

    // Note that we can't create an sp<...>(this) in a ctor that will not keep a
    // reference once the ctor ends, as that would cause the refcount of 'this'
    // dropping to 0 at the end of the ctor.  Since all we need is a wp<...>
    // that's what we create.
    
    // 此处会将BLASTBufferQueue 作为参数传入到ProxyConsumerListener构造函数中
    wp<ConsumerListener> listener = static_cast<ConsumerListener*>(this);
    sp<IConsumerListener> proxy = new BufferQueue::ProxyConsumerListener(listener);
	// 向 BufferQueueConsumer 中设置listener
    status_t err = mConsumer->consumerConnect(proxy, controlledByApp);
    if (err != NO_ERROR) {
        CB_LOGE("ConsumerBase: error connecting to BufferQueue: %s (%d)",
                strerror(-err), err);
    } else {
        mConsumer->setConsumerName(mName);
    }
}
```

#### BLASTBufferQueue::onFrameAvailable

核心逻辑通过调用BLASTBufferQueue::acquireNextBufferLocked获取buffer，但是分配buffer有一个分叉
1.外部调用了BLASTBufferQueue::syncNextTransaction，需要等待transaction
2.外部没调用BLASTBufferQueue::syncNextTransaction，不需要等待transaction
上述两个分支都会调用acquireNextBufferLocked分配buffer.
```c++
void BLASTBufferQueue::onFrameAvailable(const BufferItem& item) {
    std::function<void(SurfaceComposerClient::Transaction*)> prevCallback = nullptr;
    SurfaceComposerClient::Transaction* prevTransaction = nullptr;

    {
        UNIQUE_LOCK_WITH_ASSERTION(mMutex);
        BBQ_TRACE();
        bool waitForTransactionCallback = !mSyncedFrameNumbers.empty();

        const bool syncTransactionSet = mTransactionReadyCallback != nullptr;
        BQA_LOGV("onFrameAvailable-start syncTransactionSet=%s", boolToString(syncTransactionSet));

        if (syncTransactionSet) {
            // If we are going to re-use the same mSyncTransaction, release the buffer that may
            // already be set in the Transaction. This is to allow us a free slot early to continue
            // processing a new buffer.
            if (!mAcquireSingleBuffer) {
                auto bufferData = mSyncTransaction->getAndClearBuffer(mSurfaceControl);
                if (bufferData) {
                    BQA_LOGD("Releasing previous buffer when syncing: framenumber=%" PRIu64,
                             bufferData->frameNumber);
                    releaseBuffer(bufferData->generateReleaseCallbackId(),
                                  bufferData->acquireFence);
                }
            }

            if (waitForTransactionCallback) {
                // We are waiting on a previous sync's transaction callback so allow another sync
                // transaction to proceed.
                //
                // We need to first flush out the transactions that were in between the two syncs.
                // We do this by merging them into mSyncTransaction so any buffer merging will get
                // a release callback invoked.
                while (mNumFrameAvailable > 0) {
                    // flush out the shadow queue
                    acquireAndReleaseBuffer();
                }
            } else {
                // Make sure the frame available count is 0 before proceeding with a sync to ensure
                // the correct frame is used for the sync. The only way mNumFrameAvailable would be
                // greater than 0 is if we already ran out of buffers previously. This means we
                // need to flush the buffers before proceeding with the sync.
                while (mNumFrameAvailable > 0) {
                    BQA_LOGD("waiting until no queued buffers");
                    mCallbackCV.wait(_lock);
                }
            }
        }

        // add to shadow queue
        mNumFrameAvailable++;
        if (waitForTransactionCallback && mNumFrameAvailable >= 2) {
            acquireAndReleaseBuffer();
        }
        ATRACE_INT(mQueuedBufferTrace.c_str(),
                   mNumFrameAvailable + mNumAcquired - mPendingRelease.size());

        BQA_LOGV("onFrameAvailable framenumber=%" PRIu64 " syncTransactionSet=%s",
                 item.mFrameNumber, boolToString(syncTransactionSet));
		// BLASTBufferQueue外部调用了syncNextTransaction
        if (syncTransactionSet) {
            // Add to mSyncedFrameNumbers before waiting in case any buffers are released
            // while waiting for a free buffer. The release and commit callback will try to
            // acquire buffers if there are any available, but we don't want it to acquire
            // in the case where a sync transaction wants the buffer.
            mSyncedFrameNumbers.emplace(item.mFrameNumber);
            // If there's no available buffer and we're in a sync transaction, we need to wait
            // instead of returning since we guarantee a buffer will be acquired for the sync.
            // 关键点：获取Buffer
            while (acquireNextBufferLocked(mSyncTransaction) == BufferQueue::NO_BUFFER_AVAILABLE) {
                BQA_LOGD("waiting for available buffer");
                mCallbackCV.wait(_lock);
            }

            // Only need a commit callback when syncing to ensure the buffer that's synced has been
            // sent to SF
            incStrong((void*)transactionCommittedCallbackThunk);
            mSyncTransaction->addTransactionCommittedCallback(transactionCommittedCallbackThunk,
                                                              static_cast<void*>(this));
            if (mAcquireSingleBuffer) {
                prevCallback = mTransactionReadyCallback;
                prevTransaction = mSyncTransaction;
                mTransactionReadyCallback = nullptr;
                mSyncTransaction = nullptr;
            }
        } else if (!waitForTransactionCallback) { // 等待transactionCallbacks
            // 关键点：获取buffer
            acquireNextBufferLocked(std::nullopt);
        }
    }
    if (prevCallback) {
        prevCallback(prevTransaction);
    }
}
```

#### BLASTBufferQueue::acquireNextBufferLocked

如果不需要等待transaction则acquireNextBufferLocked的入参为null
```c++
acquireNextBufferLocked(std::nullopt);
```

核心逻辑有如下几个
1.调用BufferItemConsumer分配buffer
2.将BufferItem的数据取出来，准备并设置Transaction
3.调用Transaction.apply 提交到SurfaceFlinger

```c++
status_t BLASTBufferQueue::acquireNextBufferLocked(
        const std::optional<SurfaceComposerClient::Transaction*> transaction) {
    // 可用的buffer分配完了
    if (mNumFrameAvailable == 0) {
        BQA_LOGV("Can't acquire next buffer. No available frames");
        return BufferQueue::NO_BUFFER_AVAILABLE;
    }
	// 分配的buffer太多了
    if (mNumAcquired >= (mMaxAcquiredBuffers + 2)) {
        BQA_LOGV("Can't acquire next buffer. Already acquired max frames %d max:%d + 2",
                 mNumAcquired, mMaxAcquiredBuffers);
        return BufferQueue::NO_BUFFER_AVAILABLE;
    }
	// 没有设置surfaceControl
    if (mSurfaceControl == nullptr) {
        BQA_LOGE("ERROR : surface control is null");
        return NAME_NOT_FOUND;
    }

    SurfaceComposerClient::Transaction localTransaction;
    bool applyTransaction = true;
    SurfaceComposerClient::Transaction* t = &localTransaction;
    // 如果 transaction 为非空，则transaction的apply交给外部，不需要做applyTransaction
    // Note：由于transaction为null, acquireNextBufferLocked方法内部会出发transaction apply操作。
    if (transaction) {
        t = *transaction;
        applyTransaction = false;
    }

    BufferItem bufferItem;
	// 重点：调用BufferItemConsumer分配buffer
    status_t status =
            mBufferItemConsumer->acquireBuffer(&bufferItem, 0 /* expectedPresent */, false);
    // 处理异常状态        
    if (status == BufferQueue::NO_BUFFER_AVAILABLE) {
        BQA_LOGV("Failed to acquire a buffer, err=NO_BUFFER_AVAILABLE");
        return status;
    } else if (status != OK) {
        BQA_LOGE("Failed to acquire a buffer, err=%s", statusToString(status).c_str());
        return status;
    }
	
    auto buffer = bufferItem.mGraphicBuffer;
    // 递减可用buffer数
    mNumFrameAvailable--;
    BBQ_TRACE("frame=%" PRIu64, bufferItem.mFrameNumber);
	// 处理异常状态，buffer分配异常(取值为null)
    if (buffer == nullptr) {
        mBufferItemConsumer->releaseBuffer(bufferItem, Fence::NO_FENCE);
        BQA_LOGE("Buffer was empty");
        return BAD_VALUE;
    }
	// buffer的大小不何时，拒绝使用buffer
    if (rejectBuffer(bufferItem)) {
        BQA_LOGE("rejecting buffer:active_size=%dx%d, requested_size=%dx%d "
                 "buffer{size=%dx%d transform=%d}",
                 mSize.width, mSize.height, mRequestedSize.width, mRequestedSize.height,
                 buffer->getWidth(), buffer->getHeight(), bufferItem.mTransform);
        mBufferItemConsumer->releaseBuffer(bufferItem, Fence::NO_FENCE);
        return acquireNextBufferLocked(transaction);
    }
	// 累加buffer分配数
    mNumAcquired++;
    mLastAcquiredFrameNumber = bufferItem.mFrameNumber;
    ReleaseCallbackId releaseCallbackId(buffer->getId(), mLastAcquiredFrameNumber);
    mSubmitted[releaseCallbackId] = bufferItem;

    bool needsDisconnect = false;
    mBufferItemConsumer->getConnectionEvents(bufferItem.mFrameNumber, &needsDisconnect);

    // if producer disconnected before, notify SurfaceFlinger
    if (needsDisconnect) {
        t->notifyProducerDisconnect(mSurfaceControl);
    }

    // Ensure BLASTBufferQueue stays alive until we receive the transaction complete callback.
    incStrong((void*)transactionCallbackThunk);

    // Only update mSize for destination bounds if the incoming buffer matches the requested size.
    // Otherwise, it could cause stretching since the destination bounds will update before the
    // buffer with the new size is acquired.
    if (mRequestedSize == getBufferSize(bufferItem) ||
        bufferItem.mScalingMode != NATIVE_WINDOW_SCALING_MODE_FREEZE) {
        mSize = mRequestedSize;
    }
    Rect crop = computeCrop(bufferItem);
    mLastBufferInfo.update(true /* hasBuffer */, bufferItem.mGraphicBuffer->getWidth(),
                           bufferItem.mGraphicBuffer->getHeight(), bufferItem.mTransform,
                           bufferItem.mScalingMode, crop);

    auto releaseBufferCallback =
            std::bind(releaseBufferCallbackThunk, wp<BLASTBufferQueue>(this) /* callbackContext */,
                      std::placeholders::_1, std::placeholders::_2, std::placeholders::_3);
    sp<Fence> fence = bufferItem.mFence ? new Fence(bufferItem.mFence->dup()) : Fence::NO_FENCE;
    // 重点： 准备Transaction方便后续做apply
    t->setBuffer(mSurfaceControl, buffer, fence, bufferItem.mFrameNumber, mProducerId,
                 releaseBufferCallback);
    t->setDataspace(mSurfaceControl, static_cast<ui::Dataspace>(bufferItem.mDataSpace));
    t->setHdrMetadata(mSurfaceControl, bufferItem.mHdrMetadata);
    t->setSurfaceDamageRegion(mSurfaceControl, bufferItem.mSurfaceDamage);
    t->addTransactionCompletedCallback(transactionCallbackThunk, static_cast<void*>(this));

    mSurfaceControlsWithPendingCallback.push(mSurfaceControl);

    if (mUpdateDestinationFrame) {
        t->setDestinationFrame(mSurfaceControl, Rect(mSize));
    } else {
        const bool ignoreDestinationFrame =
                bufferItem.mScalingMode == NATIVE_WINDOW_SCALING_MODE_FREEZE;
        t->setFlags(mSurfaceControl,
                    ignoreDestinationFrame ? layer_state_t::eIgnoreDestinationFrame : 0,
                    layer_state_t::eIgnoreDestinationFrame);
    }
    t->setBufferCrop(mSurfaceControl, crop);
    t->setTransform(mSurfaceControl, bufferItem.mTransform);
    t->setTransformToDisplayInverse(mSurfaceControl, bufferItem.mTransformToDisplayInverse);
    t->setAutoRefresh(mSurfaceControl, bufferItem.mAutoRefresh);
    if (!bufferItem.mIsAutoTimestamp) {
        t->setDesiredPresentTime(bufferItem.mTimestamp);
    }

    // Drop stale frame timeline infos
    while (!mPendingFrameTimelines.empty() &&
           mPendingFrameTimelines.front().first < bufferItem.mFrameNumber) {
        ATRACE_FORMAT_INSTANT("dropping stale frameNumber: %" PRIu64 " vsyncId: %" PRId64,
                              mPendingFrameTimelines.front().first,
                              mPendingFrameTimelines.front().second.vsyncId);
        mPendingFrameTimelines.pop();
    }

    if (!mPendingFrameTimelines.empty() &&
        mPendingFrameTimelines.front().first == bufferItem.mFrameNumber) {
        ATRACE_FORMAT_INSTANT("Transaction::setFrameTimelineInfo frameNumber: %" PRIu64
                              " vsyncId: %" PRId64,
                              bufferItem.mFrameNumber,
                              mPendingFrameTimelines.front().second.vsyncId);
        t->setFrameTimelineInfo(mPendingFrameTimelines.front().second);
        mPendingFrameTimelines.pop();
    }

    {
        std::lock_guard _lock{mTimestampMutex};
        auto dequeueTime = mDequeueTimestamps.find(buffer->getId());
        if (dequeueTime != mDequeueTimestamps.end()) {
            Parcel p;
            p.writeInt64(dequeueTime->second);
            t->setMetadata(mSurfaceControl, gui::METADATA_DEQUEUE_TIME, p);
            mDequeueTimestamps.erase(dequeueTime);
        }
    }
	// 将pendingTransaction合并到Transaction中。
    mergePendingTransactions(t, bufferItem.mFrameNumber);
    // 核心逻辑：准备好Transaction后调用apply将Transaction提交到SurfaceFlinger中
    if (applyTransaction) {
        // 
        t->setApplyToken(mApplyToken).apply(false, true);
        mAppliedLastTransaction = true;
        mLastAppliedFrameNumber = bufferItem.mFrameNumber;
    } else {
        t->setBufferHasBarrier(mSurfaceControl, mLastAppliedFrameNumber);
        mAppliedLastTransaction = false;
    }

    BQA_LOGV("acquireNextBufferLocked size=%dx%d mFrameNumber=%" PRIu64
             " applyTransaction=%s mTimestamp=%" PRId64 "%s mPendingTransactions.size=%d"
             " graphicBufferId=%" PRIu64 "%s transform=%d",
             mSize.width, mSize.height, bufferItem.mFrameNumber, boolToString(applyTransaction),
             bufferItem.mTimestamp, bufferItem.mIsAutoTimestamp ? "(auto)" : "",
             static_cast<uint32_t>(mPendingTransactions.size()), bufferItem.mGraphicBuffer->getId(),
             bufferItem.mAutoRefresh ? " mAutoRefresh" : "", bufferItem.mTransform);
    return OK;
}
```


##### acquireBuffer

acquireBuffer的入口如下
```c++
// BLASTBufferQueue.cpp
status_t BLASTBufferQueue::acquireNextBufferLocked(
        const std::optional<SurfaceComposerClient::Transaction*> transaction) {
    
	// ......    
    
	status_t status =
	            mBufferItemConsumer->acquireBuffer(&bufferItem, 0 /* expectedPresent */, false);
	            
	// ......
            
}            
```


其中mBufferItemConsumer是什么对象？从BLASTBufferQueue的构造函数中不难发现是BLASTBufferItemConsumer
```c++
BLASTBufferQueue::BLASTBufferQueue(const std::string& name, bool updateDestinationFrame)
      : mSurfaceControl(nullptr),
        mSize(1, 1),
        mRequestedSize(mSize),
        mFormat(PIXEL_FORMAT_RGBA_8888),
        mTransactionReadyCallback(nullptr),
        mSyncTransaction(nullptr),
        mUpdateDestinationFrame(updateDestinationFrame) { 
        
        // ......
        
		mBufferItemConsumer = new BLASTBufferItemConsumer(mConsumer,
		                                                      GraphicBuffer::USAGE_HW_COMPOSER |
		                                                              GraphicBuffer::USAGE_HW_TEXTURE,
		                                                      1, false, this);
                                                      
        // ......                                              
}
```

然而BLASTBufferItemConsumer没有重写acquireBuffer
```c++
// BufferItemConsumer.cpp
status_t BufferItemConsumer::acquireBuffer(BufferItem *item,
        nsecs_t presentWhen, bool waitForFence) {
    status_t err;

    if (!item) return BAD_VALUE;

    Mutex::Autolock _l(mMutex);

    err = acquireBufferLocked(item, presentWhen);
    if (err != OK) {
        if (err != NO_BUFFER_AVAILABLE) {
            BI_LOGE("Error acquiring buffer: %s (%d)", strerror(err), err);
        }
        return err;
    }

    if (waitForFence) {
        err = item->mFence->waitForever("BufferItemConsumer::acquireBuffer");
        if (err != OK) {
            BI_LOGE("Failed to wait for fence of acquired buffer: %s (%d)",
                    strerror(-err), err);
            return err;
        }
    }

    item->mGraphicBuffer = mSlots[item->mSlot].mGraphicBuffer;

    return OK;
}
```


```c++
status_t ConsumerBase::acquireBufferLocked(BufferItem *item,
        nsecs_t presentWhen, uint64_t maxFrameNumber) {
    if (mAbandoned) {
        CB_LOGE("acquireBufferLocked: ConsumerBase is abandoned!");
        return NO_INIT;
    }

    status_t err = mConsumer->acquireBuffer(item, presentWhen, maxFrameNumber);
    if (err != NO_ERROR) {
        return err;
    }

    if (item->mGraphicBuffer != nullptr) {
        if (mSlots[item->mSlot].mGraphicBuffer != nullptr) {
            freeBufferLocked(item->mSlot);
        }
        mSlots[item->mSlot].mGraphicBuffer = item->mGraphicBuffer;
    }

    mSlots[item->mSlot].mFrameNumber = item->mFrameNumber;
    mSlots[item->mSlot].mFence = item->mFence;

    CB_LOGV("acquireBufferLocked: -> slot=%d/%" PRIu64,
            item->mSlot, item->mFrameNumber);

    return OK;
}
```

从队列中取出一个buffer
```c++
status_t BufferQueueConsumer::acquireBuffer(BufferItem* outBuffer,
        nsecs_t expectedPresent, uint64_t maxFrameNumber) {
    ATRACE_CALL();

    int numDroppedBuffers = 0;
    sp<IProducerListener> listener;
    {
        std::unique_lock<std::mutex> lock(mCore->mMutex);

        // Check that the consumer doesn't currently have the maximum number of
        // buffers acquired. We allow the max buffer count to be exceeded by one
        // buffer so that the consumer can successfully set up the newly acquired
        // buffer before releasing the old one.
        int numAcquiredBuffers = 0;
        for (int s : mCore->mActiveBuffers) {
            if (mSlots[s].mBufferState.isAcquired()) {
                ++numAcquiredBuffers;
            }
        }
        const bool acquireNonDroppableBuffer = mCore->mAllowExtraAcquire &&
                numAcquiredBuffers == mCore->mMaxAcquiredBufferCount + 1;
        if (numAcquiredBuffers >= mCore->mMaxAcquiredBufferCount + 1 &&
            !acquireNonDroppableBuffer) {
            BQ_LOGE("acquireBuffer: max acquired buffer count reached: %d (max %d)",
                    numAcquiredBuffers, mCore->mMaxAcquiredBufferCount);
            return INVALID_OPERATION;
        }

        bool sharedBufferAvailable = mCore->mSharedBufferMode &&
                mCore->mAutoRefresh && mCore->mSharedBufferSlot !=
                BufferQueueCore::INVALID_BUFFER_SLOT;

        // In asynchronous mode the list is guaranteed to be one buffer deep,
        // while in synchronous mode we use the oldest buffer.
        if (mCore->mQueue.empty() && !sharedBufferAvailable) {
            return NO_BUFFER_AVAILABLE;
        }

        BufferQueueCore::Fifo::iterator front(mCore->mQueue.begin());

        // If expectedPresent is specified, we may not want to return a buffer yet.
        // If it's specified and there's more than one buffer queued, we may want
        // to drop a buffer.
        // Skip this if we're in shared buffer mode and the queue is empty,
        // since in that case we'll just return the shared buffer.
        if (expectedPresent != 0 && !mCore->mQueue.empty()) {
            // The 'expectedPresent' argument indicates when the buffer is expected
            // to be presented on-screen. If the buffer's desired present time is
            // earlier (less) than expectedPresent -- meaning it will be displayed
            // on time or possibly late if we show it as soon as possible -- we
            // acquire and return it. If we don't want to display it until after the
            // expectedPresent time, we return PRESENT_LATER without acquiring it.
            //
            // To be safe, we don't defer acquisition if expectedPresent is more
            // than one second in the future beyond the desired present time
            // (i.e., we'd be holding the buffer for a long time).
            //
            // NOTE: Code assumes monotonic time values from the system clock
            // are positive.

            // Start by checking to see if we can drop frames. We skip this check if
            // the timestamps are being auto-generated by Surface. If the app isn't
            // generating timestamps explicitly, it probably doesn't want frames to
            // be discarded based on them.
            while (mCore->mQueue.size() > 1 && !mCore->mQueue[0].mIsAutoTimestamp) {
                const BufferItem& bufferItem(mCore->mQueue[1]);

                // If dropping entry[0] would leave us with a buffer that the
                // consumer is not yet ready for, don't drop it.
                if (maxFrameNumber && bufferItem.mFrameNumber > maxFrameNumber) {
                    break;
                }

                // If entry[1] is timely, drop entry[0] (and repeat). We apply an
                // additional criterion here: we only drop the earlier buffer if our
                // desiredPresent falls within +/- 1 second of the expected present.
                // Otherwise, bogus desiredPresent times (e.g., 0 or a small
                // relative timestamp), which normally mean "ignore the timestamp
                // and acquire immediately", would cause us to drop frames.
                //
                // We may want to add an additional criterion: don't drop the
                // earlier buffer if entry[1]'s fence hasn't signaled yet.
                nsecs_t desiredPresent = bufferItem.mTimestamp;
                if (desiredPresent < expectedPresent - MAX_REASONABLE_NSEC ||
                        desiredPresent > expectedPresent) {
                    // This buffer is set to display in the near future, or
                    // desiredPresent is garbage. Either way we don't want to drop
                    // the previous buffer just to get this on the screen sooner.
                    BQ_LOGV("acquireBuffer: nodrop desire=%" PRId64 " expect=%"
                            PRId64 " (%" PRId64 ") now=%" PRId64,
                            desiredPresent, expectedPresent,
                            desiredPresent - expectedPresent,
                            systemTime(CLOCK_MONOTONIC));
                    break;
                }

                BQ_LOGV("acquireBuffer: drop desire=%" PRId64 " expect=%" PRId64
                        " size=%zu",
                        desiredPresent, expectedPresent, mCore->mQueue.size());

                if (!front->mIsStale) {
                    // Front buffer is still in mSlots, so mark the slot as free
                    mSlots[front->mSlot].mBufferState.freeQueued();

                    // After leaving shared buffer mode, the shared buffer will
                    // still be around. Mark it as no longer shared if this
                    // operation causes it to be free.
                    if (!mCore->mSharedBufferMode &&
                            mSlots[front->mSlot].mBufferState.isFree()) {
                        mSlots[front->mSlot].mBufferState.mShared = false;
                    }

                    // Don't put the shared buffer on the free list
                    if (!mSlots[front->mSlot].mBufferState.isShared()) {
                        mCore->mActiveBuffers.erase(front->mSlot);
                        mCore->mFreeBuffers.push_back(front->mSlot);
                    }

                    if (mCore->mBufferReleasedCbEnabled) {
                        listener = mCore->mConnectedProducerListener;
                    }
                    ++numDroppedBuffers;
                }

                mCore->mQueue.erase(front);
                front = mCore->mQueue.begin();
            }

            // See if the front buffer is ready to be acquired
            nsecs_t desiredPresent = front->mTimestamp;
            bool bufferIsDue = desiredPresent <= expectedPresent ||
                    desiredPresent > expectedPresent + MAX_REASONABLE_NSEC;
            bool consumerIsReady = maxFrameNumber > 0 ?
                    front->mFrameNumber <= maxFrameNumber : true;
            if (!bufferIsDue || !consumerIsReady) {
                BQ_LOGV("acquireBuffer: defer desire=%" PRId64 " expect=%" PRId64
                        " (%" PRId64 ") now=%" PRId64 " frame=%" PRIu64
                        " consumer=%" PRIu64,
                        desiredPresent, expectedPresent,
                        desiredPresent - expectedPresent,
                        systemTime(CLOCK_MONOTONIC),
                        front->mFrameNumber, maxFrameNumber);
                ATRACE_NAME("PRESENT_LATER");
                return PRESENT_LATER;
            }

            BQ_LOGV("acquireBuffer: accept desire=%" PRId64 " expect=%" PRId64 " "
                    "(%" PRId64 ") now=%" PRId64, desiredPresent, expectedPresent,
                    desiredPresent - expectedPresent,
                    systemTime(CLOCK_MONOTONIC));
        }

        int slot = BufferQueueCore::INVALID_BUFFER_SLOT;

        if (sharedBufferAvailable && mCore->mQueue.empty()) {
            // make sure the buffer has finished allocating before acquiring it
            mCore->waitWhileAllocatingLocked(lock);

            slot = mCore->mSharedBufferSlot;

            // Recreate the BufferItem for the shared buffer from the data that
            // was cached when it was last queued.
            outBuffer->mGraphicBuffer = mSlots[slot].mGraphicBuffer;
            outBuffer->mFence = Fence::NO_FENCE;
            outBuffer->mFenceTime = FenceTime::NO_FENCE;
            outBuffer->mCrop = mCore->mSharedBufferCache.crop;
            outBuffer->mTransform = mCore->mSharedBufferCache.transform &
                    ~static_cast<uint32_t>(
                    NATIVE_WINDOW_TRANSFORM_INVERSE_DISPLAY);
            outBuffer->mScalingMode = mCore->mSharedBufferCache.scalingMode;
            outBuffer->mDataSpace = mCore->mSharedBufferCache.dataspace;
            outBuffer->mFrameNumber = mCore->mFrameCounter;
            outBuffer->mSlot = slot;
            outBuffer->mAcquireCalled = mSlots[slot].mAcquireCalled;
            outBuffer->mTransformToDisplayInverse =
                    (mCore->mSharedBufferCache.transform &
                    NATIVE_WINDOW_TRANSFORM_INVERSE_DISPLAY) != 0;
            outBuffer->mSurfaceDamage = Region::INVALID_REGION;
            outBuffer->mQueuedBuffer = false;
            outBuffer->mIsStale = false;
            outBuffer->mAutoRefresh = mCore->mSharedBufferMode &&
                    mCore->mAutoRefresh;
        } else if (acquireNonDroppableBuffer && front->mIsDroppable) {
            BQ_LOGV("acquireBuffer: front buffer is not droppable");
            return NO_BUFFER_AVAILABLE;
        } else {
            slot = front->mSlot;
            *outBuffer = *front;
        }

        ATRACE_BUFFER_INDEX(slot);

        BQ_LOGV("acquireBuffer: acquiring { slot=%d/%" PRIu64 " buffer=%p }",
                slot, outBuffer->mFrameNumber, outBuffer->mGraphicBuffer->handle);

        if (!outBuffer->mIsStale) {
            mSlots[slot].mAcquireCalled = true;
            // Don't decrease the queue count if the BufferItem wasn't
            // previously in the queue. This happens in shared buffer mode when
            // the queue is empty and the BufferItem is created above.
            if (mCore->mQueue.empty()) {
                mSlots[slot].mBufferState.acquireNotInQueue();
            } else {
                mSlots[slot].mBufferState.acquire();
            }
            mSlots[slot].mFence = Fence::NO_FENCE;
        }

        // If the buffer has previously been acquired by the consumer, set
        // mGraphicBuffer to NULL to avoid unnecessarily remapping this buffer
        // on the consumer side
        if (outBuffer->mAcquireCalled) {
            outBuffer->mGraphicBuffer = nullptr;
        }

        mCore->mQueue.erase(front);

        // We might have freed a slot while dropping old buffers, or the producer
        // may be blocked waiting for the number of buffers in the queue to
        // decrease.
        mCore->mDequeueCondition.notify_all();

        ATRACE_INT(mCore->mConsumerName.c_str(), static_cast<int32_t>(mCore->mQueue.size()));
#ifndef NO_BINDER
        mCore->mOccupancyTracker.registerOccupancyChange(mCore->mQueue.size());
#endif
        VALIDATE_CONSISTENCY();
    }

    if (listener != nullptr) {
        for (int i = 0; i < numDroppedBuffers; ++i) {
            listener->onBufferReleased();
        }
    }

    return NO_ERROR;
}
```

##### prepare transaction


##### apply transaction




## dequeueBuffer 逻辑分析




# Refs

https://juejin.cn/post/7397424623959080998