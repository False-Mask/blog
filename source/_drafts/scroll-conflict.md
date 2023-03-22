---
title: 滑动冲突
date: 2023-03-19 17:09:30
tags:
- android
categories:
- android
---



# 滑动冲突



> 滑动冲突指的是一个Layout布局中有**多个可滑动**的控件的时候，滑动状态出现**不符合预期**的行为的现象。



## 示例



### 界面结构

![image-20230319171355964](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230319171355964.png)



XML布局

```xml
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".conflate.ConflateActivity">


    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:layout_margin="10dp">

            <TextView
                android:id="@+id/textView"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="●从 Android 5.0 Lollipop 开始提供一套来支持嵌入的滑动效果，同样在最新的 Support V4 包中也提供了前向的兼容，有了嵌入滑动机制，就能实现很多很复杂的滑动效果，在 Android Design Support 库中非常重要的CoordinatorLayout 组件就是使用了这套机制，实现了 Toolbar 的收起和展开功能
                 \n● 看起来像带有 header 的 RecyclerView 在滑动，但其实是嵌套滑动
                 \n● layout_scrollFlags 和 layout_behavior 有很多可选值，配合起来可以实现多种效果，不只限于嵌套滑动。具体可以参考 API 文档。
                 \n● 使用 CoordinatorLayout 实现嵌套滑动比手动实现要好得多，既可以实现连贯的吸顶嵌套滑动，又支持 fling。而且是官方提供的布局，可以放心使用，出 bug 的几率很小，性能也不会有问题。不过也正是因为官方将其封装得很好，使用 CoordinatorLayout 很难实现比较复杂的嵌套滑动布局，比如多级嵌套滑动
                 \n● NestedScrolling提供了一套父 View 和子 View 滑动交互机制。要完成这样的交互，父 View 需要实现 NestedScrollingParent 接口，而子 View 需要实现 NestedScrollingChild 接口" />

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center_horizontal"
                android:text="---------------------我是分割线---------------------"/>

            <androidx.recyclerview.widget.RecyclerView
                android:id="@+id/rv"
                android:layout_width="match_parent"
                android:layout_height="match_parent" />
        </LinearLayout>
    </ScrollView>
</androidx.constraintlayout.widget.ConstraintLayout>
```



### 滑动状态



<video src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/%E6%BB%91%E5%8A%A8%E5%86%B2%E7%AA%81.mp4"></video>



### 原因分析



在View层级中有两个可滑动的View，`ScrollView`与`RecyclerView`，其中`ScrollView`是`RecyclerView`的Parent。

由于事件分发机制的存在所以

- 事件会有`ScrollView`分发给`RecyclerView`（如果手指触摸位置在`RecyclerView`附近）
- 事件会被ScrollView自己消费（如果手指触摸位置没有其他的控件消费）



但：

这种事件分发顺序会造成一个问题——**反用户直觉**。

在用户来看，一个可滑动的列表，应该是平坦的。所以在大多数用户（或者**正常**的产品经理）来看，应该是如下交互。



<video src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/%E6%97%A0%E6%BB%91%E5%8A%A8%E5%86%B2%E7%AA%81.mp4"></video>



## 解决方案



### 嵌套滑动



> 嵌套滑动可以看作是一种Android的事件处理框架。隶属于androidx
>
> ```groovy
> implementation "androidx.core:core:x.y.z"
> ```



#### 相关类



> 与嵌套滑动机制有关的有3个类



- `NestedChild`

  嵌套滑动的子View，类包含

  `NestedScrollingChild`->

  ​	`NestedScrollingChild2`->

  ​		`NestedScrollingChild3`->

  嵌套滑动经过了如上的上个版本。每次升级都是对接口内容的完善

- `NestedParent`

  嵌套滑动的父View，同`NestedChild`经历了3个版本的变迁。

- `NestedHelper`

  嵌套滑动中的Helper帮助类。

  为简便嵌套机制，为`NestedChild`与`NestedParent`提供了不少的工具方法。

  类包含`NestedScrollingParentHelper`、`NestedScrollingChildHelper`



#### 机制

