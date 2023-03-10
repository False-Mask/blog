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



## 概念



### RX

RX是什么意思



> Reactive Extensions即响应式扩展，所谓的响应式的核心既是设计模式中的观察者模式。

> 除此之外还切分了**上下游关系**，下游**观察**上游，上游向下游**发送事件**



> 很不直观？没能理解他带来的便利？

> 那来对比一下写法



> 假如你想完成一个**异步任务**，很容易想到需要接口回调。（异步任务在多线程编程中普遍存在）

> 抽象如下（很简陋）

```java
// 任务实体
interface Task {
    void start();

    void start(TaskListener listener);
}
// 任务完成监听
interface TaskListener {
    void onFinished();
}
```



> 假如有3个Task需要依照如下顺序完成。TaskA -> TaskB -> TaskC

```java
class TaskA implements Task {
    //......
}

class TaskB implements Task {
    //......
}

class TaskC implements Task {
    //......
}
```



> none-Reactive

```java
public class Test {

    public static void main(String[] args) {

        Task taskA;
        Task taskB;
        Task taskC;
        // 初始化...
        init();
        // 开启任务
        taskA.start(new TaskListener() {
            @Override
            public void onFinished() {
                taskB.start(new TaskListener() {
                    @Override
                    public void onFinished() {
                        taskC.start(new TaskListener() {
                            @Override
                            public void onFinished() {
								// finished all tasks
                            }
                        });
                    }
                });
            }
        });

    }

}
```



> Reactive (伪代码)

```java
taskA.toObserver()
    .map {
    	taskB.start()
	}
	.map {
        taskC.start()
    }
```





> R是一种思想

> RX是Reactive的一种实现



### Rxjava



> ReactiveX是一个用于解决异步事件的编程库

> 它使用了观察者模式，并且有很多的操作符可以以声明式的方式将不同的流组合在一起。

> 同时他封装了线程，同步，线程安全，并发容器，非阻塞式IO



### Why Rxjava

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





