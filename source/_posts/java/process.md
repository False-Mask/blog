---
title: Java Process
tags:
- java
- 操作系统
categories:
- java
---



# Java基础之Process

>进程属于是操作系统的资源，Java对其亦是开箱支持的

> 相关的类有
>
> - `java.lang.Process`
> - `java.lang.ProcessBuilder`
> - `java.lang.ProcessHandle`



## Process



> Process是一个抽象类，只有一套模板

```java
public abstract class Process
```



### IO

```java
public abstract OutputStream getOutputStream();

public abstract InputStream getInputStream();

public abstract InputStream getErrorStream();
```



### 同步

```java
// 使得当前线程一直等待，直到进程执行完毕
public abstract int waitFor() throws InterruptedException;
```

```java
// 等待指定时间，超时即退出
public boolean waitFor(long timeout, TimeUnit unit)
    throws InterruptedException
{
    long startTime = System.nanoTime();
    long rem = unit.toNanos(timeout);

    do {
        try {
            exitValue();
            return true;
        } catch(IllegalThreadStateException ex) {
            if (rem > 0)
                Thread.sleep(
                    Math.min(TimeUnit.NANOSECONDS.toMillis(rem) + 1, 100));
        }
        rem = unit.toNanos(timeout) - (System.nanoTime() - startTime);
    } while (rem > 0);
    return false;
}
```



### 控制相关

```java
// 进程的退出的result code，如果调用的时候没有退出即返回IllegalThreadStateException
public abstract int exitValue();
```



```java
// 杀死process
public abstract void destroy();
```



```java
public Process destroyForcibly() {
    destroy();
    return this;
}
```

```java
// 判断进程是否存活
public boolean isAlive() {
    try {
        exitValue();
        return false;
    } catch(IllegalThreadStateException e) {
        return true;
    }
}
```



```java
// 返回进程pid
public long pid() {
    return toHandle().pid();
}
```



```java
// 进程退出触发事件
public CompletableFuture<Process> onExit() {
    return CompletableFuture.supplyAsync(this::waitForInternal);
}
```



```java
// 转换为进程句柄
public ProcessHandle toHandle() {
    throw new UnsupportedOperationException(this.getClass()
            + ".toHandle() not supported");
}
```



```java
// 获取进程详细信息
public ProcessHandle.Info info() {
    return toHandle().info();
}
```



```java
// 获取直接子进程
public Stream<ProcessHandle> children() {
    return toHandle().children();
}
```



## ProcessBuilder

> 一个用于构造Process的类



### 构造函数

```java
// 传入command为一个list
public ProcessBuilder(List<String> command) {
    if (command == null)
        throw new NullPointerException();
    this.command = command;
}
```



```java
// 传入command为变长参数
public ProcessBuilder(String... command) {
    this.command = new ArrayList<>(command.length);
    for (String arg : command)
        this.command.add(arg);
}
```



### 命令行参数

```java
public ProcessBuilder command(List<String> command) {
    if (command == null)
        throw new NullPointerException();
    this.command = command;
    return this;
}
```



```java
public ProcessBuilder command(String... command) {
    this.command = new ArrayList<>(command.length);
    for (String arg : command)
        this.command.add(arg);
    return this;
}
```





### 设置工作路径

```java
public ProcessBuilder directory(File directory) {
    this.directory = directory;
    return this;
}
```



### 重定向

```java
public ProcessBuilder redirectInput(Redirect source) {
    if (source.type() == Redirect.Type.WRITE ||
        source.type() == Redirect.Type.APPEND)
        throw new IllegalArgumentException(
            "Redirect invalid for reading: " + source);
    redirects()[0] = source;
    return this;
}
```



```java
public ProcessBuilder redirectOutput(Redirect destination) {
    if (destination.type() == Redirect.Type.READ)
        throw new IllegalArgumentException(
            "Redirect invalid for writing: " + destination);
    redirects()[1] = destination;
    return this;
}
```



```java
public ProcessBuilder redirectError(Redirect destination) {
    if (destination.type() == Redirect.Type.READ)
        throw new IllegalArgumentException(
            "Redirect invalid for writing: " + destination);
    redirects()[2] = destination;
    return this;
}
```



```java
public ProcessBuilder redirectInput(File file) {
    return redirectInput(Redirect.from(file));
}
```



```java
public ProcessBuilder redirectOutput(File file) {
    return redirectOutput(Redirect.to(file));
}
```



```java
public ProcessBuilder redirectError(File file) {
    return redirectError(Redirect.to(file));
}
```



```java
// 重定向到当前进程的io
public ProcessBuilder inheritIO() {
    Arrays.fill(redirects(), Redirect.INHERIT);
    return this;
}
```



```java
// 是否将error 流重定向到标准输出流
public ProcessBuilder redirectErrorStream(boolean redirectErrorStream) {
    this.redirectErrorStream = redirectErrorStream;
    return this;
}
```



### 创建进程

```java
// 直接开启单个进程
public Process start() throws IOException {
    return start(redirects);
}
```



```java
private Process start(Redirect[] redirects) throws IOException {
    // Must convert to array first -- a malicious user-supplied
    // list might try to circumvent the security check.
    // 读取配置参数
    String[] cmdarray = command.toArray(new String[command.size()]);
    cmdarray = cmdarray.clone();

    for (String arg : cmdarray)
        if (arg == null)
            throw new NullPointerException();
    // Throws IndexOutOfBoundsException if command is empty
    String prog = cmdarray[0];

    SecurityManager security = System.getSecurityManager();
    if (security != null)
        security.checkExec(prog);

    String dir = directory == null ? null : directory.toString();

    for (int i = 1; i < cmdarray.length; i++) {
        if (cmdarray[i].indexOf('\u0000') >= 0) {
            throw new IOException("invalid null character in command");
        }
    }

    try {// 开启进程
        return ProcessImpl.start(cmdarray,
                                 environment,
                                 dir,
                                 redirects,
                                 redirectErrorStream);
    } catch (IOException | IllegalArgumentException e) {
        // 异常抛出
        String exceptionInfo = ": " + e.getMessage();
        Throwable cause = e;
        if ((e instanceof IOException) && security != null) {
            // Can not disclose the fail reason for read-protected files.
            try {
                security.checkRead(prog);
            } catch (SecurityException se) {
                exceptionInfo = "";
                cause = se;
            }
        }
        // It's much easier for us to create a high-quality error
        // message than the low-level C code which found the problem.
        throw new IOException(
            "Cannot run program \"" + prog + "\""
            + (dir == null ? "" : " (in directory \"" + dir + "\")")
            + exceptionInfo,
            cause);
    }
}
```



```java
// 以管道的方式开启多个进程
public static List<Process> startPipeline(List<ProcessBuilder> builders) throws IOException {
    // Accumulate and check the builders
    final int numBuilders = builders.size();
    List<Process> processes = new ArrayList<>(numBuilders);
    try {
        Redirect prevOutput = null;
        // 除了第一个和最后一个，input，和output必须是pipe模式
        // 前一个的input是后一个的output
        for (int index = 0; index < builders.size(); index++) {
            ProcessBuilder builder = builders.get(index);
            Redirect[] redirects = builder.redirects();
            if (index > 0) {
                // check the current Builder to see if it can take input from the previous
                if (builder.redirectInput() != Redirect.PIPE) {
                    throw new IllegalArgumentException("builder redirectInput()" +
                            " must be PIPE except for the first builder: "
                            + builder.redirectInput());
                }
                redirects[0] = prevOutput;
            }
            if (index < numBuilders - 1) {
                // check all but the last stage has output = PIPE
                if (builder.redirectOutput() != Redirect.PIPE) {
                    throw new IllegalArgumentException("builder redirectOutput()" +
                            " must be PIPE except for the last builder: "
                            + builder.redirectOutput());
                }
                redirects[1] = new RedirectPipeImpl();  // placeholder for new output
            }
            processes.add(builder.start(redirects));
            prevOutput = redirects[1];
        }
    } catch (Exception ex) {
        // Cleanup processes already started
        processes.forEach(Process::destroyForcibly);
        processes.forEach(p -> {
            try {
                p.waitFor();        // Wait for it to exit
            } catch (InterruptedException ie) {
                // If interrupted; continue with next Process
                Thread.currentThread().interrupt();
            }
        });
        throw ex;
    }
    return processes;
}
```





## ProcessHandle



### 静态工具方法

> 根据pid获取ProcessHandle

```java
public static Optional<ProcessHandle> of(long pid) {
    return ProcessHandleImpl.get(pid);
}
```



> 获取当前进程

```java
public static ProcessHandle current() {
    return ProcessHandleImpl.current();
}
```



> 获取所有进程

```java
static Stream<ProcessHandle> allProcesses() {
    return ProcessHandleImpl.children(0);
}
```



> 获取info

```java
Info info();
```

```java
public interface Info {
    // 可执行文件路径
    public Optional<String> command();

    // 命令行参数
    public Optional<String> commandLine();

    // 参数
    public Optional<String[]> arguments();

   	// 进程开启时间
    public Optional<Instant> startInstant();

    // cpu占用时间
    public Optional<Duration> totalCpuDuration();

    // 用户
    public Optional<String> user();
}
```









### 基础信息



> 获取pid

```java
long pid();
```



> 获取父进程

```java
Optional<ProcessHandle> parent();
```



> 获取直接子进程

```java
Stream<ProcessHandle> children();
```



> 获取所有子进程

```java
Stream<ProcessHandle> descendants();
```



> 获取是否属存活

```java
boolean isAlive();
```



> 是否支持normal termination

> 以正常的result code终止进程

```java
boolean supportsNormalTermination();
```



### 监听

> 退出监听

```java
CompletableFuture<ProcessHandle> onExit();
```




### 控制



> kill

```java
boolean destroy();
```

```java
boolean destroyForcibly();
```



## 类关联关系

![image-20230222154741801](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222154741801.png)





## 实现原理分析

> Process属于操作系统的抽象，底层肯定是依靠操作系统实现的，所以大致我们能猜到一点，他的实现绝对离不开jni。

> Java -> JNI -> C/C++ -> 操作系统

> 类关系图中只有两个实现类
>
> - `ProcessImpl`
> - `ProcessHandleImpl`

> Note:
>
> 基于Linux环境分析实现

### ProcessImpl

> Process的实现类（有且仅有这一个实现）



#### Process创建



> 测试代码

```java
public class Test {

    public static void main(String[] args) throws IOException {

        ProcessBuilder builder = new ProcessBuilder("java", "--version");
        builder.start();

    }

}
```



> ProcessImpl的获取在于一个名为start的静态方法

```java
static Process start(String[] cmdarray,
                         java.util.Map<String,String> environment,
                         String dir,
                         ProcessBuilder.Redirect[] redirects,
                         boolean redirectErrorStream)
            throws IOException
    {
        assert cmdarray != null && cmdarray.length > 0;

        // Convert arguments to a contiguous block; it's easier to do
        // memory management in Java than in C.
        byte[][] args = new byte[cmdarray.length-1][];
        int size = args.length; // For added NUL bytes
        for (int i = 0; i < args.length; i++) {
            args[i] = cmdarray[i+1].getBytes();
            size += args[i].length;
        }
        byte[] argBlock = new byte[size];
        int i = 0;
        for (byte[] arg : args) {
            System.arraycopy(arg, 0, argBlock, i, arg.length);
            i += arg.length + 1;
            // No need to write NUL bytes explicitly
        }

        int[] envc = new int[1];
        byte[] envBlock = ProcessEnvironment.toEnvironmentBlock(environment, envc);

        int[] std_fds;

        FileInputStream  f0 = null;
        FileOutputStream f1 = null;
        FileOutputStream f2 = null;

        try {
            boolean forceNullOutputStream = false;
            if (redirects == null) {
                std_fds = new int[] { -1, -1, -1 };
            } else {
                std_fds = new int[3];
				// input
                if (redirects[0] == Redirect.PIPE) {
                    std_fds[0] = -1;
                } else if (redirects[0] == Redirect.INHERIT) {
                    std_fds[0] = 0;
                } else if (redirects[0] instanceof ProcessBuilder.RedirectPipeImpl) {
                    std_fds[0] = fdAccess.get(((ProcessBuilder.RedirectPipeImpl) redirects[0]).getFd());
                } else {
                    f0 = new FileInputStream(redirects[0].file());
                    std_fds[0] = fdAccess.get(f0.getFD());
                }
				// output
                if (redirects[1] == Redirect.PIPE) {
                    std_fds[1] = -1;
                } else if (redirects[1] == Redirect.INHERIT) {
                    std_fds[1] = 1;
                } else if (redirects[1] instanceof ProcessBuilder.RedirectPipeImpl) {
                    std_fds[1] = fdAccess.get(((ProcessBuilder.RedirectPipeImpl) redirects[1]).getFd());
                    // Force getInputStream to return a null stream,
                    // the fd is directly assigned to the next process.
                    forceNullOutputStream = true;
                } else {
                    f1 = new FileOutputStream(redirects[1].file(),
                            redirects[1].append());
                    std_fds[1] = fdAccess.get(f1.getFD());
                }
				// error
                if (redirects[2] == Redirect.PIPE) {
                    std_fds[2] = -1;
                } else if (redirects[2] == Redirect.INHERIT) {
                    std_fds[2] = 2;
                } else if (redirects[2] instanceof ProcessBuilder.RedirectPipeImpl) {
                    std_fds[2] = fdAccess.get(((ProcessBuilder.RedirectPipeImpl) redirects[2]).getFd());
                } else {
                    f2 = new FileOutputStream(redirects[2].file(),
                            redirects[2].append());
                    std_fds[2] = fdAccess.get(f2.getFD());
                }
            }
			// 创建进程实现类
            Process p = new ProcessImpl
                    (toCString(cmdarray[0]),
                            argBlock, args.length,
                            envBlock, envc[0],
                            toCString(dir),
                            std_fds,
                            forceNullOutputStream,
                            redirectErrorStream);
            if (redirects != null) { // 设置标准流
                // Copy the fd's if they are to be redirected to another process
                if (std_fds[0] >= 0 &&
                        redirects[0] instanceof ProcessBuilder.RedirectPipeImpl) {
                    fdAccess.set(((ProcessBuilder.RedirectPipeImpl) redirects[0]).getFd(), std_fds[0]);
                }
                if (std_fds[1] >= 0 &&
                        redirects[1] instanceof ProcessBuilder.RedirectPipeImpl) {
                    fdAccess.set(((ProcessBuilder.RedirectPipeImpl) redirects[1]).getFd(), std_fds[1]);
                }
                if (std_fds[2] >= 0 &&
                        redirects[2] instanceof ProcessBuilder.RedirectPipeImpl) {
                    fdAccess.set(((ProcessBuilder.RedirectPipeImpl) redirects[2]).getFd(), std_fds[2]);
                }
            }
            return p;
        } finally {
            // In theory, close() can throw IOException
            // (although it is rather unlikely to happen here)
            try { if (f0 != null) f0.close(); }
            finally {
                try { if (f1 != null) f1.close(); }
                finally { if (f2 != null) f2.close(); }
            }
        }
    }
```



> ProcessImpl构造函数

```java
private ProcessImpl(final byte[] prog,
                final byte[] argBlock, final int argc,
                final byte[] envBlock, final int envc,
                final byte[] dir,
                final int[] fds,
                final boolean forceNullOutputStream,
                final boolean redirectErrorStream)
            throws IOException {
		// fork并执行
        pid = forkAndExec(launchMechanism.ordinal() + 1,
                          helperpath,
                          prog,
                          argBlock, argc,
                          envBlock, envc,
                          dir,
                          fds,
                          redirectErrorStream);
    	// 创建handle对象
        processHandle = ProcessHandleImpl.getInternal(pid);

        try {
            doPrivileged((PrivilegedExceptionAction<Void>) () -> {
                initStreams(fds, forceNullOutputStream);
                return null;
            });
        } catch (PrivilegedActionException ex) {
            throw (IOException) ex.getException();
        }
    }
```



> 进程创建forkAndExec

![image-20230222225321943](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222225321943.png)





> 通过调用startChild获取pid

![image-20230222225404016](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222225404016.png)



> 对于非Solaris系统会调用vfork复制进程

![image-20230222225513176](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222225513176.png)



> vfork调用

![image-20230222225545934](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222225545934.png)



> 关于vfork

**vfork（建立一个新的进程）**

相关函数wait，[execve](https://baike.baidu.com/item/execve/4475693?fromModule=lemma_inlink)

头文件 #include<unistd.h>

定义函数pid_t vfork([void](https://baike.baidu.com/item/void/5126319?fromModule=lemma_inlink));



vfork()用法与fork()相似.但是也有区别,具体区别归结为以下4点:

1. fork():子进程拷贝父进程的**[数据](https://baike.baidu.com/item/数据?fromModule=lemma_inlink)**段，[代码段](https://baike.baidu.com/item/代码段?fromModule=lemma_inlink). vfork():子进程与父进程共享数据段.

2. fork():父子进程的执行次序不确定.vfork():保证子进程先运行，在调用exec或_exit之前与父进程数据是共享的,在它调用exec或_exit之后[父进程](https://baike.baidu.com/item/父进程?fromModule=lemma_inlink)才可能被调度运行。

3. vfork()保证[子进程](https://baike.baidu.com/item/子进程/12720718?fromModule=lemma_inlink)先运行，在她调用exec或_exit之后父进程才可能被调度运行。如果在调用这两个**[函数](https://baike.baidu.com/item/函数?fromModule=lemma_inlink)**之前子进程依赖于父进程的进一步动作，则会导致[死锁](https://baike.baidu.com/item/死锁/2196938?fromModule=lemma_inlink)。

4. 当需要改变共享[数据段](https://baike.baidu.com/item/数据段/5136260?fromModule=lemma_inlink)中变量的值，则拷贝父进程。



——from 百度百科



> 子进程执行

![image-20230222235256328](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222235256328.png)



![image-20230222235315541](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222235315541.png)



> 执行操作

![image-20230222235405240](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222235405240.png)



![image-20230222235502627](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230222235502627.png)





> 所以启动的原理其实也只是
>
> vfork + execvp





#### 同步

> 通过synchronized机制

```java
public synchronized int waitFor() throws InterruptedException {
        while (!hasExited) {
            wait();
        }
        return exitcode;
}

@Override
public synchronized boolean waitFor(long timeout, TimeUnit unit)
    throws InterruptedException
{
    long remainingNanos = unit.toNanos(timeout);    // throw NPE before other conditions
    if (hasExited) return true;
    if (timeout <= 0) return false;

    long deadline = System.nanoTime() + remainingNanos;
    do {
        TimeUnit.NANOSECONDS.timedWait(this, remainingNanos);
        if (hasExited) {
            return true;
        }
        remainingNanos = deadline - System.nanoTime();
    } while (remainingNanos > 0);
    return hasExited;
}
```



#### kill



```java
// 非强制kill
@Override
public void destroy() {
    destroy(false);
}

// 强制kill
@Override
public Process destroyForcibly() {
    destroy(true);
    return this;
}
```



> 实现

> 依靠ProcessHandle实现	

```java
private void destroy(boolean force) {
        switch (platform) {
                // linux，bsd，aix平台
            case LINUX:
            case BSD:
            case AIX:
                // There is a risk that pid will be recycled, causing us to
                // kill the wrong process!  So we only terminate processes
                // that appear to still be running.  Even with this check,
                // there is an unavoidable race condition here, but the window
                // is very small, and OSes try hard to not recycle pids too
                // soon, so this is quite safe.
                synchronized (this) {
                    if (!hasExited)
                        // 调用ProcessHandle
                        processHandle.destroyProcess(force);
                }
                try { stdin.close();  } catch (IOException ignored) {}
                try { stdout.close(); } catch (IOException ignored) {}
                try { stderr.close(); } catch (IOException ignored) {}
                break;
				// Solaris平台
            case SOLARIS:
                // There is a risk that pid will be recycled, causing us to
                // kill the wrong process!  So we only terminate processes
                // that appear to still be running.  Even with this check,
                // there is an unavoidable race condition here, but the window
                // is very small, and OSes try hard to not recycle pids too
                // soon, so this is quite safe.
                synchronized (this) {
                    if (!hasExited)
                        processHandle.destroyProcess(force);
                    try {
                        stdin.close();
                        if (stdout_inner_stream != null)
                            stdout_inner_stream.closeDeferred(stdout);
                        if (stderr instanceof DeferredCloseInputStream)
                            ((DeferredCloseInputStream) stderr)
                                .closeDeferred(stderr);
                    } catch (IOException e) {
                        // ignore
                    }
                }
                break;

            default: throw new AssertionError("Unsupported platform: " + platform);
        }
    }
```



### ProcessHandleImpl

> 进程句柄，用于控制进程



#### 句柄创建

> 核心既是pid，可以通过pid进行jni的调用获取相关信息

```java
processHandle = ProcessHandleImpl.getInternal(pid);
```

```java
  static ProcessHandleImpl getInternal(long pid) {
        return new ProcessHandleImpl(pid, isAlive0(pid));
    }
```

> isAlive0

```c
JNIEXPORT jlong JNICALL
Java_java_lang_ProcessHandleImpl_isAlive0(JNIEnv *env, jobject obj, jlong jpid) {
    pid_t pid = (pid_t) jpid;
    jlong startTime = 0L;
    jlong totalTime = 0L;
    // 获取parentPid和开始时间
    pid_t ppid = os_getParentPidAndTimings(env, pid, &totalTime, &startTime);
    return (ppid < 0) ? -1 : startTime;
}
```

> 本质就是读取/proc/%d/stat，然后将数据进行解析

![image-20230223130333237](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223130333237.png)

```java
private ProcessHandleImpl(long pid, long startTime) {
        this.pid = pid;
        this.startTime = startTime;
    }
```



#### 静态工具



> 依据pid获取进程句柄

```java
public static Optional<ProcessHandle> of(long pid) {
        return ProcessHandleImpl.get(pid);
    }
```

```java
static Optional<ProcessHandle> get(long pid) {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
    // 通过读取/proc/$pid/stat中的信息，判断进程是否存在。
        long start = isAlive0(pid);
        return (start >= 0)
                ? Optional.of(new ProcessHandleImpl(pid, start))
                : Optional.empty();
    }
```



>  获取当前进程句柄

```java
public static ProcessHandle current() {
      return ProcessHandleImpl.current();
}
```

```java
private static final ProcessHandleImpl current;

    static {
        initNative();
        long pid = getCurrentPid0();
        current = new ProcessHandleImpl(pid, isAlive0(pid));
    } 

public static ProcessHandleImpl current() {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
        return current;
    }
```

```c
JNIEXPORT jlong JNICALL
Java_java_lang_ProcessHandleImpl_getCurrentPid0(JNIEnv *env, jclass clazz) {
    // 获取当前的进程id
    pid_t pid = getpid();
    return (jlong) pid;
}
```



> 获取所有运行的进程

```java
static Stream<ProcessHandle> allProcesses() {
        return ProcessHandleImpl.children(0);
    }
```

```java
static Stream<ProcessHandle> children(long pid) {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
        int size = 100;
        long[] childpids = null;
        long[] starttimes = null;
        while (childpids == null || size > childpids.length) {
            childpids = new long[size];
            starttimes = new long[size];
            size = getProcessPids0(pid, childpids, null, starttimes);
        }

        final long[] cpids = childpids;
        final long[] stimes = starttimes;
        return IntStream.range(0, size).mapToObj(i -> new ProcessHandleImpl(cpids[i], stimes[i]));
    }
```

![image-20230223213932581](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223213932581.png)



![image-20230223213954724](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223213954724.png)



> 读取/proc路径

![image-20230223214414397](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223214414397.png)



> 遍历/proc路径

![image-20230223214607470](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223214607470.png)



> 所以实现和 ls /proc 没多大差别，因为linux一切皆文件，所以每一个进程在运行的时候就会在此路径开辟文件夹。（名称都是pid号），只要有pid就可以创建ProcessHandleImpl。接着就可以使用一系列调用获取进程信息。



#### 基础信息



##### 获取pid

```java
// 创建句柄会传入pid。
@Override
public long pid() {
   return pid;
}
```



##### 获取直接父进程

```java
public Optional<ProcessHandle> parent() {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
        long ppid = parent0(pid, startTime);
        if (ppid <= 0) {
            return Optional.empty();
        }
        return get(ppid);
    }
```



```java
JNIEXPORT jlong JNICALL
Java_java_lang_ProcessHandleImpl_parent0(JNIEnv *env,
                                        jobject obj,
                                        jlong jpid,
                                        jlong startTime) {
    pid_t pid = (pid_t) jpid;
    pid_t ppid;
	// 如果获取parent的是当前进程
    if (pid == getpid()) {
        // 调用标准函数
        ppid = getppid();
    } else {
        // 如果是其他进程调用获取父进程信息
        jlong start = 0L;
        jlong total = 0L;        // unused
        // 使用自定义的内部实现
        ppid = os_getParentPidAndTimings(env, pid, &total, &start);
        if (start != startTime && start != 0 && startTime != 0) {
            ppid = -1;
        }
    }
    return (jlong) ppid;
}
```



> 读取进程文件(/proc/$pid/stat)

![image-20230223220742966](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223220742966.png)

> 其中文件的第一个参数既是parentPid

![image-20230223220828141](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223220828141.png)

> 可知进程1977 parent为1976

```text
root@foolish-pc # cat /proc/1977/stat                                                                       

1977 (init) S 1976 1976 1976 0 -1 4194624 25 0 0 0 1 26 0 0 20 0 1 0 293027 2351104 26 18446744073709551615 2700608 3954436 140727491924432 0 0 0 65536 2147024638 65536 1 0 0 17 4 0 0 0 0 0 4043632 4047976 37527552 140727491927907 140727491927913 140727491927913 140727491928050 0
```



##### 获取直接子进程

```java
@Override
    public Stream<ProcessHandle> children() {
        // The native OS code selects based on matching the requested parent pid.
        // If the original parent exits, the pid may have been re-used for
        // this newer process.
        // Processes started by the original parent (now dead) will all have
        // start times less than the start of this newer parent.
        // Processes started by this newer parent will have start times equal
        // or after this parent.
        return children(pid).filter(ph -> startTime <= ((ProcessHandleImpl)ph).startTime);
    }
```

```java
static Stream<ProcessHandle> children(long pid) {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
        int size = 100;
        long[] childpids = null;
        long[] starttimes = null;
        while (childpids == null || size > childpids.length) {
            childpids = new long[size];
            starttimes = new long[size];
            // jni
            size = getProcessPids0(pid, childpids, null, starttimes);
        }

        final long[] cpids = childpids;
        final long[] stimes = starttimes;
        return IntStream.range(0, size).mapToObj(i -> new ProcessHandleImpl(cpids[i], stimes[i]));
    }
```

![image-20230223221746487](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223221746487.png)



![image-20230223221802180](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223221802180.png)

> 和前面allProcess一样，就是读取/proc路径，分析路径下/proc/$pid的所以stat文件，判断进程关系。

![image-20230223222529629](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230223222529629.png)



##### 获取所有子进程

> 核心原理就是通过获取所有进程，然后通过向下循环搜索直接子进程。

```java
@Override
    public Stream<ProcessHandle> descendants() {
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(new RuntimePermission("manageProcess"));
        }
        int size = 100;
        long[] pids = null;
        long[] ppids = null;
        long[] starttimes = null;
        while (pids == null || size > pids.length) {
            pids = new long[size];
            ppids = new long[size];
            starttimes = new long[size];
            // 获取所有进程
            size = getProcessPids0(0, pids, ppids, starttimes);
        }

        int next = 0;       // index of next process to check
        int count = -1;     // count of subprocesses scanned
        long ppid = pid;    // start looking for this parent
        long ppStart = 0;
        // Find the start time of the parent
        // 寻找当前进程的开启时间
        for (int i = 0; i < size; i++) {
            if (pids[i] == ppid) {
                ppStart = starttimes[i];
                break;
            }
        }
        do {
            // Scan from next to size looking for ppid with child start time
            // the same or later than the parent.
            // If found, exchange it with index next
            // 如果把进程层级关系想成是一个树，这个算法实现的就是向下搜索。
            for (int i = next; i < size; i++) {
                // 寻找当前线程的直接子进程
                if (ppids[i] == ppid &&
                        ppStart <= starttimes[i]) {
                    swap(pids, i, next);
                    swap(ppids, i, next);
                    swap(starttimes, i, next);
                    next++;
                }
            }
            // 当前进程的下一个子进程
            ppid = pids[++count];   // pick up the next pid to scan for
            // 子进程的开启时间
            ppStart = starttimes[count];    // and its start time
        } while (count < next);

        final long[] cpids = pids;
        final long[] stimes = starttimes;
        return IntStream.range(0, count).mapToObj(i -> new ProcessHandleImpl(cpids[i], stimes[i]));
    }
```



##### 获取详细信息



```java
	@Override
    public ProcessHandle.Info info() {
        return ProcessHandleImpl.Info.info(pid, startTime);
    }
```

```java
public static ProcessHandle.Info info(long pid, long startTime) {
            Info info = new Info();
            info.info0(pid);
            if (startTime != info.startTime) {
                info.command = null;
                info.arguments = null;
                info.startTime = -1L;
                info.totalTime = -1L;
                info.user = null;
            }
            return info;
        }
```



```c
JNIEXPORT void JNICALL
Java_java_lang_ProcessHandleImpl_00024Info_info0(JNIEnv *env,
                                                 jobject jinfo,
                                                 jlong jpid) {
    pid_t pid = (pid_t) jpid;
    pid_t ppid;
    jlong totalTime = -1L;
    jlong startTime = -1L;
	// 获取父进程pid
    ppid = os_getParentPidAndTimings(env, pid,  &totalTime, &startTime);
    if (ppid >= 0) {
        (*env)->SetLongField(env, jinfo, ProcessHandleImpl_Info_totalTimeID, totalTime);
        JNU_CHECK_EXCEPTION(env);

        (*env)->SetLongField(env, jinfo, ProcessHandleImpl_Info_startTimeID, startTime);
        JNU_CHECK_EXCEPTION(env);
    }
    // 获取参数
    os_getCmdlineAndUserInfo(env, jinfo, pid);
}
```

```c
void os_getCmdlineAndUserInfo(JNIEnv *env, jobject jinfo, pid_t pid) {
    int fd;
    int cmdlen = 0;
    char *cmdline = NULL, *cmdEnd = NULL; // used for command line args and exe
    char *args = NULL;
    jstring cmdexe = NULL;
    char fn[32];
    struct stat stat_buf;

    /*
     * Stat /proc/<pid> to get the user id
     */
    // 格式化字符串
    snprintf(fn, sizeof fn, "/proc/%d", pid);
    // 获取用户信息
    if (stat(fn, &stat_buf) == 0) {
        unix_getUserInfo(env, jinfo, stat_buf.st_uid);
        JNU_CHECK_EXCEPTION(env);
    }

    /*
     * Try to open /proc/<pid>/cmdline
     */
    // 字符串拼接
    strncat(fn, "/cmdline", sizeof fn - strnlen(fn, sizeof fn) - 1);
    if ((fd = open(fn, O_RDONLY)) < 0) {
        return;
    }

    do {                // Block to break out of on errors
        int i, truncated = 0;
        int count;
        char *s;

        /*
         * The path name read by readlink() is limited to PATH_MAX characters.
         * The content of /proc/<pid>/cmdline is limited to PAGE_SIZE characters.
         */
        cmdline = (char*)malloc((PATH_MAX > pageSize ? PATH_MAX : pageSize) + 1);
        if (cmdline == NULL) {
            break;
        }

        /*
         * On Linux, the full path to the executable command is the link in
         * /proc/<pid>/exe. But it is only readable for processes we own.
         */
        snprintf(fn, sizeof fn, "/proc/%d/exe", pid);
        // 读取链接地址
        if ((cmdlen = readlink(fn, cmdline, PATH_MAX)) > 0) {
            // null terminate and create String to store for command
            cmdline[cmdlen] = '\0';
            cmdexe = JNU_NewStringPlatform(env, cmdline);
            (*env)->ExceptionClear(env);        // unconditionally clear any exception
        }

        /*
         * The command-line arguments appear as a set of strings separated by
         * null bytes ('\0'), with a further null byte after the last
         * string. The last string is only null terminated if the whole command
         * line is not exceeding (PAGE_SIZE - 1) characters.
         */
        cmdlen = 0;
        s = cmdline;
        while ((count = read(fd, s, pageSize - cmdlen)) > 0) {
            cmdlen += count;
            s += count;
        }
        if (count < 0) {
            break;
        }
        // We have to null-terminate because the process may have changed argv[]
        // or because the content in /proc/<pid>/cmdline is truncated.
        cmdline[cmdlen] = '\0';
        if (cmdlen == pageSize && cmdline[pageSize - 1] != '\0') {
            truncated = 1;
        } else if (cmdlen == 0) {
            // /proc/<pid>/cmdline was empty. This usually happens for kernel processes
            // like '[kthreadd]'. We could try to read /proc/<pid>/comm in the future.
        }
        if (cmdlen > 0 && (cmdexe == NULL || truncated)) {
            // We have no exact command or the arguments are truncated.
            // In this case we save the command line from /proc/<pid>/cmdline.
            args = (char*)malloc(pageSize + 1);
            if (args != NULL) {
                memcpy(args, cmdline, cmdlen + 1);
                for (i = 0; i < cmdlen; i++) {
                    if (args[i] == '\0') {
                        args[i] = ' ';
                    }
                }
            }
        }
        i = 0;
        if (!truncated) {
            // Count the arguments
            cmdEnd = &cmdline[cmdlen];
            for (s = cmdline; *s != '\0' && (s < cmdEnd); i++) {
                s += strnlen(s, (cmdEnd - s)) + 1;
            }
        }
        // 设置参数
        unix_fillArgArray(env, jinfo, i, cmdline, cmdEnd, cmdexe, args);
    } while (0);

    if (cmdline != NULL) {
        free(cmdline);
    }
    if (args != NULL) {
        free(args);
    }
    if (fd >= 0) {
        close(fd);
    }
}
```

> 即通过使用stat函数 ，读取/proc/$pid/cmdline,/proc/$pid/exe获取info信息







##### 是否存活

> 判断进程是否存活

```java
public boolean isAlive() {
        long start = isAlive0(pid);
        return (start >= 0 && (start == startTime || start == 0 || startTime == 0));
    }
```

> 老熟人了，通过读取进程状态信息（/proc/$pid/stat）判断是否存活，存活则返回进程开启时间。

```c
JNIEXPORT jlong JNICALL
Java_java_lang_ProcessHandleImpl_isAlive0(JNIEnv *env, jobject obj, jlong jpid) {
    pid_t pid = (pid_t) jpid;
    jlong startTime = 0L;
    jlong totalTime = 0L;
    pid_t ppid = os_getParentPidAndTimings(env, pid, &totalTime, &startTime);
    return (ppid < 0) ? -1 : startTime;
}
```



#### 控制指令



##### 正常退出

> 即不强制退出，所以进程在指令下达以后还可以存活一段时间

```java
public boolean destroy() {
        return destroyProcess(false);
    }
```



```java
boolean destroyProcess(boolean force) {
        if (this.equals(current)) {
            throw new IllegalStateException("destroy of current process not allowed");
        }
        return destroy0(pid, startTime, force);
    }
```

```c
JNIEXPORT jboolean JNICALL
Java_java_lang_ProcessHandleImpl_destroy0(JNIEnv *env,
                                          jobject obj,
                                          jlong jpid,
                                          jlong startTime,
                                          jboolean force) {
    pid_t pid = (pid_t) jpid;
    // 如果是强制退出则发送SIGKILL信号,否则就是SIGTERM信号
    int sig = (force == JNI_TRUE) ? SIGKILL : SIGTERM;
    jlong start = Java_java_lang_ProcessHandleImpl_isAlive0(env, obj, jpid);

    if (start == startTime || start == 0 || startTime == 0) {
        // 发送信号
        return (kill(pid, sig) < 0) ? JNI_FALSE : JNI_TRUE;
    } else {
        return JNI_FALSE;
    }
}
```



#####  强制退出

> 发送信号后进程会尽可能快地退出

```java
public boolean destroyForcibly() {
        return destroyProcess(true);
    }
```





## 小结



- Process是操作系统的抽象一切实现都需要借助操作系统
- Java Process API是对操作系统进程的上层封装
- Java Process API底层通过vfork，execvp实现进程的创建执行
- Java Process API通过读取/proc文件夹获取进程信息
- Java Process API通过kill向进程发送停止请求，依据请求的程度分为软性和强制（信号量不同，`SIGKILL `，`SIGTERM`）









