---
title: Okio原理解析
date: 2023-04-03 11:06:41
tags:
- okio
- io
---



# Okio原理

> 基于okio:3.3.0，JVM

> Okio有如下优点
>
> - 简单
>
>   指的是它的类关系满足迪米特原则，牵扯少，只有Sink/Source仅凭其可完成所有的IO
>
> - 高效
>
>   发生io时的缓存做了池化处理避免了频繁的内存分配，Sink/Source是由Segment构成的，而Segment的获取会从SegmentPool获取
>
> - 跨平台
>
>   使用了Kotlin Multiplatform插件实现类JVM/Js/Native多平台的兼容



## Segment 

> 通常的Segment是一个循环链表

![image-20230403211909495](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403211909495.png)



### 对象创建

```kotlin
constructor() {
    // const val SIZE = 8192
  this.data = ByteArray(SIZE)
  this.owner = true
  this.shared = false
}

constructor(data: ByteArray, pos: Int, limit: Int, shared: Boolean, owner: Boolean) {
  this.data = data
  this.pos = pos
  this.limit = limit
  this.shared = shared
  this.owner = owner
}

```



### 对象复制

```kotlin
// 使用当前对象的数据复制一个Segment对象
fun sharedCopy(): Segment {
  shared = true
  return Segment(data, pos, limit, true, false)
}

// 使用当前对象的数据深拷贝一份
fun unsharedCopy() = Segment(data.copyOf(), pos, limit, false, true)
```



### 数据结构搭建

> Segment在Okio中通常是以循环链表的方式组织

```kotlin
// 将当前节点弹出
fun pop(): Segment? {
  val result = if (next !== this) next else null
  prev!!.next = next
  next!!.prev = prev
  next = null
  prev = null
  return result
}

// 在循环队列的指定位置加入一个元素
fun push(segment: Segment): Segment {
  segment.prev = this
  segment.next = next
  next!!.prev = segment
  next = segment
  return segment
}
```



### Segment拆分

> 将Segment一分为二，前部分为包含data [pos,pos + byteCount)后部分包含[pos + byteCount,limit)

```kotlin
fun split(byteCount: Int): Segment {
    // 确保当前的byteCode处于正常范围
  require(byteCount > 0 && byteCount <= limit - pos) { "byteCount out of range" }
  val prefix: Segment

    // 如果byteCount大于共享的最小值（1024）
    // 拆分时直接浅拷贝一份Segment
  if (byteCount >= SHARE_MINIMUM) {
    prefix = sharedCopy()
  } else {
      // 如果小于 1024，则从Segment池中获取一份，逐一字节复制
    prefix = SegmentPool.take()
    data.copyInto(prefix.data, startIndex = pos, endIndex = pos + byteCount)
  }
	// 更新参数
  prefix.limit = prefix.pos + byteCount
  pos += byteCount
  prev!!.push(prefix)
  return prefix
}
```



### 压缩Segment

> 尝试和前面的Segment合并，如果前面的Segment长度够长则会将两个Segment合并为1个

```kotlin
fun compact() {
  check(prev !== this) { "cannot compact" }
  if (!prev!!.owner) return // Cannot compact: prev isn't writable.
  val byteCount = limit - pos
  val availableByteCount = SIZE - prev!!.limit + if (prev!!.shared) 0 else prev!!.pos
  if (byteCount > availableByteCount) return // Cannot compact: not enough writable space.
  writeTo(prev!!, byteCount)
  pop()
  SegmentPool.recycle(this)
}
```



### 写入内容

```kotlin
fun writeTo(sink: Segment, byteCount: Int) {
  check(sink.owner) { "only owner can write" }
    // 如果剩余容量不够用
  if (sink.limit + byteCount > SIZE) {
    // We can't fit byteCount bytes at the sink's current position. Shift sink first.
    if (sink.shared) throw IllegalArgumentException()
    if (sink.limit + byteCount - sink.pos > SIZE) throw IllegalArgumentException()
      // 将[pos,limit]移到[0,limit-pos];
    sink.data.copyInto(sink.data, startIndex = sink.pos, endIndex = sink.limit)
    sink.limit -= sink.pos
    sink.pos = 0
  }
	// 将内容写入
  data.copyInto(
    sink.data, destinationOffset = sink.limit, startIndex = pos,
    endIndex = pos + byteCount
  )
  sink.limit += byteCount
  pos += byteCount
}
```



## SegmentPool



> 频繁创建使用的通常都会有XXXPool，比如为了避免线程的重复创建会有ThreadPool。
>
> 为了避免连接的重复创建所以OkHttp有了ConnectionPool



```kotlin
internal actual object SegmentPool {

  actual val MAX_SIZE = 64 * 1024 // 64 KiB.

  /** A sentinel segment to indicate that the linked list is currently being modified. */
  private val LOCK = Segment(ByteArray(0), pos = 0, limit = 0, shared = false, owner = false)

  // hash桶的大小为 2 ^ (int)log2(2 * cpu - 1)
  private val HASH_BUCKET_COUNT =
    Integer.highestOneBit(Runtime.getRuntime().availableProcessors() * 2 - 1)

 // hash桶，也是缓存的segment的地方
  private val hashBuckets: Array<AtomicReference<Segment?>> = Array(HASH_BUCKET_COUNT) {
    AtomicReference<Segment?>() // null value implies an empty bucket
  }

  actual val byteCount: Int
    get() {
      val first = firstRef().get() ?: return 0
      return first.limit
    }

  @JvmStatic
  actual fun take(): Segment {
      // 获取hash桶中的句柄
    val firstRef = firstRef()
		// 加锁
    val first = firstRef.getAndSet(LOCK)
    when {
        // 已经锁定
      first === LOCK -> {
        // 防止等待，直接new返回
        return Segment()
      }
      first == null -> {
        // 获取锁但是为缓存
        firstRef.set(null)
        return Segment()
      }
      else -> {
        //获取锁并且有缓存，使用缓存
        firstRef.set(first.next)
        first.next = null
        first.limit = 0
        return first
      }
    }
  }

  @JvmStatic
  actual fun recycle(segment: Segment) {
    require(segment.next == null && segment.prev == null)
      // 如果当前segment被共享，无法回收
    if (segment.shared) return // This segment cannot be recycled.
	// 获取句柄
    val firstRef = firstRef()
	// 加锁
    val first = firstRef.getAndSet(LOCK)
      // 没有获取锁
    if (first === LOCK) return 
      // 获取到当前线程池的缓存量（limit在被回收以后被赋予了新的意义）
    val firstLimit = first?.limit ?: 0
      // actual val MAX_SIZE = 64 * 1024 （64kb）
    if (firstLimit >= MAX_SIZE) {
      firstRef.set(first) // Pool is full.
      return
    }

    segment.next = first
    segment.pos = 0
      // 累加Segment Data Size
    segment.limit = firstLimit + Segment.SIZE
		// 头插法设置进入hash桶
    firstRef.set(segment)
  }

  private fun firstRef(): AtomicReference<Segment?> {
    // Get a value in [0..HASH_BUCKET_COUNT) based on the current thread.
    val hashBucket = (Thread.currentThread().id and (HASH_BUCKET_COUNT - 1L)).toInt()
    return hashBuckets[hashBucket]
  }
}
```



- SegmentPool是基于链表头插法生成的池
- SegmentPool有大小限制，默认为64Kb不能扩容
- SegmentPool为了满足多并发，采用了hash桶+自旋锁解决并发问题。
- hash桶的大小≈2 * CPU - 1
- 并发策略即是，没有发生线程竞争则对Segment进行缓存，否则跳过缓存。



> 池化

> 每次`pop`后都会通过调用`recycle`回收`Segment`

![image-20230403224106766](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403224106766.png)



> 而每次`Segment`的获取会通过`take`

![image-20230403224235301](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403224235301.png)



## Sink



> Sink类似于一个OuputStream

> 它的实现类如下



![image-20230403175233802](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403175233802.png)



> 最后翻源码发现Buffer，RealBufferedSink的实现都是借助于commonMain模块的扩展方法。

![image-20230403175741516](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403175741516.png)



> 我们重点挑几个方法看看实现原理

> `Sink`和`BufferedSink`都挑几个分析实现

![image-20230403175922024](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403175922024.png)



![image-20230403175943596](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403175943596.png)





> 可以发现
>
> - `Sink`方法注重的时**通用**即什么业务都可以调用它。
>
> - `BufferedSink`注重实用，基础数据类型，String，等均是可以的



### Sink.write

> 调用commonMain工具方法。

```kotlin
override fun write(source: Buffer, byteCount: Long): Unit = commonWrite(source, byteCount)
```

> 写入

```kotlin
internal inline fun Buffer.commonWrite(source: Buffer, byteCount: Long) {
    // 记录写入长度
  var byteCount = byteCount
  
	// check
  require(source !== this) { "source == this" }
  checkOffsetAndCount(source.size, 0, byteCount)

    // 写入内容直到写入完全
  while (byteCount > 0L) {
    // 写入的长度如果小于source一个段的大小
    if (byteCount < source.head!!.limit - source.head!!.pos) {
      val tail = if (head != null) head!!.prev else null
        // 写入的段容量足以容纳byteCount大小的数据
      if (tail != null && tail.owner &&
        byteCount + tail.limit - (if (tail.shared) 0 else tail.pos) <= Segment.SIZE
      ) {
        // 写入后修改参数并返回
        source.head!!.writeTo(tail, byteCount.toInt())
        source.size -= byteCount
        size += byteCount
        return
      } else {
        // 写入的段内容不足以容纳byteCount长度
        // 将source的head拆分成两段 [0,byteCount) [byteCount,len)
        source.head = source.head!!.split(byteCount.toInt())
      }
    }

    // 将head移除
    val segmentToMove = source.head
    val movedByteCount = (segmentToMove!!.limit - segmentToMove.pos).toLong()
    source.head = segmentToMove.pop()
      // destination head没有初始化，将segmentToMove作为head
    if (head == null) {
      head = segmentToMove
      segmentToMove.prev = segmentToMove
      segmentToMove.next = segmentToMove.prev
    } else {
        // 如果初始化了
        // 将切分的[0,byteCount)段直接添加到tail，并尝试与tail.prev进行合并
      var tail = head!!.prev
      tail = tail!!.push(segmentToMove)
      tail.compact()
    }
      // 更新buffer的size等参数。
    source.size -= movedByteCount
    size += movedByteCount
    byteCount -= movedByteCount
  }
}
```



> 简单讲述一下写入逻辑。
>
> - 由于Buffer是由一个个的Segment组成，而每个Segemnt又是由byte[]组成
>
> - 写入过程中会遇上两种情况
>
>   - 写入的长度小于一个Segment
>
>     将一个Segment切成两部分，[0,byteCount) [byteCount,len)，并将[0,byteCount)这一块Segment直接append入Buffer
>
>   - 写入长度大于一个Segment
>
>     依此将Segment放入Buffer中。



> 由此我们发现`Sink.write`写入的基本单位不是字节，而是`Segement`，直接将`Segement`从一个`Buffer`转移到另外一个`Buffer`中





### BufferedSink.writeXX



- `writeInt`

```kotlin
actual override fun writeInt(i: Int): Buffer = commonWriteInt(i)
```

```kotlin
internal inline fun Buffer.commonWriteInt(i: Int): Buffer {
  val tail = writableSegment(4)
  val data = tail.data
  var limit = tail.limit
  data[limit++] = (i ushr 24 and 0xff).toByte()
  data[limit++] = (i ushr 16 and 0xff).toByte()
  data[limit++] = (i ushr  8 and 0xff).toByte() // ktlint-disable no-multi-spaces
  data[limit++] = (i         and 0xff).toByte() // ktlint-disable no-multi-spaces
  tail.limit = limit
  size += 4L
  return this
}
```



- writeLong

```kotlin
actual override fun writeLong(v: Long): Buffer = commonWriteLong(v)
```

```kotlin
internal inline fun Buffer.commonWriteLong(v: Long): Buffer {
  val tail = writableSegment(8)
  val data = tail.data
  var limit = tail.limit
  data[limit++] = (v ushr 56 and 0xffL).toByte()
  data[limit++] = (v ushr 48 and 0xffL).toByte()
  data[limit++] = (v ushr 40 and 0xffL).toByte()
  data[limit++] = (v ushr 32 and 0xffL).toByte()
  data[limit++] = (v ushr 24 and 0xffL).toByte()
  data[limit++] = (v ushr 16 and 0xffL).toByte()
  data[limit++] = (v ushr  8 and 0xffL).toByte() // ktlint-disable no-multi-spaces
  data[limit++] = (v         and 0xffL).toByte() // ktlint-disable no-multi-spaces
  tail.limit = limit
  size += 8L
  return this
}
```



> 类似的writeXXX都是会先调用`writableSegment`接着修改data。

> 其中writableSegment是用于准备足够的空间。

```kotlin
internal inline fun Buffer.commonWritableSegment(minimumCapacity: Int): Segment {
  require(minimumCapacity >= 1 && minimumCapacity <= Segment.SIZE) { "unexpected capacity" }
	// 如果head为null初始化
  if (head == null) {
    val result = SegmentPool.take() // Acquire a first segment.
    head = result
    result.prev = result
    result.next = result
    return result
  }

  var tail = head!!.prev
    // 如果内存容量不足minimumCapacity开辟新的空间
  if (tail!!.limit + minimumCapacity > Segment.SIZE || !tail.owner) {
    tail = tail.push(SegmentPool.take()) // Append a new empty segment to fill up.
  }
  return tail
}
```





## Source



> Source类似于OutputStream



![image-20230403203804664](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403203804664.png)



![image-20230403203817928](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403203817928.png)



### Source.read

> 总的来说比较简单。就是将实现委托给了sink

```kotlin
override fun read(sink: Buffer, byteCount: Long): Long = commonRead(sink, byteCount)
```

```kotlin
internal inline fun Buffer.commonRead(sink: Buffer, byteCount: Long): Long {
  var byteCount = byteCount
    // read的长度必须大于等于0
  require(byteCount >= 0L) { "byteCount < 0: $byteCount" }
  if (size == 0L) return -1L
    // 如果读取的量超过了buffer的容量
  if (byteCount > size) byteCount = size
    // 将内容写入sink中
  sink.write(this, byteCount)
   	// 返回读取个数
  return byteCount
}
```



### BufferedSource.readXXX

- readByte

```kotlin
override fun readByte(): Byte = commonReadByte()
```

```kotlin
internal inline fun Buffer.commonReadByte(): Byte {
  if (size == 0L) throw EOFException()
	// 从head开始读取
  val segment = head!!
  var pos = segment.pos
  val limit = segment.limit
	// 读取data累计pos
  val data = segment.data
  val b = data[pos++]
  size -= 1L
	// 如果pos和limit重合，该segment已经读取完全
  if (pos == limit) {
      // 探测出当前segment
    head = segment.pop()
      // 并回收
    SegmentPool.recycle(segment)
  } else {
      // 如果没有读取完更新pos
    segment.pos = pos
  }

  return b
}
```

- readInt

```kotlin
override fun readInt(): Int = commonReadInt()
```

```kotlin
internal inline fun Buffer.commonReadInt(): Int {
  if (size < 4L) throw EOFException()

  val segment = head!!
  var pos = segment.pos
  val limit = segment.limit

  // If the int is split across multiple segments, delegate to readByte().
    // segment小于4，按字节读取
  if (limit - pos < 4L) {
    return (
      readByte() and 0xff shl 24
        or (readByte() and 0xff shl 16)
        or (readByte() and 0xff shl 8) // ktlint-disable no-multi-spaces
        or (readByte() and 0xff)
      )
  }
	// 大于4直接读取segment data
  val data = segment.data
  val i = (
    data[pos++] and 0xff shl 24
      or (data[pos++] and 0xff shl 16)
      or (data[pos++] and 0xff shl 8)
      or (data[pos++] and 0xff)
    )
    // 更新参数
  size -= 4L
	
  if (pos == limit) {
    head = segment.pop()
    SegmentPool.recycle(segment)
  } else {
    segment.pos = pos
  }

  return i
}
```



## Timeout

> 无论是`Sink`还是`Source`都可以设置超时器。

> 所谓超时器即超过一定的时间终止任务。

超时器分为两类

- 同步超时器

  当前线程触发中断

- 异步超时器

  异步线程触发中断



### 同步超时器

> 即`Timeout`

设置参数以后在，每一次read/write时都会调用

```kotlin
open fun throwIfReached() {
    if (Thread.currentThread().isInterrupted) {
      // If the current thread has been interrupted.
      throw InterruptedIOException("interrupted")
    }

    if (hasDeadline && deadlineNanoTime - System.nanoTime() <= 0) {
      throw InterruptedIOException("deadline reached")
    }
  }
```

> 比如OutputSink

> 看了我们也能发现如果Sink/Source不调用超时器，我们是没办法做到中断的

```kotlin
fun OutputStream.sink(): Sink = OutputStreamSink(this, Timeout())

private class OutputStreamSink(
  private val out: OutputStream,
  private val timeout: Timeout
) : Sink {

  override fun write(source: Buffer, byteCount: Long) {
    checkOffsetAndCount(source.size, 0, byteCount)
    var remaining = byteCount
    while (remaining > 0) {
      timeout.throwIfReached()
      val head = source.head!!
      val toCopy = minOf(remaining, head.limit - head.pos).toInt()
      out.write(head.data, head.pos, toCopy)

      head.pos += toCopy
      remaining -= toCopy
      source.size -= toCopy

      if (head.pos == head.limit) {
        source.head = head.pop()
        SegmentPool.recycle(head)
      }
    }
  }

  override fun flush() = out.flush()

  override fun close() = out.close()

  override fun timeout() = timeout

  override fun toString() = "sink($out)"
}
```



### 异步超时器

> 即`AsyncTimeout`

> 如果看过OkHttp的源码会发现有很多异步超时器的调用

```kotlin
fun enter() {
  val timeoutNanos = timeoutNanos()
  val hasDeadline = hasDeadline()
  if (timeoutNanos == 0L && !hasDeadline) {
    return // No timeout and no deadline? Don't bother with the queue.
  }
    // 开启计时
  scheduleTimeout(this, timeoutNanos, hasDeadline)
}

/** Returns true if the timeout occurred.  */
fun exit(): Boolean {
    // 任务完成取消计时
  return cancelScheduledTimeout(this)
}
```



> 计时

```kotlin
private fun scheduleTimeout(node: AsyncTimeout, timeoutNanos: Long, hasDeadline: Boolean) {
  AsyncTimeout.lock.withLock {
    check(!node.inQueue) { "Unbalanced enter/exit" }
    node.inQueue = true

      // 如果计时器第一次开启
    if (head == null) {
        // 初始化watchDog
      head = AsyncTimeout()
      Watchdog().start()
    }

      // 计算超时时间
    val now = System.nanoTime()
    if (timeoutNanos != 0L && hasDeadline) {
      // Compute the earliest event; either timeout or deadline. Because nanoTime can wrap
      // around, minOf() is undefined for absolute values, but meaningful for relative ones.
      node.timeoutAt = now + minOf(timeoutNanos, node.deadlineNanoTime() - now)
    } else if (timeoutNanos != 0L) {
      node.timeoutAt = now + timeoutNanos
    } else if (hasDeadline) {
      node.timeoutAt = node.deadlineNanoTime()
    } else {
      throw AssertionError()
    }

    // 在队列中以时间排序
    val remainingNanos = node.remainingNanos(now)
    var prev = head!!
    while (true) {
      if (prev.next == null || remainingNanos < prev.next!!.remainingNanos(now)) {
        node.next = prev.next
        prev.next = node
        if (prev === head) {
          // Wake up the watchdog when inserting at the front.
          condition.signal()
        }
        break
      }
      prev = prev.next!!
    }
  }
}
```



### WatchDog

```kotlin
private class Watchdog internal constructor() : Thread("Okio Watchdog") {
  init {
    isDaemon = true
  }

  override fun run() {
      // 等待任务执行，超时即调用timeout方法
    while (true) {
      try {
        var timedOut: AsyncTimeout? = null
        AsyncTimeout.lock.withLock {
          timedOut = awaitTimeout()

          // head是一个虚节点，如果出队的为虚节点，表明timeout已经全部处理完成。
          if (timedOut === head) {
            head = null
            return
          }
        }

        // 触发超时
        timedOut?.timedOut()
      } catch (ignored: InterruptedException) {
      }
    }
  }
}
```



## 小结



> Okio的核心就是用到了Segment，在进行拷贝的时候为了达到高效，直接以Segment作为单位进行传递，而且由于Segment是做了池化处理的，不会出现对象的重复创建。



> 除此之外Timeout也算是Okio设计地不错地地方，其中Timeout分为同步计时和异步计时两种，同步计时需要调用者时不时调用Timeout方法，而异步计时则开辟一个看门狗线程从Timeout队列里拿取超时地Timeout调用其timeOut方法（每一次enter方法scheduleTimeout会将Timeout放入Timeout队列中）



> Okio概述图



![image-20230403223337674](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230403223337674.png)
