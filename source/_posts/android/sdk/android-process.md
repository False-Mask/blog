---
title: Android Process基础之创建
date: 2023-02-28 18:58:26
tags:
- android
- 操作系统
- sdk
categaries:
- android
- sdk
---



# Android Process



## Java Process API



> 直接通过Java Process API创建

```kotlin
const val TAG = "com.example.process"

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
		// 创建进程并开启
        val process = ProcessBuilder("echo","hello world")
            .start()
		// 等待至进程退出
        val waitFor = process.waitFor()
		// 如果程序正常退出
        if(waitFor ==0) {
            Log.e(TAG, String(process.inputStream.readBytes()) )
        } else {
            // 如果不正常退出
            Log.e(TAG,  String(process.errorStream.readBytes()))
        }

    }
}
```



### 原理

`ProcessBuilder`

```java
public Process start() throws IOException {
    //......
    
    try {
        return ProcessImpl.start(cmdarray,
                                 environment,
                                 dir,
                                 redirects,
                                 redirectErrorStream);
    } catch (IOException | IllegalArgumentException e) {
        //......
    }
}
```



`ProcessImpl`

```java
static Process start(String[] cmdarray,
                     java.util.Map<String,String> environment,
                     String dir,
                     ProcessBuilder.Redirect[] redirects,
                     boolean redirectErrorStream)
    throws IOException
{
    //......

    try {
        //.......
    return new UNIXProcess
        (toCString(cmdarray[0]),
         argBlock, args.length,
         envBlock, envc[0],
         toCString(dir),
             std_fds,
         redirectErrorStream);
    } finally {
        //......
    }
}
```



`UNIXProcess`

```java
UNIXProcess(final byte[] prog,
            final byte[] argBlock, final int argc,
            final byte[] envBlock, final int envc,
            final byte[] dir,
            final int[] fds,
            final boolean redirectErrorStream)
        throws IOException {

    pid = forkAndExec(prog,
                      argBlock, argc,
                      envBlock, envc,
                      dir,
                      fds,
                      redirectErrorStream);

    //......
}
```



> 开辟并执行

```java
private native int forkAndExec(byte[] prog,
                               byte[] argBlock, int argc,
                               byte[] envBlock, int envc,
                               byte[] dir,
                               int[] fds,
                               boolean redirectErrorStream)
    throws IOException;
```



[UNIXProcess_md.c](https://cs.android.com/android/platform/superproject/+/master:libcore/ojluni/src/main/native/UNIXProcess_md.c;l=922;drc=1fe17e6b3c4bb375d81e2c60a5a76af79377555f;bpv=0;bpt=1?q=forkAndExec&sq=&ss=android%2Fplatform%2Fsuperproject&hl=zh-cn)

```c
JNIEXPORT jint JNICALL
UNIXProcess_forkAndExec(JNIEnv *env,
                                       jobject process,
                                       jbyteArray prog,
                                       jbyteArray argBlock, jint argc,
                                       jbyteArray envBlock, jint envc,
                                       jbyteArray dir,
                                       jintArray std_fds,
                                       jboolean redirectErrorStream)
{
    // ....
    
	// 开启子进程
    resultPid = startChild(c);
    assert(resultPid != 0);

    //......
}
```

> fork进程

```c
static pid_t
startChild(ChildStuff *c) {
#if START_CHILD_USE_CLONE
#define START_CHILD_CLONE_STACK_SIZE (64 * 1024)
    /*
     * See clone(2).
     * Instead of worrying about which direction the stack grows, just
     * allocate twice as much and start the stack in the middle.
     */
    if ((c->clone_stack = malloc(2 * START_CHILD_CLONE_STACK_SIZE)) == NULL)
        /* errno will be set to ENOMEM */
        return -1;
    return clone(childProcess,
                 c->clone_stack + START_CHILD_CLONE_STACK_SIZE,
                 CLONE_VFORK | CLONE_VM | SIGCHLD, c);
#else
  #if START_CHILD_USE_VFORK
    /*
     * We separate the call to vfork into a separate function to make
     * very sure to keep stack of child from corrupting stack of parent,
     * as suggested by the scary gcc warning:
     *  warning: variable 'foo' might be clobbered by 'longjmp' or 'vfork'
     */
    volatile pid_t resultPid = vfork();
  #else
    /*
     * From Solaris fork(2): In Solaris 10, a call to fork() is
     * identical to a call to fork1(); only the calling thread is
     * replicated in the child process. This is the POSIX-specified
     * behavior for fork().
     */
    pid_t resultPid = fork();
  #endif
    // 子进程执行
    if (resultPid == 0)
        childProcess(c);
    assert(resultPid != 0);  /* childProcess never returns */
    return resultPid;
#endif /* ! START_CHILD_USE_CLONE */
}
```

> exec进程

```java
static int
childProcess(void *arg)
{
  	// .....
    // 执行
    JDK_execvpe(p->argv[0], p->argv, p->envv);

 WhyCantJohnnyExec:
    /* We used to go to an awful lot of trouble to predict whether the
     * child would fail, but there is no reliable way to predict the
     * success of an operation without *trying* it, and there's no way
     * to try a chdir or exec in the parent.  Instead, all we need is a
     * way to communicate any failure back to the parent.  Easy; we just
     * send the errno back to the parent over a pipe in case of failure.
     * The tricky thing is, how do we communicate the *success* of exec?
     * We use FD_CLOEXEC together with the fact that a read() on a pipe
     * yields EOF when the write ends (we have two of them!) are closed.
     */
    {
        int errnum = errno;
        restartableWrite(FAIL_FILENO, &errnum, sizeof(errnum));
    }
    closeInChild(FAIL_FILENO);
    _exit(-1);
    return 0;  /* Suppress warning "no return value from function" */
}
```

> exec

```c
static void
JDK_execvpe(const char *file,
            const char *argv[],
            const char *const envp[])
{
    // 执行
    if (envp == NULL || (char **) envp == environ) {
        execvp(file, (char **) argv);
        return;
    }

    if (*file == '\0') {
        errno = ENOENT;
        return;
    }

    if (strchr(file, '/') != NULL) {
        execve_with_shell_fallback(file, argv, envp);
    } else {
        /* We must search PATH (parent's, not child's) */
        char expanded_file[PATH_MAX];
        int filelen = strlen(file);
        int sticky_errno = 0;
        const char * const * dirs;
        for (dirs = parentPathv; *dirs; dirs++) {
            const char * dir = *dirs;
            int dirlen = strlen(dir);
            if (filelen + dirlen + 1 >= PATH_MAX) {
                errno = ENAMETOOLONG;
                continue;
            }
            memcpy(expanded_file, dir, dirlen);
            memcpy(expanded_file + dirlen, file, filelen);
            expanded_file[dirlen + filelen] = '\0';
            execve_with_shell_fallback(expanded_file, argv, envp);
            /* There are 3 responses to various classes of errno:
             * return immediately, continue (especially for ENOENT),
             * or continue with "sticky" errno.
             *
             * From exec(3):
             *
             * If permission is denied for a file (the attempted
             * execve returned EACCES), these functions will continue
             * searching the rest of the search path.  If no other
             * file is found, however, they will return with the
             * global variable errno set to EACCES.
             */
            switch (errno) {
            case EACCES:
                sticky_errno = errno;
                /* FALLTHRU */
            case ENOENT:
            case ENOTDIR:
#ifdef ELOOP
            case ELOOP:
#endif
#ifdef ESTALE
            case ESTALE:
#endif
#ifdef ENODEV
            case ENODEV:
#endif
#ifdef ETIMEDOUT
            case ETIMEDOUT:
#endif
                break; /* Try other directories in PATH */
            default:
                return;
            }
        }
        if (sticky_errno != 0)
            errno = sticky_errno;
    }
}
```



> Android JDK和OpenJDK的差异不大。都是通过fork+exec开启子进程的执行。



### 测试结果

> 测试parent进程是否是com.exmaple.process



```kotlin
private const val TAG = "com.example.process"

class JavaProcessAPI : AppCompatActivity() {

    private val binding by lazy {
        ActivityJavaProcessApiBinding.inflate(layoutInflater)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(binding.root)

        val process: Process = ProcessBuilder("sleep","1d")
            .start()


		// 输出进程的id
        binding.textView.text = process.toString()


    }

    companion object {
        @JvmStatic
        fun startActivity(activity: AppCompatActivity) {
            val intent = Intent(activity, JavaProcessAPI::class.java)
            activity.startActivity(intent)
        }
    }

}
```



> 运行图像

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230301184617332.png" alt="image-20230301184617332" style="zoom:25%;" />



> 输入如下指令

> 很明显可以发现新开辟进程的parent为activity进程

```shell
C:\Users\fool>adb shell

generic_x86:/ $ ps 28688
USER           PID  PPID     VSZ    RSS WCHAN            ADDR S NAME
u0_a134      28688 28621   11932   3068 0                   0 S sleep

generic_x86:/ $ ps -A | grep 28621
u0_a134      28621  1776 1924628 122328 0                   0 S com.example.process
u0_a134      28688 28621   11932   3068 0                   0 S sleep

generic_x86:/ $
```







## XML配置

> 只需在AndroidManifest.xml中配置。



> 在此之后当start `XMLConfiguredProcess`时activity就会运行在package:test进程

```xml
<application
	....>
    
    <activity
        android:name=".XMLConfiguredProcess"
        android:process=":test"
        android:exported="false" />
  
......

    <activity
        android:name=".MainActivity"
        android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />

            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>
    
</application>
```



### 测试

```kotlin
private const val TAG = "XMLConfigredProcess"

class XMLConfiguredProcess : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_xmlconfigured_process)
        Log.e(TAG, android.os.Process.myPid().toString() )
    }
    

    companion object {
        @JvmStatic
        fun startActivity(activity: AppCompatActivity) {
            val intent = Intent(activity, XMLConfiguredProcess::class.java)
            activity.startActivity(intent)
        }
    }

}
```



> 得到进程id

```text
2023-03-01 18:55:10.581 30665-30665 XMLConfigredProcess     com.example.process                  E  30665
```

> 通过xml配置的process的parent为zygote，
>
> zygote的parent为init进程

```shell
generic_x86:/ $ ps -A | grep 30665
u0_a134      30665  1776 1902920 122072 0                   0 S com.example.process:test

generic_x86:/ $ ps -A 1776
USER           PID  PPID     VSZ    RSS WCHAN            ADDR S NAME
root          1776     1 1733028 104476 0                   0 S zygote

generic_x86:/ $ ps -A 1
USER           PID  PPID     VSZ    RSS WCHAN            ADDR S NAME
root             1     0   31740   5884 0                   0 S init

generic_x86:/ $
```









# 区别



> Java Process API底层是通过forkAndExec开辟进程并执行命令行，所以父进程为执行进程

> 通过XML配置开辟的进程是由zygote孵化的，所以父进程为zygote

> 所以本质来说使用Java Process API和XML开启进程的本质区别即一个是自己管理Process，一个是由Android系统管理Process

