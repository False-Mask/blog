---
title: Java Thread
date: 2023-02-24 11:21:26
tags:
- java
- 操作系统
categories:
- java
---

# Java Thread 







## 构造函数

> 数目很多，但是全部都会调用到private的6参构造方法

```java
public Thread() {
    this(null, null, "Thread-" + nextThreadNum(), 0);
}

public Thread(Runnable target) {
    this(null, target, "Thread-" + nextThreadNum(), 0);
}

public Thread(String name) {
    this(null, null, name, 0);
}

public Thread(ThreadGroup group, Runnable target) {
    this(group, target, "Thread-" + nextThreadNum(), 0);
}

public Thread(Runnable target, String name) {
    this(null, target, name, 0);
}

public Thread(ThreadGroup group, String name) {
    this(group, null, name, 0);
}

public Thread(ThreadGroup group, Runnable target, String name) {
    this(group, target, name, 0);
}

public Thread(ThreadGroup group, Runnable target, String name,
                  long stackSize) {
     this(group, target, name, stackSize, null, true);
}

public Thread(ThreadGroup group, Runnable target, String name,
                  long stackSize, boolean inheritThreadLocals) {
     this(group, target, name, stackSize, null, inheritThreadLocals);
}

```



```java
Thread(Runnable target, AccessControlContext acc) {
    this(null, target, "Thread-" + nextThreadNum(), 0, acc, false);
}
```



```java
private Thread(ThreadGroup g, Runnable target, String name,
               long stackSize, AccessControlContext acc,
               boolean inheritThreadLocals) {
    // 参数校验
    if (name == null) {
        throw new NullPointerException("name cannot be null");
    }
	
    this.name = name;
	// 获取父线程
    Thread parent = currentThread();
    SecurityManager security = System.getSecurityManager();
    if (g == null) {
        /* Determine if it's an applet or not */

        /* If there is a security manager, ask the security manager
           what to do. */
        if (security != null) {
            g = security.getThreadGroup();
        }

        /* If the security manager doesn't have a strong opinion
           on the matter, use the parent thread group. */
        if (g == null) {
            g = parent.getThreadGroup();
        }
    }

    /* checkAccess regardless of whether or not threadgroup is
       explicitly passed in. */
    g.checkAccess();

    /*
     * Do we have the required permissions?
     */
    if (security != null) {
        if (isCCLOverridden(getClass())) {
            security.checkPermission(
                    SecurityConstants.SUBCLASS_IMPLEMENTATION_PERMISSION);
        }
    }

    g.addUnstarted();

    this.group = g;
    // daemon和优先级继承自父线程
    this.daemon = parent.isDaemon();
    this.priority = parent.getPriority();
    if (security == null || isCCLOverridden(parent.getClass()))
        this.contextClassLoader = parent.getContextClassLoader();
    else
        this.contextClassLoader = parent.contextClassLoader;
    this.inheritedAccessControlContext =
            acc != null ? acc : AccessController.getContext();
    this.target = target;
    setPriority(priority);
    // 机场parent的threadLocal
    if (inheritThreadLocals && parent.inheritableThreadLocals != null)
        this.inheritableThreadLocals =
            ThreadLocal.createInheritedMap(parent.inheritableThreadLocals);
    /* Stash the specified stack size in case the VM cares */
    this.stackSize = stackSize;

    /* Set thread ID */
    this.tid = nextThreadID();
}
```



> 构造函数只完成了参数的配置



## 静态工具方法



### 获取当前线程

```
public static native Thread currentThread();
```

> 查找方法表

![image-20230224160223525](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224160223525.png)



> 断点

![image-20230224160455317](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224160455317.png)



> jvm在运行时会记录当前的thread

![image-20230224160902239](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224160902239.png)



> 使用时即可直接返回

![image-20230224160933855](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224160933855.png)



### 线程让位

> A hint to the scheduler that the current thread is willing to yield its current use of a processor
>
> 向调度器表示出让当前线程的时间片

```java
public static native void yield();
```

> 通过系统调用出让cpu执行时间片

![image-20230224162927208](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224162927208.png)

![image-20230224162949942](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224162949942.png)





### 线程休眠

> 使得线程进入休眠

```java
public static void sleep(long millis, int nanos)
throws InterruptedException {
    if (millis < 0) {
        throw new IllegalArgumentException("timeout value is negative");
    }

    if (nanos < 0 || nanos > 999999) {
        throw new IllegalArgumentException(
                            "nanosecond timeout value out of range");
    }
	// 四舍五入
    if (nanos >= 500000 || (nanos != 0 && millis == 0)) {
        millis++;
    }
	// sleep
    sleep(millis);
}
```



```java
public static native void sleep(long millis) throws InterruptedException;
```



> 断点

![image-20230224194223331](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224194223331.png)



> 睡眠

![image-20230224194313891](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224194313891.png)



> 暂停

![image-20230224194413244](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224194413244.png)



> 睡眠

![image-20230224195000645](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224195000645.png)





### 是否打断



```java
public static boolean interrupted() {
    return currentThread().isInterrupted(true);
}
```



```java
private native boolean isInterrupted(boolean ClearInterrupted);
```



![image-20230224200007109](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224200007109.png)



> 获取是都被打断

![image-20230224200041890](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224200041890.png)

![image-20230224200105482](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224200105482.png)



### 获取组内的线程数

> Returns an estimate of the number of active threads in the current thread's thread group and its subgroups.
>
> 返回在当前线程组的线程数量和子组的线程数

```java
public static int activeCount() {
    return currentThread().getThreadGroup().activeCount();
}
```



```java
public int activeCount() {
    int result;
    // Snapshot sub-group data so we don't hold this lock
    // while our children are computing.
    int ngroupsSnapshot;
    ThreadGroup[] groupsSnapshot;
    synchronized (this) {
        if (destroyed) {
            return 0;
        }
        // 当前组线程数
        result = nthreads;
        // 子group
        ngroupsSnapshot = ngroups;
        if (groups != null) {
            groupsSnapshot = Arrays.copyOf(groups, ngroupsSnapshot);
        } else {
            groupsSnapshot = null;
        }
    }
    // 遍历每一个group返回count累加和
    for (int i = 0 ; i < ngroupsSnapshot ; i++) {
        result += groupsSnapshot[i].activeCount();
    }
    return result;
}
```



### 拷贝组内的活跃线程



```java
public static int enumerate(Thread tarray[]) {
    return currentThread().getThreadGroup().enumerate(tarray);
}
```



```java
private int enumerate(Thread list[], int n, boolean recurse) {
    int ngroupsSnapshot = 0;
    ThreadGroup[] groupsSnapshot = null;
    synchronized (this) {
        if (destroyed) {
            return 0;
        }
        int nt = nthreads;
        if (nt > list.length - n) {
            nt = list.length - n;
        }
        // 拷贝组内线程
        for (int i = 0; i < nt; i++) {
            if (threads[i].isAlive()) {
                list[n++] = threads[i];
            }
        }
        if (recurse) {
            ngroupsSnapshot = ngroups;
            if (groups != null) {
                groupsSnapshot = Arrays.copyOf(groups, ngroupsSnapshot);
            } else {
                groupsSnapshot = null;
            }
        }
    }
    // 拷贝子组的线程
    if (recurse) {
        for (int i = 0 ; i < ngroupsSnapshot ; i++) {
            n = groupsSnapshot[i].enumerate(list, n, true);
        }
    }
    return n;
}
```



### 获取堆栈信息

```java
public static void dumpStack() {
    new Exception("Stack trace").printStackTrace();
}
```





### 判断是否含有对象锁

```java
public static native boolean holdsLock(Object obj);
```

> 判断当前进程是否包含对象锁

![image-20230224203146520](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224203146520.png)



> 如果当前object的对象头中含有锁标志位，判断锁标准是否执行当前线程
>
> 如果没有判断对象头中是否有monitor，判断当前进程是否进入临界区。（synchronized代码块）

![image-20230224203319795](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230224203319795.png)



### 获取group内线程的堆栈

```java
public static Map<Thread, StackTraceElement[]> getAllStackTraces() {
    // check for getStackTrace permission
    SecurityManager security = System.getSecurityManager();
    if (security != null) {
        security.checkPermission(
            SecurityConstants.GET_STACK_TRACE_PERMISSION);
        security.checkPermission(
            SecurityConstants.MODIFY_THREADGROUP_PERMISSION);
    }

    // Get a snapshot of the list of all threads
    // 获取所有线程
    Thread[] threads = getThreads();
    // 获取堆栈信息
    StackTraceElement[][] traces = dumpThreads(threads);
    Map<Thread, StackTraceElement[]> m = new HashMap<>(threads.length);
    for (int i = 0; i < threads.length; i++) {
        StackTraceElement[] stackTrace = traces[i];
        if (stackTrace != null) {
            m.put(threads[i], stackTrace);
        }
        // else terminated so we don't put it in the map
    }
    return m;
}
```



### 未捕获异常处理器

> get

```java
public static UncaughtExceptionHandler getDefaultUncaughtExceptionHandler(){
    return defaultUncaughtExceptionHandler;
}
```

> set

```java
public static void setDefaultUncaughtExceptionHandler(UncaughtExceptionHandler eh) {
    SecurityManager sm = System.getSecurityManager();
    if (sm != null) {
        sm.checkPermission(
            new RuntimePermission("setDefaultUncaughtExceptionHandler")
                );
    }

     defaultUncaughtExceptionHandler = eh;
 }
```



> 未捕获异常传递

> Dispatch an uncaught exception to the handler. This method is intended to be called only by the JVM.
>
> 当遇上未捕获异常时首先jvm会调用此函数

```java
private void dispatchUncaughtException(Throwable e) {
    getUncaughtExceptionHandler().uncaughtException(this, e);
}
```

> 接着进入了调度方法。
>
> 先委派给ThreadGroup处理异常
>
> 如果ThreadGroup为null则自己处理。
>
> 获取defaultUncaughtExceptionHandler，并调用uncaughtException。
>
> 否则调用默认实现。

```java
public void uncaughtException(Thread t, Throwable e) {
    if (parent != null) {
        parent.uncaughtException(t, e);
    } else {
        Thread.UncaughtExceptionHandler ueh =
            Thread.getDefaultUncaughtExceptionHandler();
        if (ueh != null) {
            ueh.uncaughtException(t, e);
        } else if (!(e instanceof ThreadDeath)) {
            System.err.print("Exception in thread \""
                             + t.getName() + "\" ");
            e.printStackTrace(System.err);
        }
    }
}
```



## 线程创建

> demo



```java
Thread t = new Thread(()->{
    System.out.println("Hello Thread!");
});
t.start();
```

```java
class MyThread extends Thread {

    @Override
    public void run() {

        System.out.println("Hello from my Thread");
    }
}

MyThread m = new MyThread();
        m.start();
```



> 开启线程

```java
public synchronized void start() {
    /**
     * This method is not invoked for the main method thread or "system"
     * group threads created/set up by the VM. Any new functionality added
     * to this method in the future may have to also be added to the VM.
     *
     * A zero status value corresponds to state "NEW".
     */
    if (threadStatus != 0)
        throw new IllegalThreadStateException();

    /* Notify the group that this thread is about to be started
     * so that it can be added to the group's list of threads
     * and the group's unstarted count can be decremented. */
    // 添加到线程组
    group.add(this);

    boolean started = false;
    try {
        // jni
        start0();
        started = true;
    } finally {
        // 判断是否正常开启
        try {
            if (!started) {
                group.threadStartFailed(this);
            }
        } catch (Throwable ignore) {
            /* do nothing. If start0 threw a Throwable then
              it will be passed up the call stack */
        }
    }
}
```



![image-20230225102931051](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225102931051.png)

> 创建线程实体

![image-20230225103020235](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225103020235.png)



![image-20230225113553700](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225113553700.png)



![image-20230225113653749](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225113653749.png)



![image-20230225113730837](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225113730837.png)



> 开启线程

![image-20230225103112097](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225103112097.png)



![image-20230225103139276](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225103139276.png)

> 将线程状态设置为Runnable

![image-20230225103219239](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225103219239.png)

> notify

![image-20230225113815261](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225113815261.png)

![image-20230225114230124](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225114230124.png)



## 线程控制



### 停止



#### suspend/resume



- suspend

> 即挂起线程

```java
@Deprecated(since="1.2")
public final void suspend() {
    checkAccess();
    suspend0();
}
```

![image-20230225155847881](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225155847881.png)



> 设置线程状态

![image-20230225155915335](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225155915335.png)



![image-20230225160423157](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225160423157.png)



> 通知os挂起线程

![image-20230225160522107](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225160522107.png)



> 修改了线程的状态标识，然后就挂起了。（不是特别清楚原理）



- resume

```java
@Deprecated(since="1.2")
public final void resume() {
    checkAccess();
    resume0();
}
```

![image-20230225162500784](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162500784.png)



> 唤醒线程

![image-20230225162619300](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162619300.png)

> 唤醒

![image-20230225162645258](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162645258.png)



> 清除挂起标记

![image-20230225162725285](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162725285.png)



![image-20230225162752701](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162752701.png)



> 唤醒线程

![image-20230225162909723](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225162909723.png)





#### stop

> 通过stop使得线程停止。（Deprecated）

```java
public final void stop() {
    SecurityManager security = System.getSecurityManager();
    // 权限鉴别
    if (security != null) {
        checkAccess();
        if (this != Thread.currentThread()) {
            security.checkPermission(SecurityConstants.STOP_THREAD_PERMISSION);
        }
    }
    // A zero status value corresponds to "NEW", it can't change to
    // not-NEW because we hold the lock.
    // 如果进程已经start
    if (threadStatus != 0) {
        // 如果处于挂起状态唤醒线程
        resume(); // Wake up thread if it was suspended; no-op otherwise
    }

    // The VM can handle all thread states
    stop0(new ThreadDeath());
}
```



![image-20230225163146764](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225163146764.png)

> 发送消息入队列

![image-20230225163206951](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225163206951.png)





![image-20230225163247772](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225163247772.png)



### 打断

> If this thread is blocked in an invocation of the wait(), wait(long), or wait(long, int) methods of the Object class, or of the join(), join(long), join(long, int), sleep(long), or sleep(long, int), methods of this class, then its interrupt status will be cleared and it will receive an InterruptedException.
>
> 如果线程由于wait，join，sleep处于阻塞状态，可以使用interrupt方法中断等待

```java
public void interrupt() {
    if (this != Thread.currentThread()) {
        checkAccess();

        // thread may be blocked in an I/O operation
        // 可能由于io而等待
        synchronized (blockerLock) {
            Interruptible b = blocker;
            if (b != null) {
                // 打断
                interrupt0();  // set interrupt status
                b.interrupt(this);
                return;
            }
        }
    }

    // set interrupt status
    interrupt0();
}
```



> 查看线程是否存活，存活则进行打断

![image-20230225164622269](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225164622269.png)



![image-20230225164702415](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225164702415.png)



![image-20230225164741752](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225164741752.png)

> 发送信号量

![image-20230225164846354](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230225164846354.png)





### 同步



```java
public final void join() throws InterruptedException {
    join(0);
}
```



```java
public final synchronized void join(long millis, int nanos)
throws InterruptedException {

    if (millis < 0) {
        throw new IllegalArgumentException("timeout value is negative");
    }

    if (nanos < 0 || nanos > 999999) {
        throw new IllegalArgumentException(
                            "nanosecond timeout value out of range");
    }
	// 无法精准采用把控时间，四舍五入
    if (nanos >= 500000 || (nanos != 0 && millis == 0)) {
        millis++;
    }

    join(millis);
}
```



```java
public final synchronized void join(long millis)
throws InterruptedException {
    long base = System.currentTimeMillis();
    long now = 0;

    if (millis < 0) {
        throw new IllegalArgumentException("timeout value is negative");
    }

    if (millis == 0) {
        while (isAlive()) {
            wait(0);
        }
    } else {
        // 等待足够长的时间
        while (isAlive()) {
            long delay = millis - now;
            if (delay <= 0) {
                break;
            }
            wait(delay);
            now = System.currentTimeMillis() - base;
        }
    }
}
```



### 状态修改



#### name

```java
public final synchronized void setName(String name) {
    checkAccess();
    if (name == null) {
        throw new NullPointerException("name cannot be null");
    }

    this.name = name;
    if (threadStatus != 0) {
        setNativeName(name);
    }
}

public final String getName() {
        return name;
    }
```

> 修改native线程的名称，不过只支持修改当前线程

![image-20230226111912507](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226111912507.png)



> 格式化字符串，设置pthread nane

![image-20230226112138447](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226112138447.png)



#### priority

```java
public final void setPriority(int newPriority) {
    ThreadGroup g;
    checkAccess();
    if (newPriority > MAX_PRIORITY || newPriority < MIN_PRIORITY) {
        throw new IllegalArgumentException();
    }
    if((g = getThreadGroup()) != null) {
        if (newPriority > g.getMaxPriority()) {
            newPriority = g.getMaxPriority();
        }
        setPriority0(priority = newPriority);
    }
}

public final int getPriority() {
        return priority;
    }
```



![image-20230226112735882](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226112735882.png)



![image-20230226112751023](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226112751023.png)



![image-20230226112807554](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226112807554.png)

> 需要系统支持priority否则就是直接return，调试的时候发现并没有调用到setpriority方法。所以java的线程优先级应该对于linux是无感的（也可能是没做好线程优先级相关设置的配置）。
>
> 总之java线程优先级和linux线程优先级是不太一样的。

![image-20230226113107665](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230226113107665.png)



#### daemon



> Marks this thread as either a daemon thread or a user thread. The Java Virtual Machine exits when the only threads running are all daemon threads
>
> 将线程标记成用户线程或者守护线程。jvm在退出时会忽略守护线程

```java
public final void setDaemon(boolean on) {
    checkAccess();
    if (isAlive()) {
        throw new IllegalThreadStateException();
    }
    daemon = on;
}
```





#### contextClassLoader

> 当一个线程调用一个类的静态方法或实例化一个对象时，Java虚拟机会使用线程的`contextClassLoader`来查找相应的类。
>
> 如果线程没有设置`contextClassLoader`，则默认使用当前类的ClassLoader。
>
> 如果线程需要加载的类和资源文件无法通过当前ClassLoader找到，它会尝试使用`contextClassLoader`来加载这些类和资源文件。

> 正是由于contextClassLoader的存在使得父classLoader可以使用子classLoader，在一些特殊的情况下类加载更为灵活。

```java
public void setContextClassLoader(ClassLoader cl) {
    SecurityManager sm = System.getSecurityManager();
    if (sm != null) {
        sm.checkPermission(new RuntimePermission("setContextClassLoader"));
    }
    contextClassLoader = cl;
}

```

```java
public ClassLoader getContextClassLoader() {
    if (contextClassLoader == null)
        return null;
    SecurityManager sm = System.getSecurityManager();
    if (sm != null) {
        ClassLoader.checkClassLoaderPermission(contextClassLoader,
                                               Reflection.getCallerClass());
    }
    return contextClassLoader;
}
```



#### exceptionHandler

> 设置默认的未捕获异常处理器

> 注意是异常已经发生了，并且没有被处理。

```java
public void setUncaughtExceptionHandler(UncaughtExceptionHandler eh) {
    checkAccess();
    uncaughtExceptionHandler = eh;
}
```

```java
public UncaughtExceptionHandler getUncaughtExceptionHandler() {
    return uncaughtExceptionHandler != null ?
        uncaughtExceptionHandler : group;
}
```



> 此方法在当前线程发生异常的时候会调用

```java
private void dispatchUncaughtException(Throwable e) {
    getUncaughtExceptionHandler().uncaughtException(this, e);
}
```



### 状态获取



#### id

> 表示线程的long值

```java
public long getId() {
        return tid;
    }
```

> 在线程构造函数中，累加线程号。

```java
private Thread(ThreadGroup g, Runnable target, String name,
                   long stackSize, AccessControlContext acc,
                   boolean inheritThreadLocals) {
// ....
    this.tid = nextThreadID();
// ....    
}
```



```java
private static synchronized long nextThreadID() {
    return ++threadSeqNumber;
}
```



#### 状态



```java
public State getState() {
    // get current thread state
    return jdk.internal.misc.VM.toThreadState(threadStatus);
}
```

> java线程状态有
>
> - RUNNABLE
>
>   线程处于运行状态，但也可能是处于等待操作系统分配如实现片等资源。
>
> - BLOCKED
>
>   线程等待获取对象锁，对象等待进入同步代码块
>
> - WAITING
>
>   线程无限期等待另一个线程，如下方法可能出发
>
>   - Object.wait with no timeout
>   - Thread.join with no timeout
>   - LockSupport.park
>
> - TIMED_WAITING
>
>   线程等待触发条件，但并非无限期，超过等待时间即刻唤醒。
>
>   - Object.wait with timeout
>   - Thread.join with timeout
>   - LockSupport.parkNanos
>   - LockSupport.parkUntil
>
> - TERMINATED
>
>   线程完成执行
>
> - NEW
>
>   线程被创建但并未start（执行了构造函数没执行start）

```java
public static Thread.State toThreadState(int threadStatus) {
    if ((threadStatus & JVMTI_THREAD_STATE_RUNNABLE) != 0) {
        return RUNNABLE;
    } else if ((threadStatus & JVMTI_THREAD_STATE_BLOCKED_ON_MONITOR_ENTER) != 0) {
        return BLOCKED;
    } else if ((threadStatus & JVMTI_THREAD_STATE_WAITING_INDEFINITELY) != 0) {
        return WAITING;
    } else if ((threadStatus & JVMTI_THREAD_STATE_WAITING_WITH_TIMEOUT) != 0) {
        return TIMED_WAITING;
    } else if ((threadStatus & JVMTI_THREAD_STATE_TERMINATED) != 0) {
        return TERMINATED;
    } else if ((threadStatus & JVMTI_THREAD_STATE_ALIVE) == 0) {
        return NEW;
    } else {
        return RUNNABLE;
    }
}
```



#### 线程组

> 线程组会在thread构造函数中指定，如果构造函数传入的是null，默认会继承当前线程的group

> thread group用于管理线程

```java
public final ThreadGroup getThreadGroup() {
    return group;
}
```





## 总结



- Java Thread只是包在外面的一层壳，核心实现是空的，需要借助JNI

- JNI层的线程是对平台线程的封装，Linux则是封装的pthread
