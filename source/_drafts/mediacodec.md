---
title: mediacodec
tags:
cover:
---
# MediaCodec 硬解原理分析


# 基础使用


- MediaCodec配置

```c++
AMediaCodec* codec = AMediaCodec_createDecoderByType(mime);

AMediaCodec_configure(codec, format, d->window, NULL, 0);
```

- AMediaExtractor

```c++
// 选择音轨
AMediaExtractor* ex = AMediaExtractor_new();
media_status_t err = AMediaExtractor_setDataSourceFd(  
ex, d->fd, static_cast<off64_t>(outStart), static_cast<off64_t>(outLen));  

MediaExtractor_selectTrack(ex, i);
```

- 启动

```c++
AMediaCodec_start(codec);
```

- 渲染

```c++
for (....) {

	// 从MediaCodec中取出Buffer
	ssize_t bufidx = AMediaCodec_dequeueInputBuffer(d->codec, 2000);
	auto buf = AMediaCodec_getInputBuffer(d->codec, bufidx, &bufsize);
	// 从MediaExtractor中读取一帧数据并写入到Buffer中
	auto sampleSize = AMediaExtractor_readSampleData(d->ex, buf, bufsize);
	// 将Buffer输入到MediaCodec
	AMediaCodec_queueInputBuffer(  
	    d->codec, bufidx, 0, sampleSize, presentationTimeUs,  
	    d->sawInputEOS ? AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM : 0);  
	// 解码下一帧  
	AMediaExtractor_advance(d->ex);

	
	// dequeue一个buffer
	AMediaCodec_dequeueOutputBuffer(d->codec, &info, 0);
	// 将buffer入队到surfaceflinger中
	AMediaCodec_releaseOutputBuffer(d->codec, status, info.size != 0);
	
	// sleep
}
```


站在MediaCodec的角度主要有如下几个周期
```c++
// 获取buffer
AMediaCodec_dequeueInputBuffer(...);
auto buf = AMediaCodec_getInputBuffer(...);

// 写入数据
// ......

// 入队buffer
AMediaCodec_queueInputBuffer(...);

// 获取outputBuffer
AMediaCodec_dequeueOutputBuffer(...);

// 获取buffer
AMediaCodec_getOutputBuffer(...);

// 二次处理(可选)
// ......

// 释放buffer
AMediaCodec_releaseOutputBuffer(...);
```


# 渲染原理


![CodecBuffer](https://developer.android.com/images/media/mediacodec_buffers.svg)


## AMediaExtractor

用于提取原始画面帧



## MediaCodec

用于将原始画面帧进行解码，获取图像帧