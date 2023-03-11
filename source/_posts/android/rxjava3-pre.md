---
title: Rxjava3序言
date: 2023-03-09 20:46:08
tags:
- rxjava3
- android
categories:
- android
---



# Rxjava3



> Rxjava其实在很早以前有过学习和了解，但是当时由于没有记笔记的习惯，难以整理成体系化的笔记，零零散散。

> 本系列笔记学习基于`io.reactivex.rxjava3:rxjava:3.1.6`



## 概念



### RP



> RP即`Reactive Programming`(响应式编程)



>  所谓的响应式即变化是可传播的，即发生变化后这种变化会如同”病毒“一样扩散出去。



> 假如计算一个式子
>
> c = a + b
>
> 命令式和响应式写法如下



> None RP

```java
public class NoneRP {

    public static void main(String[] args) {
        int a = 1;
        int b = 2;

        int c = a + b;
		// 3
        System.out.println(c);

        a = 2;
        b = 3;
		// 由于逻辑处理没有采用响应式，所以a b的变化不会扩散到c，即abc的值互相独立，互不影响。
        System.out.println(c);

    }

}
```



> RP

```java
public class RP {


    public static void main(String[] args) {
        ObservableInt a = new ObservableInt(1);
        ObservableInt b = new ObservableInt(2);

        int[] c = {0};
		// 观察a的变化
        a.observer((oldV, newV) -> {
            c[0] += newV - oldV;
        });
		// 观察b的变化
        b.observer((oldV,newV)->{
            c[0] += newV - oldV;
        });
		// 3
        System.out.println(c[0]);
		// 修改a的值，由于采用了响应式的编程范式，a，b的变动会传播到c
        a.setV(2);
        // 4
        System.out.println(c[0]);

        b.setV(3);
        // 5
        System.out.println(c[0]);




    }

}

// 可观测的int值
class ObservableInt {

    private int v;

    private OnIntChange observer;

    public ObservableInt(int v) {
        this.v = v;
    }

    public int getV() {
        return v;
    }

    public void setV(int v) {
        observer.change(this.v, v);
        this.v = v;
    }

    public void observer(OnIntChange observer) {
        this.observer = observer;
        observer.change(0,v);
    }

}

// 观察监听
interface OnIntChange {
    void change(int from, int to);
}
```



### RX

*RX是什么意思？*



> RX（ReactiveX或Reactive Extensions）即响应式扩展，即用于实现响应式编程的框架



> 响应式的核心是设计模式中的观察者模式。

> 除此之外还切分了**上下游关系**，下游**观察**上游，上游向下游**发送事件**



> R是一种**思想**即上文所述RP

> RX是实现响应式的一种**框架**
>
> 是一个用于解决**异步事件**的编程库
>
> 它使用了**观察者模式**，并且有很多的**操作符**可以以声明式的方式将不同的流组合在一起。
>
> 同时他封装了**线程**，**同步**，**线程安全**，**并发容器**，**非阻塞式IO**



### Rxjava



> Rxjava是ReactiveX对于指定编程语言的实现

类似的还有

- RxJs
- Rx.NET
- RxScala
- RxClojure
- RxSwift
- RxCpp
- RxLua
- Rx.rb
- RxPY

......



## Why Rxjava

- callback存在问题

  > Callback解决了异步调用，阻塞的问题，但是由于异步需要嵌套一层回调。加大了编程效率。

- rxjava灵活

  - 可以指定数据流的线程
  - 可以指定数据流的顺序
  - 支持异步eventloop nio

- 提供了大量的操作符用于支持[响应式编程](https://zh.wikipedia.org/wiki/%E5%93%8D%E5%BA%94%E5%BC%8F%E7%BC%96%E7%A8%8B)



## 版本变动



Rxjava经历了3个版本的变动

- 1.X

  > 2018 3/13官方宣布停止更新，不再推出新版本。版本定格在**1.3.8**。
  >
  > No further development, support, maintenance, PRs and updates will happen

- 2.X

  > 2021 2/28官方宣布停止更新。最后版本定格在**2.2.21**

- 3.X

  > 目前最新版本，功能最为强大。



## 内容



> 在Rx中包含如下角色
>
> - `Observable`
>
>   即可观测的，可以被观察的。被观察者。在rx中观察观测被观察者（即Observable），被观察者可以向观察者发送一系列事件。
>
> - `Single`
>
>   一个只能发送一个事件的被观察者。（即一次性的Observable）
>
> - `Subject`
>
>   是观察者和被观察者的桥梁，**既**是一个**观察者**，**也**是一个**被观察者**，既可以发送数据也可以接受数据。
>
> - `Operator`
>
>   操作符，为是一系列功能的集合。
>
> - `Scheduler`
>
>   即调度器，为Observable添加多线程的调度支持。





## RxJava项目结构结构



### 项目依赖

![image-20230310220820058](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230310220820058.png)





> [reactive stream](https://github.com/reactive-streams/reactive-streams-jvm)
>
> The purpose of Reactive Streams is to provide a standard for asynchronous stream processing with non-blocking backpressure.
>
> Reactive Streams的目的在于提供**非阻塞**式**背压** **异步流**处理的标准



> 所谓标准既是一套抽象。（说人话就是一套接口）

![image-20230310221343995](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230310221343995.png)





### 项目公共API

> 即除internal包外的所有包

```java
module io.reactivex.rxjava3 {
    requires org.reactivestreams;
	// 一些注解，标注代码功能
    exports io.reactivex.rxjava3.annotations;
    // 核心包 包含如下抽象
    // Completable Flowable Maybe Observable Scheduler Single
    exports io.reactivex.rxjava3.core;
    // 包含各类disposable
    exports io.reactivex.rxjava3.disposables;
    // 异常
    exports io.reactivex.rxjava3.exceptions;
    // flowable
    exports io.reactivex.rxjava3.flowables;
    // 函数式接口
    exports io.reactivex.rxjava3.functions;
    // observable子类
    exports io.reactivex.rxjava3.observables;
    // 观察者
    exports io.reactivex.rxjava3.observers;
    // 操作符
    exports io.reactivex.rxjava3.operators;
    // 并行
    exports io.reactivex.rxjava3.parallel;
    // 插件
    exports io.reactivex.rxjava3.plugins;
    // Processor（reactive stream中的规范）
    exports io.reactivex.rxjava3.processors;
    // 调度器实现
    exports io.reactivex.rxjava3.schedulers;
    // subject
    exports io.reactivex.rxjava3.subjects;
    // subscriber（reactive stream中的规范）
    exports io.reactivex.rxjava3.subscribers;
}
```



![image-20230310221552417](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230310221552417.png)





### 抽象

![image-20230311111903622](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230311111903622.png)

> `Maybe`，`Observable`，`Single`，`Completable`的结构类似均包含如下抽象
>
> - XXXSource
>
>   可观测的数据源，通常是XXX的抽象，比如ObservableSource是Observable的抽象
>
> - XXXObserver
>
>   订阅关系中，下游需要在subscribe过程向上游传输观察者
>
> - XXXEmitter
>
>   订阅关系在，上游需要向下游发送事件，而这一部分内容由上游的Emitter实现
>
> - XXXOnSubscribe
>
>   订阅关系中的最上游。
>
> - XXXOperator
>
>   对**下游**的**observer**进行包裹hook。（`lift`操作符）
>
> - XXXTransformer
>
>   对**上游**的**数据源**进行转换（`compose`操作符）
>
> - XXXConverter
>
>   转换器，将数据源进行转换。（`to`操作符）



> `Flowable`支持背压（即实现了reactive stream规范），所以结构上有一定的差异
>
> - Publisher
>
>   同XXXSource，是Flowable的抽象
>
> - FlowSubscriber
>
>   同Observer是一个订阅者，需要在订阅过程中向上游传输。
>
> - FlowEmitter
>
> - FlowOnSubscribe
>
> - FlowOperator
>
> - FlowTransformer
>
> - FlowConverter



## 参考



- [Rxjava introduction](https://reactivex.io/intro.html)

- [Rxjava 中文版文档](https://mcxiaoke.gitbooks.io/rxdocs/content/)
