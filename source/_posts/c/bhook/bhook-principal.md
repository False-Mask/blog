---
title: bhook基础原理分析
tags:
  - bhook
  - c
  - plt hook
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240218165530385.png
date: 2024-02-18 16:57:53
---




# BHook原理解析



# 基础概念



## PLT/GOT hook



> BHook是一个plt/got hook框架。

> plt/got hook是指，利用动态链接过程的特点。
>
> 即——***使用PLT表作为跳板查got表来查询被调用函数的地址在哪***。
>
> 如果我们修改GOT表内的地址就可以实现劫持函数的执行过程。



示例

> test.c

```c
#include <stdio.h>
void sayHell() {
    printf("Hello World");
}
int main() {
    sayHello();
}
```

> PLT/GOT hook前

![image-20240216221802707](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240216221802707.png)



> hook 后

![image-20240216223205742](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240216223205742.png)



## Relocation



> 即重定位，讲符号引用转化为直接引用。

> 说直白点就是：
>
> 编译器在编译一个库函数调用的时候，编译器本身是不知道你调用的地址在哪，**所以会直接用0填充**
>
> 于此同时他会在.rela中生成一条记录（我们暂且称之为“坑位“），告知来着，哪个函数调用需要填充地址。
>
> Relocation即填坑的过程。



### 静态链接

> 对于静态链接，Relocation会在编译的时候完成。

`hello.c`

```c
#include <stdio.h>

void printHello() {
        printf("Hello World!\n");
}
```

`static.c`

```c
#include <stdio.h>

extern void printHello();

int main() {
        printHello();
}
```

> 编译静态库，编译调用文件

```shell
gcc -o hello.o -c hello.c # 编译Hello 文件
ar rc hello.a hello.o # 创建静态hello.a文件
```



> 验证一：函数调用是否是填充的0
>
> e8 00 00 00 00
>
> e8表示callq，00 00 00 00 表示相对于当前指令的偏移量。

```shell
➜  relocation objdump --disassemble=main static.o
......
0000000000000000 <main>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   b8 00 00 00 00          mov    $0x0,%eax
   9:   e8 00 00 00 00          callq  e <main+0xe>
   e:   b8 00 00 00 00          mov    $0x0,%eax
  13:   5d                      pop    %rbp
  14:   c3                      retq
```



>验证二：rela中是否有一条记录
>
>这条记录表明
>
>0x00000000000a地址处有一个“坑位”需要填充。
>
>0xa不就是callq处的00 00 00 00

```shell
➜  relocation readelf -r static.o

Relocation section '.rela.text' at offset 0x1f0 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
00000000000a  000a00000004 R_X86_64_PLT32    0000000000000000 printHello - 4

```



> 验证三：静态链接是否是在编译时就进行了relocation



> 首先我们先创建elf文件

```c
gcc -o static static.o hello.a -static
```



> 反编译查看。
>
> 很明显空位已经被填充了

```c
➜  relocation objdump --disassemble=main static

static:     file format elf64-x86-64
......

0000000000401c8d <main>:
  401c8d:       55                      push   %rbp
  401c8e:       48 89 e5                mov    %rsp,%rbp
  401c91:       b8 00 00 00 00          mov    $0x0,%eax
  401c96:       e8 07 00 00 00          callq  401ca2 <printHello>
  401c9b:       b8 00 00 00 00          mov    $0x0,%eax
  401ca0:       5d                      pop    %rbp
  401ca1:       c3                      retq
```



### 动态链接



> 使用的代码同上

> 编译文件

```c
➜  relocation gcc -o dynamic.o -c dynamic.c
➜  relocation gcc -o hello.o -c hello.c
```



> 创建静态库

```c
gcc -o libhello.so hello.o -shared -fPIC
```



> 链接

```c
gcc -o dynamic dynamic.o -L. -lhello -Wl,-rpath=.
```



> 验证一：是否预留的“坑位”
>
> 动态链接的“坑位”不是直接填充0，而是got表

```shell
# 查看main函数
➜  relocation objdump --disassemble=main dynamic

dynamic:     file format elf64-x86-64
......

0000000000001135 <main>:
    1135:       55                      push   %rbp
    1136:       48 89 e5                mov    %rsp,%rbp
    1139:       b8 00 00 00 00          mov    $0x0,%eax
    113e:       e8 ed fe ff ff          callq  1030 <printHello@plt>
    1143:       b8 00 00 00 00          mov    $0x0,%eax
    1148:       5d                      pop    %rbp
    1149:       c3                      retq

# 查看plt
➜  relocation objdump --disassemble=printHello@plt dynamic

dynamic:     file format elf64-x86-64
......

0000000000001030 <printHello@plt>: 
	# 直接jmp got表所在地址
    # 这个地址编译器生成默认的值是下一行代码的地址，即1036 
    1030:       ff 25 e2 2f 00 00       jmpq   *0x2fe2(%rip)        # 4018 <printHello>
    1036:       68 00 00 00 00          pushq  $0x0
    103b:       e9 e0 ff ff ff          jmpq   1020 <.plt>
    1040:       Address 0x0000000000001040 is out of bounds.

# 查看got表
➜  relocation readelf -x .got.plt dynamic

Hex dump of section '.got.plt':
 NOTE: This section has relocations against it, but these have NOT been applied to this dump.
 # got.plt的起始地址为4000,4018为0x1036（别忘了小端序） 
  0x00004000 d83d0000 00000000 00000000 00000000 .=..............
  0x00004010 00000000 00000000 36100000 00000000 ........6.......
```



> 验证二：是否生成了rela数据

> 当然生成了只是不同于静态链接的.rela.text。
>
> .rela.plt通常用于懒加载。
>
> 即调用plt跳板后让ld在这个地方填充放入函数地址

```shell
➜  relocation readelf -r dynamic

Relocation section '.rela.plt' at offset 0x560 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000004018  000200000007 R_X86_64_JUMP_SLO 0000000000000000 printHello + 0
```







# 初始化



## java

> Java部分主要提供一层API，其实啥也没做。
>
> 一层层最后调用到JNI。



> Application

```java
public class XXXApplication extends Application {
    
    // ......
	
    @Override
    protected void attachBaseContext(Context base) {
        
        super.attachBaseContext(base);
     	int r = ByteHook.init(new ByteHook.ConfigBuilder()
                    // ......
                    .build());   
        
        
    }
    
    // ......
    
    
}
```



> 初始化

```java
public static synchronized int init(Config config) {
        // 防止重复初始化 
        if (inited) {
            return initStatus;
        }
        inited = true;

   		// ......

        // load libbytehook.so

        // call native bytehook_init()
        try {
            initStatus = nativeInit(config.getMode(), config.getDebug());
        } catch (Throwable ignored) {
            initStatus = ERRNO_INIT_EXCEPTION;
        }

        initCostMs = System.currentTimeMillis() - start;
        return initStatus;
    }
```



> Note:
>
> JNI注册表
>
> ```java
> JNINativeMethod m[] = {{"nativeGetVersion", "()Ljava/lang/String;", (void *)bh_jni_get_version},
>                          {"nativeInit", "(IZ)I", (void *)bh_jni_init},
>                          {"nativeAddIgnore", "(Ljava/lang/String;)I", (void *)bh_jni_add_ignore},
>                          {"nativeGetMode", "()I", (void *)bh_jni_get_mode},
>                          {"nativeGetDebug", "()Z", (void *)bh_jni_get_debug},
>                          {"nativeSetDebug", "(Z)V", (void *)bh_jni_set_debug},
>                          {"nativeGetRecordable", "()Z", (void *)bh_jni_get_recordable},
>                          {"nativeSetRecordable", "(Z)V", (void *)bh_jni_set_recordable},
>                          {"nativeGetRecords", "(I)Ljava/lang/String;", (void *)bh_jni_get_records},
>                          {"nativeGetArch", "()Ljava/lang/String;", (void *)bh_jni_get_arch}};
> 
> ```
>
> 



> 初始化

```C
static jint bh_jni_init(JNIEnv *env, jobject thiz, jint mode, jboolean debug) {
  (void)env;
  (void)thiz;

  return bytehook_init((int)mode, (bool)debug);
}

int bytehook_init(int mode, bool debug) {
  return bh_core_init(mode, debug);
}
```



## bh_core_init



- linkerinit
- manager init
  - task manager
  - hook manager
  - elf manager
- trampo init 
- signal init(SIGSEGV/SIGBUS)



```C
int bh_core_init(int mode, bool debug) {
  // Do not repeat the initialization.
  // 防止重复init
  if (BYTEHOOK_STATUS_CODE_UNINIT != bh_core.init_status) {
    BH_LOG_SHOW("bytehook already inited, return: %d", bh_core.init_status);
    return bh_core.init_status;
  }

  static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  // lock 加锁
  pthread_mutex_lock(&lock);
  // 预测为true
  if (__predict_true(BYTEHOOK_STATUS_CODE_UNINIT == bh_core.init_status)) {
    int status;
	
    bh_log_set_debug(debug);
    // check mode设置
    if (BYTEHOOK_MODE_AUTOMATIC != mode && BYTEHOOK_MODE_MANUAL != mode) {
      status = BYTEHOOK_STATUS_CODE_INITERR_INVALID_ARG;
      goto end;
    }
    bh_core.mode = mode;
    // init linker
    if (0 != bh_linker_init()) {
      status = BYTEHOOK_STATUS_CODE_INITERR_SYM;
      goto end;
    }
    // 创建3和task节点
    if (NULL == (bh_core.task_mgr = bh_task_manager_create())) {
      status = BYTEHOOK_STATUS_CODE_INITERR_TASK;
      goto end;
    }
    if (NULL == (bh_core.hook_mgr = bh_hook_manager_create())) {
      status = BYTEHOOK_STATUS_CODE_INITERR_HOOK;
      goto end;
    }
    if (NULL == (bh_core.elf_mgr = bh_elf_manager_create())) {
      status = BYTEHOOK_STATUS_CODE_INITERR_ELF;
      goto end;
    }
    // automic模式init trampo
    if (BYTEHOOK_MODE_AUTOMATIC == mode && 0 != bh_trampo_init()) {
      status = BYTEHOOK_STATUS_CODE_INITERR_TRAMPO;
      goto end;
    }
    // 信号量初始化
    if (0 != bytesig_init(SIGSEGV) || 0 != bytesig_init(SIGBUS)) {
      status = BYTEHOOK_STATUS_CODE_INITERR_SIG;
      goto end;
    }
    if (0 != bh_cfi_disable_slowpath()) {
      status = BYTEHOOK_STATUS_CODE_INITERR_CFI;
      goto end;
    }
    status = BYTEHOOK_STATUS_CODE_OK;  // everything OK

  end:
    __atomic_store_n(&bh_core.init_status, status, __ATOMIC_SEQ_CST);
  }
    
  // 解锁
  pthread_mutex_unlock(&lock);
  // loge
  BH_LOG_SHOW("%s: bytehook init(mode: %s, debug: %s), return: %d", bytehook_get_version(),
              BYTEHOOK_MODE_AUTOMATIC == mode ? "AUTOMATIC" : "MANUAL", debug ? "true" : "false",
              bh_core.init_status);
  // 返回状态码
  return bh_core.init_status;
}
```



### bh_linker_init



> 读取锁变量的值
>
> 读取一些函数、全局变量地址，方便后续做兼容性适配
>
> 初始化如下变量
>
>  bh_linker_do_dlopen = NULL;
>  bh_linker_dlopen_ext = NULL;
>  bh_linker_g_dl_mutex = NULL;
>  bh_linker_get_error_buffer = NULL;
>  bh_linker_bionic_format_dlerror = NULL;

```c
int bh_linker_init(void) {
  bh_linker_g_dl_mutex_compatible = bh_linker_check_lock_compatible();
  int api_level = bh_util_get_api_level();

  // for Android 4.x
  // ......

  // 创建锁变量
  if (!bh_linker_g_dl_mutex_compatible) {
    // If the mutex ABI is not compatible, then we need to use an alternative.
    if (0 != pthread_key_create(&bh_linker_g_dl_mutex_key, NULL)) return -1;
  }

  // 读取linker base地址，方便后续解析函数地址
  void *linker = bh_dl_open_linker();
  if (NULL == linker) goto err;

  // for Android 5.0, 5.1, 7.0, 7.1 and all mutex ABI compatible cases
  // 解析dl mutex全局变量位置
  // __dl__ZL10g_dl_mutex 	__dl_g_dl_mutex
  if (__ANDROID_API_L__ == api_level || __ANDROID_API_L_MR1__ == api_level ||
      __ANDROID_API_N__ == api_level || __ANDROID_API_N_MR1__ == api_level ||
      bh_linker_g_dl_mutex_compatible) {
    bh_linker_g_dl_mutex = (pthread_mutex_t *)(bh_dl_dsym(linker, BH_CONST_SYM_G_DL_MUTEX));
    if (NULL == bh_linker_g_dl_mutex && api_level >= __ANDROID_API_U__)
      bh_linker_g_dl_mutex = (pthread_mutex_t *)(bh_dl_dsym(linker, BH_CONST_SYM_G_DL_MUTEX_U_QPR2));
    if (NULL == bh_linker_g_dl_mutex) goto err;
  }

  // for Android 7.0, 7.1
  // 读取如下函数地址 
  // __dl__ZL10dlopen_extPKciPK17android_dlextinfoPv
  // __dl__Z9do_dlopenPKciPK17android_dlextinfoPv
  // __dl__Z23linker_get_error_bufferv
  // __dl__ZL23__bionic_format_dlerrorPKcS0_
  if (__ANDROID_API_N__ == api_level || __ANDROID_API_N_MR1__ == api_level) {
    bh_linker_dlopen_ext = (bh_linker_dlopen_ext_t)(bh_dl_dsym(linker, BH_CONST_SYM_DLOPEN_EXT));
    if (NULL == bh_linker_dlopen_ext) {
      if (NULL == (bh_linker_do_dlopen = (bh_linker_do_dlopen_t)(bh_dl_dsym(linker, BH_CONST_SYM_DO_DLOPEN))))
        goto err;
      bh_linker_get_error_buffer =
          (bh_linker_get_error_buffer_t)(bh_dl_dsym(linker, BH_CONST_SYM_LINKER_GET_ERROR_BUFFER));
      bh_linker_bionic_format_dlerror =
          (bh_linker_bionic_format_dlerror_t)(bh_dl_dsym(linker, BH_CONST_SYM_BIONIC_FORMAT_DLERROR));
    }
  }

  bh_dl_close(linker);
  return 0;

err:
  // 滞空所以相关的变量......
  return -1;
}
```



### bh_task_manager_create

> 用于初始化task_manager结构体。
>
> `bh_task_manager_t`主要用于存储`bh_task_t`
>
> 即用于存储hook single、hook partial、hook all的函数参数。
>
> 双向链表结构



> 单箭头不意味着，是单链表。偷懒没画双向剪头。😄

![image-20240217122355793](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240217122355793.png)

> 初始化数据结构

```c
bh_task_manager_t *bh_task_manager_create(void) {
  // 分配内存空间
  bh_task_manager_t *self = malloc(sizeof(bh_task_manager_t));
  if (NULL == self) return NULL;
  // 初始化tasks
  TAILQ_INIT(&self->tasks);
  // 初始化读写锁
  pthread_rwlock_init(&self->lock, NULL);
  return self;
}
```



> manager 结构体

```c
typedef struct bh_task_manager bh_task_manager_t;

struct bh_task_manager {
  // 双向链表 element为 bh_task
  bh_task_queue_t tasks;
  // 读写锁
  pthread_rwlock_t lock;
};

// 其实就是个单向链表
typedef TAILQ_HEAD(bh_task_queue, bh_task, ) bh_task_queue_t;

// 头节点
#define TAILQ_HEAD(name, type, qual)                                    \
    struct name {                                                       \
        struct type *qual tqh_first; /* first element */                \
        struct type *qual *tqh_last; /* addr of last next element */    \
}

// task
typedef struct bh_task {
  uint32_t id;  // unique id
  bh_task_type_t type;
  bh_task_status_t status;

  // caller
  char *caller_path_name;                              // for single
  bytehook_caller_allow_filter_t caller_allow_filter;  // for partial
  void *caller_allow_filter_arg;                       // for partial

  // callee
  char *callee_path_name;
  void *callee_addr;

  // symbol
  char *sym_name;

  // new function address
  void *new_func;

  // callback
  bytehook_hooked_t hooked;
  void *hooked_arg;

  int hook_status_code;  // for single type

  void *manual_orig_func;  // for manual mode

  TAILQ_ENTRY(bh_task, ) link;
} bh_task_t;

// 链接之前和之后的结构体。
#define TAILQ_ENTRY(type, qual)                                         \
    struct {                                                            \
        struct type *qual tqe_next;  /* next element */                 \
        struct type *qual *tqe_prev; /* address of previous next element */ \
}

```







### bh_hook_manager_create



> `bh_hook_manager_t`结构体是用于做***automic模式***下的hook管理。
>
> 即对trampo hook链进行控制。
>
> 记录同一个函数下的所有hook。
>
> 数据结构是红黑树 + 链表，红黑树的每个元素就是一个链表。



> 初始化`bh_hook_manager_t`数据结构

```c
bh_hook_manager_t *bh_hook_manager_create(void) {
  bh_hook_manager_t *self;
  if (NULL == (self = malloc(sizeof(bh_hook_manager_t)))) return NULL;
  // root节点制空
  RB_INIT(&self->hooks);
  // abandoned节点制空
  RB_INIT(&self->abandoned_hooks);
  // 初始化mutex
  pthread_mutex_init(&self->hooks_lock, NULL);
  return self;
}
```



> hook manager结构体

```c
typedef struct bh_hook_manager bh_hook_manager_t;

struct bh_hook_manager {
  // 红黑树 Node结构体为bh_hook
  bh_hook_tree_t hooks;
  bh_hook_tree_t abandoned_hooks;
  pthread_mutex_t hooks_lock;
};

typedef RB_HEAD(bh_hook_tree, bh_hook) bh_hook_tree_t;

// 头节点
#define RB_HEAD(name, type)                                             \
struct name {                                                           \
        struct type *rbh_root; /* root of the tree */                   \
}

typedef struct bh_hook {
  void *got_addr;
  void *orig_func;
  bh_hook_call_list_t running_list;
  pthread_mutex_t running_list_lock;
  RB_ENTRY(bh_hook) link;
} bh_hook_t;

#define RB_INIT(root) do {                                              \
        (root)->rbh_root = NULL;                                        \
} while (/*CONSTCOND*/ 0)
```





### bh_elf_manager_create



> 用于记录open的elf文件。每open一个so文件，就会触发刷新`bh_elf_manager_t`内的数据。
>
> `bh_elf_manager_t`是一个红黑树的数据结构，每一个element都是一个复合的结构体`bh_elf`（存储elf文件数据）



> 初始化`bh_elf_manager_t`数据结构

```c
bh_elf_manager_t *bh_elf_manager_create(void) {
  bh_elf_manager_t *self;
  if (NULL == (self = malloc(sizeof(bh_elf_manager_t)))) return NULL;
  // 初始化manager内的所有成员
  self->contain_pathname = false;
  self->contain_basename = false;
  RB_INIT(&self->elfs);
  self->elfs_cnt = 0;
  TAILQ_INIT(&self->abandoned_elfs);
  pthread_rwlock_init(&self->elfs_lock, NULL);
  TAILQ_INIT(&self->blocklist);
  pthread_mutex_init(&self->blocklist_lock, NULL);

  return self;
}
```



> elf manager数据结构

```c
typedef struct bh_elf_manager bh_elf_manager_t;

typedef RB_HEAD(bh_elf_tree, bh_elf) bh_elf_tree_t;

typedef TAILQ_HEAD(bh_elf_list, bh_elf, ) bh_elf_list_t;

typedef TAILQ_HEAD(bh_elf_manager_block_list, bh_elf_manager_block, ) bh_elf_manager_block_list_t;

struct bh_elf_manager {
  bool contain_pathname;
  bool contain_basename;
  // 以bh_elf为元素的红黑树
  bh_elf_tree_t elfs;
  size_t elfs_cnt;
  // 以bh_elf为元素的链表
  bh_elf_list_t abandoned_elfs;
  pthread_rwlock_t elfs_lock;
  // 以bh_elf_manager_block为元素的链表
  bh_elf_manager_block_list_t blocklist;
  pthread_mutex_t blocklist_lock;
};
```







### bh_trampo_init



> Node: 只有mode为automic的时候才会调用init方法

```c
static pthread_key_t bh_trampo_tls_key;
static bh_trampo_stack_t bh_hub_stack_cache[BH_TRAMPO_THREAD_MAX];
static uint8_t bh_hub_stack_cache_used[BH_TRAMPO_THREAD_MAX];

int bh_trampo_init(void) {
  // 初始化thread_key
  if (0 != pthread_key_create(&bh_trampo_tls_key, bh_trampo_stack_destroy)) return -1;
  // 清0
  memset(&bh_hub_stack_cache, 0, sizeof(bh_hub_stack_cache));
  memset(&bh_hub_stack_cache_used, 0, sizeof(bh_hub_stack_cache_used));
  return 0;
}
```



### bytesig_init



> 在调用bytesig_init之前，进行了准备工作

> `__attribute__((constructor))`会在`main`函数调用以前调用
>
> 用 `__attribute__((constructor))` 定义单独的 init 函数。

> 通过dlopen 寻找 sigaction64、sigprocmask64函数

```c
__attribute__((constructor)) static void bytesig_ctor(void) {
  void *libc = dlopen("libc.so", RTLD_LOCAL);
  if (__predict_false(NULL == libc)) return;

  if (__predict_true(NULL != sigfillset64 && NULL != sigemptyset64 && NULL != sigaddset64 &&
                     NULL != sigismember64)) {
    if (__predict_true(NULL != (bytesig_sigaction = dlsym(libc, "sigaction64")) &&
                       NULL != (bytesig_sigprocmask = dlsym(libc, "sigprocmask64")))) {
      bytesig_status = BYTESIG_STATUS_SIG64;
      goto end;
    }
  }

  if (__predict_true(NULL != (bytesig_sigaction = dlsym(libc, "sigaction")) &&
                     NULL != (bytesig_sigprocmask = dlsym(libc, "sigprocmask")))) {
    bytesig_status = BYTESIG_STATUS_SIG32;
  }

end:
  dlclose(libc);
}
```



> 注册信号量（SIGSEGV、SIGBUS）
>
> 通过bytesig_ctor获取的sigaction64函数指针，调用进行型号量的注册
>
> SIGSEGV
>
> 表示段错误（Segmentation Fault）。当一个进程试图访问一个未分配给它的内存区域，或者试图在只读的内存区域上执行写操作时，就会触发段错误信号。
>
> SIGBUS
>
> 表示总线错误（Bus Error）。这个信号表示发生了一些硬件相关的错误，比如访问未对齐的内存地址，或者试图在只读的内存区域上执行写操作。

```c
int bytesig_init(int signum) {
    
  // 确认信号量的合法性（不处理SIGKILL & SIGSTOP）
  if (__predict_false(signum <= 0 || signum >= __SIGRTMIN || signum == SIGKILL || signum == SIGSTOP))
    return -1;
  // bytesig_ctor准备过程是否异常。
  if (__predict_false(BYTESIG_STATUS_UNAVAILABLE == bytesig_status)) return -1;
  // 如果已经注册则不进行后续处理
  if (__predict_false(NULL != bytesig_signal_array[signum])) return -1;

  // 初始化互斥锁
  static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  // 加锁
  pthread_mutex_lock(&lock);
  int ret = -1;
  // 再次确认没有重复注册
  if (__predict_false(NULL != bytesig_signal_array[signum])) goto end;
  // 分配对象
  bytesig_signal_t *sig = calloc(1, sizeof(bytesig_signal_t));
  if (__predict_false(NULL == sig)) goto end;

#define SA_EXPOSE_TAGBITS 0x00000800

// 注册signal handler
#define REGISTER_SIGNAL_HANDLER(suffix)                                                                     \
  do {                                                                                                      \
    struct sigaction##suffix act;                                                                           \
    memset(&act, 0, sizeof(struct sigaction##suffix));                                                      \
    sigfillset##suffix(&act.sa_mask);                                                                       \
    act.sa_sigaction = bytesig_handler;                                                                     \
    act.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESTART | SA_EXPOSE_TAGBITS;                                \
    if (__predict_false(                                                                                    \
            0 !=                                                                                            \
            ((bytesig_sigaction##suffix##_t)bytesig_sigaction)(signum, &act, &sig->prev_action##suffix))) { \
      free(sig);                                                                                            \
      goto end;                                                                                             \
    }                                                                                                       \
  } while (0)

  // register the signal handler, we start off with all signals blocked
  // 为32位 & 64位架构单独注册
  if (BYTESIG_STATUS_SIG64 == bytesig_status)
    REGISTER_SIGNAL_HANDLER(64);
  else
    REGISTER_SIGNAL_HANDLER();
  // 写入注册表中
  bytesig_signal_array[signum] = sig;
  ret = 0;  // OK

end:
  // 解锁 & 返回
  pthread_mutex_unlock(&lock);
  return ret;
}
```



### bh_cfi_disable_slowpath



> 用于禁用cfi检查。
>
> [CFI官网介绍](https://source.android.com/docs/security/test/cfi?hl=zh-cn)



> 实现就我来看，**好像**是通过修改`__cfi_slowpath`函数的指令实现的。
>
> 可见BH_CFI_ARM64_RET_INST（svc #0）

```c
int bh_cfi_disable_slowpath(void) {
  if (bh_util_get_api_level() < __ANDROID_API_O__) return 0;

  if (NULL == bh_cfi_slowpath || NULL == bh_cfi_slowpath_diag) return -1;

  void *start = bh_cfi_slowpath <= bh_cfi_slowpath_diag ? bh_cfi_slowpath : bh_cfi_slowpath_diag;
  void *end = bh_cfi_slowpath <= bh_cfi_slowpath_diag ? bh_cfi_slowpath_diag : bh_cfi_slowpath;
  if (0 != bh_util_set_protect(start, (void *)((uintptr_t)end + sizeof(uint32_t)),
                               PROT_READ | PROT_WRITE | PROT_EXEC))
    return -1;

  BYTESIG_TRY(SIGSEGV, SIGBUS) {
    *((uint32_t *)bh_cfi_slowpath) = BH_CFI_ARM64_RET_INST;
    *((uint32_t *)bh_cfi_slowpath_diag) = BH_CFI_ARM64_RET_INST;
  }
  BYTESIG_CATCH() {
    return -1;
  }
  BYTESIG_EXIT

  __builtin___clear_cache(start, (void *)((size_t)end + sizeof(uint32_t)));

  return 0;
}
```



# hook



bhook 的hook类型分为3种

> Note：
>
> 下图中
>
> **虚线箭头**表示hook前的got表指向。
>
> **实线箭头**表示hook后或实际的got表指向。

- hook single

  > 只hook 指定的模块调用。假设有两个so，a.so，b.so分别定义了aPrint，bPrint函数，调用glibc的printf。
  >
  > 通过hook single hook b.so的printf调用。
  >
  > ![image-20240217171106126](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240217171106126.png)

- hook all

  > 还是上面的示例，则会hook 所有so对于printf符号表的引用
  >
  > ![image-20240217171350135](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240217171350135.png)

- hook partial

  > 类似于hook all只是加了一个过滤器。不是对所有的调用都进行hook。只有满足hook规则的才会hook。



小小总结一下。

1.hook single只会对指定caller的got表进行修改

2.hook all 不管三七二一，对所有caller的got表进行修改。

3.hook partial 在hook all的基础上，只有对caller满足指定filter函数的要求才会修改got表。

4.hook的本质起始就是对caller的got表的修改。算法的关键在于，怎么找到got表。





## bytehook_hook_single



我们可以把single hook（起始不只是single hook，partial，all起始过程基本上是一样的）

过程分为4个阶段。

- hook cfi

  > 这一步主要是绕过android的cfi安全检查。
  >
  > 安全机制的存在导致不能直接修改got表。
  >
  > 这里只是贴一下，保证流程完整，不会细致分析。

- init dl monitor

  > 这个流程主要是hook dl，用于兼容对dlopen加载的动态库的hook。
  >
  > 如果不监控dl的链接，hook all，hook partial可能无法覆盖全
  >
  > （如果我们hook的函数在dlopen加载之后）

- search got

  > GOT/PLT hook的核心是修改got表。
  >
  > 在修改之前，需要把GOT表给找到才行。

- replace

  > 最后一步，修改got表。

![single-hook-overview.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/single-hook-overview.drawio.png)



```c
bytehook_stub_t bytehook_hook_single(const char *caller_path_name, const char *callee_path_name,
                                     const char *sym_name, void *new_func, bytehook_hooked_t hooked,
                                     void *hooked_arg) {
  // 获取上个函数调用的return addr，即bytehook_hook_single返回后的跳转地址
  // （参数0表示上个函数，1则表示上上个函数，以此类推）
  const void *caller_addr = __builtin_return_address(0);
  // 传入所有函数参数 + caller_addr
  return bh_core_hook_single(caller_path_name, callee_path_name, sym_name, new_func, hooked, hooked_arg,
                             (uintptr_t)caller_addr);
}
```



```c
bytehook_stub_t bh_core_hook_single(const char *caller_path_name, const char *callee_path_name,
                                    const char *sym_name, void *new_func, bytehook_hooked_t hooked,
                                    void *hooked_arg, uintptr_t caller_addr) {
  // 判空
  if (NULL == caller_path_name || NULL == sym_name || NULL == new_func) return NULL;
  // 判断是否init完成
  if (BYTEHOOK_STATUS_CODE_OK != bh_core.init_status) return NULL;
  // 创建task
  bh_task_t *task =
      bh_task_create_single(caller_path_name, callee_path_name, sym_name, new_func, hooked, hooked_arg);
  if (NULL != task) { // hook
    bh_task_manager_add(bh_core.task_mgr, task);
    bh_task_manager_hook(bh_core.task_mgr, task);
    bh_recorder_add_hook(task->hook_status_code, caller_path_name, sym_name, (uintptr_t)new_func,
                         (uintptr_t)task, caller_addr);
  }
  return (bytehook_stub_t)task;
}
```



### bh_task_manager_add



> 单纯地添加元素

```c
void bh_task_manager_add(bh_task_manager_t *self, bh_task_t *task) {
  // 加锁
  pthread_rwlock_wrlock(&self->lock);
  // tail尾部插入task
  TAILQ_INSERT_TAIL(&self->tasks, task, link);
  // 解锁
  pthread_rwlock_unlock(&self->lock);
}
```



### bh_task_manager_hook



> 这部分主要是进行
>
> - dl monitor的初始化（hook dlopen & dlclose方法）
> - hook
>   - got地址获取
>   - got表改写

```c
void bh_task_manager_hook(bh_task_manager_t *self, bh_task_t *task) {
  if (bh_dl_monitor_is_initing()) { // dl monitor已经初始化
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static bool oneshot_refreshed = false;
    if (!oneshot_refreshed) {
      bool hooked = false;
      pthread_mutex_lock(&lock);
      if (!oneshot_refreshed) {
        bh_dl_monitor_dlclose_rdlock();
        bh_elf_manager_refresh(bh_core_global()->elf_mgr, false, NULL, NULL);
        bh_task_hook(task);
        bh_dl_monitor_dlclose_unlock();
        oneshot_refreshed = true;
        hooked = true;
      }
      pthread_mutex_unlock(&lock);
      if (hooked) return;
    }
  } else { // 1. dl monitor初始化
    // start & check dl-monitor
    if (0 != bh_task_manager_init_dl_monitor(self)) {
      // For internal tasks in the DL monitor, this is not an error.
      // But these internal tasks do not set callbacks, so there will be no side effects.
      bh_task_hooked(task, BYTEHOOK_STATUS_CODE_INITERR_DLMTR, NULL, NULL);
      return;
    }
  }

  bh_dl_monitor_dlclose_rdlock();
  // 2.hook 
  bh_task_hook(task);
  bh_dl_monitor_dlclose_unlock();
}
```





#### init monitor



> 只有当monitor没初始化的时候才需要init

```c
static int bh_task_manager_init_dl_monitor(bh_task_manager_t *self) {
  static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  static bool inited = false;
  static bool inited_ok = false;
  // 防止重复init
  if (inited) return inited_ok ? 0 : -1;  // Do not repeat the initialization.

  int r;
  // 加锁
  pthread_mutex_lock(&lock);
  if (!inited) { // double check是否init
    // 设置dlopen & dlclose函数
    bh_dl_monitor_set_post_dlopen(bh_task_manager_post_dlopen, self);
    bh_dl_monitor_set_post_dlclose(bh_task_manager_post_dlclose, NULL);
    if (0 == (r = bh_dl_monitor_init())) inited_ok = true;
    inited = true;
  } else { // 
    r = inited_ok ? 0 : -1;
  }
  // 解锁
  pthread_mutex_unlock(&lock);
  return r;
}
```



> monitor初始化过程中核心是hook dl。

```c
int bh_dl_monitor_init(void) {
  // mutex初始化
  // ......
  int r;
  // lock
  pthread_mutex_lock(&lock);
  bh_dl_monitor_initing = true;
  if (!inited) {
    __atomic_store_n(&inited, true, __ATOMIC_SEQ_CST);
    BH_LOG_INFO("DL monitor: pre init");
      // 核心！！
    if (0 == (r = bh_dl_monitor_hook())) { // 初始化成功
      __atomic_store_n(&inited_ok, true, __ATOMIC_SEQ_CST);
      BH_LOG_INFO("DL monitor: post init, OK");
    } else {
      BH_LOG_ERROR("DL monitor: post init, FAILED");
    }
  } else {
    r = inited_ok ? 0 : -1;
  }
  bh_dl_monitor_initing = false;
  // unlock
  pthread_mutex_unlock(&lock);
  return r;
}
```



> 所谓的init monitor主要就是hook
>
> ld的dlopen以及dlclose（兼容不同版本的差异）
>
> - dlopen
>
> - android_dlopen_ext
>
> - __loader_dlopen
>
> - __loader_android_dlopen_ext
>
> - dlclose



> Note：
>
> hook调用了bh_core_hook_single/bh_core_hook_all去实现。

```c
static int bh_dl_monitor_hook(void) {
  int api_level = bh_util_get_api_level();

    // 兼容24 && 25 sdkversion
	// ......

    
    // Hook dlopen
    // sdk 16 ~ 25 
    // hook 	dl open
    // ......

    // 21 ~ 24 sdkversion 
    // hook 	android_dlopen_ext函数
	// ......
    
    // sdkversion >= 26
  if (api_level >= __ANDROID_API_O__) {
      // libdl.so __loader_dlopen
    if (NULL ==
        (bh_dl_monitor_stub_loader_dlopen = bh_core_hook_single(
             BH_CONST_BASENAME_DL, NULL,
             BH_CONST_SYM_LOADER_DLOPEN,  // STT_FUNC or STT_NOTYPE
             (void *)bh_dl_monitor_proxy_loader_dlopen,
             (BYTEHOOK_MODE_MANUAL == bh_core_get_mode()) ? bh_dl_monitor_proxy_loader_dlopen_hooked : NULL,
             NULL, (uintptr_t)(__builtin_return_address(0)))))
      goto err;

      // libdl.so __loader_android_dlopen_ext
    if (NULL == (bh_dl_monitor_stub_loader_android_dlopen_ext =
                     bh_core_hook_single(BH_CONST_BASENAME_DL, NULL,
                                         BH_CONST_SYM_LOADER_ANDROID_DLOPEN_EXT,  // STT_FUNC or STT_NOTYPE
                                         (void *)bh_dl_monitor_proxy_loader_android_dlopen_ext,
                                         (BYTEHOOK_MODE_MANUAL == bh_core_get_mode())
                                             ? bh_dl_monitor_proxy_loader_android_dlopen_ext_hooked
                                             : NULL,
                                         NULL, (uintptr_t)(__builtin_return_address(0)))))
      goto err;
  }

    // hook dlclose
  if (api_level < __ANDROID_API_O__) {
      // dlclose
    if (NULL == (bh_dl_monitor_stub_dlclose = bh_core_hook_all(
                     NULL, BH_CONST_SYM_DLCLOSE, (void *)bh_dl_monitor_proxy_dlclose,
                     (BYTEHOOK_MODE_MANUAL == bh_core_get_mode()) ? bh_dl_monitor_proxy_dlclose_hooked : NULL,
                     NULL, (uintptr_t)(__builtin_return_address(0)))))
      goto err;
  } else {
      // libdl.so __loader_dlclose
    if (NULL ==
        (bh_dl_monitor_stub_loader_dlclose = bh_core_hook_single(
             BH_CONST_BASENAME_DL, NULL,
             BH_CONST_SYM_LOADER_DLCLOSE,  // STT_FUNC or STT_NOTYPE
             (void *)bh_dl_monitor_proxy_loader_dlclose,
             (BYTEHOOK_MODE_MANUAL == bh_core_get_mode()) ? bh_dl_monitor_proxy_loader_dlclose_hooked : NULL,
             NULL, (uintptr_t)(__builtin_return_address(0)))))
      goto err;
  }

  return 0;

err:
  bh_dl_monitor_uninit();
  return -1;
}
```



#### hook cfi



```c
void bh_hook_manager_hook(bh_hook_manager_t *self, bh_task_t *task, bh_elf_t *caller_elf) {
  // check ELF
  if (bh_elf_get_error(caller_elf)) {
    if (BH_TASK_TYPE_SINGLE == task->type)
      bh_task_hooked(task, BYTEHOOK_STATUS_CODE_READ_ELF, caller_elf->pathname, NULL);
    return;
  }

    // 定义lp64 && api >= 26
#ifdef __LP64__
  if (bh_util_get_api_level() >= __ANDROID_API_O__) {
    // hook __cfi_slowpath and __cfi_slowpath_diag (only once)
    if (!caller_elf->cfi_hooked) {
      bh_elf_cfi_hook_lock(caller_elf);
      if (!caller_elf->cfi_hooked) {
        caller_elf->cfi_hooked_ok = bh_hook_manager_hook_cfi(self, caller_elf);
        caller_elf->cfi_hooked = true;
      }
      bh_elf_cfi_hook_unlock(caller_elf);
    }

    // check CIF hook
    if (!caller_elf->cfi_hooked_ok) {
      if (BH_TASK_TYPE_SINGLE == task->type)
        bh_task_hooked(task, BYTEHOOK_STATUS_CODE_CFI_HOOK_FAILED, caller_elf->pathname, NULL);
      return;
    }
  }
#endif

  bh_hook_manager_hook_impl(self, task, caller_elf);
}
```



#### search got

> 寻找got表写入addr_array中

```c
static size_t bh_hook_manager_find_all_got(bh_elf_t *caller_elf, bh_task_t *task, void **addr_array,
                                           size_t addr_array_cap) {
  if (NULL == task->callee_addr) {
    // by import symbol name
    return bh_elf_find_import_func_addr_by_symbol_name(caller_elf, task->sym_name, addr_array,
                                                       addr_array_cap);
  } else {
    // by callee address
    return bh_elf_find_import_func_addr_by_callee_addr(caller_elf, task->callee_addr, addr_array,
                                                       addr_array_cap);
  }
}
```



##### search by symbol name

> search by symbol name

```c
static size_t bh_elf_find_import_func_addr_by_symbol_name_unsafe(bh_elf_t *self, const char *sym_name,
                                                                 void **addr_array, size_t addr_array_cap) {
  size_t addr_array_sz = 0;

    // 通过symbol name寻找symbol
  ElfW(Sym) *sym = bh_elf_find_import_func_symbol_by_symbol_name(self, sym_name);
  if (NULL == sym) return 0;
	// 遍历rel plt
  for (size_t i = 0; i < self->rel_plt_cnt; i++) {
    const Elf_Reloc *rel = &(self->rel_plt[i]);
    if (&(self->dynsym[BH_ELF_R_SYM(rel->r_info)]) != sym) continue;
    if (BH_ELF_R_JUMP_SLOT != BH_ELF_R_TYPE(rel->r_info)) continue;

    addr_array[addr_array_sz++] = (void *)(self->load_bias + rel->r_offset);
    if (addr_array_sz >= addr_array_cap) return addr_array_sz;
  }
	// 遍历rel dyn
  for (size_t i = 0; i < self->rel_dyn_cnt; i++) {
    const Elf_Reloc *rel = &(self->rel_dyn[i]);
    if (&(self->dynsym[BH_ELF_R_SYM(rel->r_info)]) != sym) continue;
    if (BH_ELF_R_GLOB_DAT != BH_ELF_R_TYPE(rel->r_info) && BH_ELF_R_ABS != BH_ELF_R_TYPE(rel->r_info))
      continue;

    addr_array[addr_array_sz++] = (void *)(self->load_bias + rel->r_offset);
    if (addr_array_sz >= addr_array_cap) return addr_array_sz;
  }
	// 遍历rel dyn aps2格式
  if (NULL != self->rel_dyn_aps2) {
    bh_sleb128_decoder_t decoder;
    bh_sleb128_decoder_init(&decoder, self->rel_dyn_aps2, self->rel_dyn_aps2_sz);
    void *pkg[5] = {self, sym, (void *)addr_array, (void *)addr_array_cap, &addr_array_sz};
    bh_elf_iterate_aps2(&decoder, bh_elf_find_import_func_addr_by_symbol_name_unsafe_aps2_cb, pkg);
  }

  return addr_array_sz;
}
```



##### search by callee addr

> 遍历rel.plt 、rel.dyn、rel.dyn aps2 所有的item。
>
> 通过：
>
> type == JUMP_SLOT && 
>
> *got == addr
>
> 寻找满足条件的got表。

```c
static size_t bh_elf_find_import_func_addr_by_callee_addr_unsafe(bh_elf_t *self, void *target_addr,
                                                                 void **addr_array, size_t addr_array_cap) {
  size_t addr_array_sz = 0;
     // 遍历rel.plt
  for (size_t i = 0; i < self->rel_plt_cnt; i++) {
    const Elf_Reloc *rel = &(self->rel_plt[i]);
    if (BH_ELF_R_JUMP_SLOT != BH_ELF_R_TYPE(rel->r_info)) continue;
    if (*((void **)(self->load_bias + rel->r_offset)) != target_addr) continue;

    addr_array[addr_array_sz++] = (void *)(self->load_bias + rel->r_offset);
    if (addr_array_sz >= addr_array_cap) return addr_array_sz;
  }
	// 遍历rel.dyn
  for (size_t i = 0; i < self->rel_dyn_cnt; i++) {
    const Elf_Reloc *rel = &(self->rel_dyn[i]);
    if (BH_ELF_R_GLOB_DAT != BH_ELF_R_TYPE(rel->r_info) && BH_ELF_R_ABS != BH_ELF_R_TYPE(rel->r_info))
      continue;
    if (*((void **)(self->load_bias + rel->r_offset)) != target_addr) continue;

    addr_array[addr_array_sz++] = (void *)(self->load_bias + rel->r_offset);
    if (addr_array_sz >= addr_array_cap) return addr_array_sz;
  }
	// 遍历rel.dyn aps2格式
  if (NULL != self->rel_dyn_aps2) {
    bh_sleb128_decoder_t decoder;
    bh_sleb128_decoder_init(&decoder, self->rel_dyn_aps2, self->rel_dyn_aps2_sz);
    void *pkg[5] = {self, target_addr, (void *)addr_array, (void *)addr_array_cap, &addr_array_sz};
    bh_elf_iterate_aps2(&decoder, bh_elf_find_import_func_addr_by_callee_addr_unsafe_aps2_cb, pkg);
  }

  return addr_array_sz;
}
```



#### replace

> 下方代码片段中可以发现有两个分支。

分别为bhook两种mode进行了处理

- manual mode
- automic mode

```c
static int bh_hook_manager_hook_single_got(bh_hook_manager_t *self, bh_elf_t *caller_elf, bh_task_t *task,
                                           void *got_addr, void **orig_func_ret) {
  // 手动模式
  if (BYTEHOOK_MODE_MANUAL == bh_core_get_mode()) {
    // manual mode:

    // 1. always patch with the externally specified address
    r = bh_hook_manager_replace_got_value(caller_elf, task, got_addr, orig_func, task->new_func);

    // 2. save the original address in task object for unhook
    if (0 == r) {
      bh_task_set_manual_orig_func(task, orig_func);
      BH_LOG_INFO("hook chain: manual REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
                  (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)task->new_func, task->sym_name,
                  caller_elf->pathname);
    }

    // 3. return the original address
    if (0 == r) *orig_func_ret = orig_func;
  } else {
    // automatic mode:

    // 1. add new-func to the hook chain
    void *trampo = NULL;
    void *orig_func_real = NULL;
    r = bh_hook_manager_add_func(self, caller_elf, got_addr, orig_func, task, &trampo, &orig_func_real);

    // 2. replace with the trampoline address if we haven't done it yet
    if (0 == r && NULL != trampo) {
      r = bh_hook_manager_replace_got_value(caller_elf, task, got_addr, orig_func, trampo);
      if (0 == r) {
        BH_LOG_INFO("hook chain: auto REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
                    (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)trampo, task->sym_name,
                    caller_elf->pathname);
      } else {
        bh_hook_manager_del_func(self, got_addr, task, NULL);
      }
    }

    // 3. return the original address
    if (0 == r) *orig_func_ret = orig_func_real;
  }

  // ......
}
```







##### manual mode

> 即手动模式

```c
// manual mode:

// 1. always patch with the externally specified address
// 设置got表
r = bh_hook_manager_replace_got_value(caller_elf, task, got_addr, orig_func, task->new_func);

// 2. save the original address in task object for unhook
// 保存原始address到task结构体内
if (0 == r) {
  bh_task_set_manual_orig_func(task, orig_func);
  BH_LOG_INFO("hook chain: manual REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
              (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)task->new_func, task->sym_name,
              caller_elf->pathname);
}

// 3. return the original address
// 设置origin指针
if (0 == r) *orig_func_ret = orig_func;
```



1.replace got value

​	1）确保got表和symbol是匹配的

​	2）获取got表segment的权限（如果got表没有写权限，通过mprotect写入写权限）

​	3）通过atomic内置函数设置got表内容为new_func指针。

```c
static int bh_hook_manager_replace_got_value(bh_elf_t *caller_elf, bh_task_t *task, void *got_addr,
                                             void *orig_func, void *new_func) {
  // verify the GOT value
  // 确保got表和symbol是匹配的
  if (BH_TASK_STATUS_UNHOOKING != task->status) {
    if (0 != bh_hook_manager_verify_got_value(caller_elf, task, got_addr)) {
      bh_task_hooked(task, BYTEHOOK_STATUS_CODE_GOT_VERIFY, caller_elf->pathname, orig_func);
      return BYTEHOOK_STATUS_CODE_GOT_VERIFY;
    }
  }

  // get permission by address
  // 通过program header的flag获取section的权限
  int prot = bh_elf_get_protect_by_addr(caller_elf, got_addr);
  if (0 == prot) {
    bh_task_hooked(task, BYTEHOOK_STATUS_CODE_GET_PROT, caller_elf->pathname, orig_func);
    return BYTEHOOK_STATUS_CODE_GET_PROT;
  }

  // add write permission
  // 如果got表对应的segment没有写权限，强行通过mprotect设置写入权限
  if (0 == (prot & PROT_WRITE)) {
    if (0 != bh_util_set_addr_protect(got_addr, prot | PROT_WRITE)) {
      bh_task_hooked(task, BYTEHOOK_STATUS_CODE_SET_PROT, caller_elf->pathname, orig_func);
      return BYTEHOOK_STATUS_CODE_SET_PROT;
    }
  }

  // replace the target function address by "new_func"
  int r;
  BYTESIG_TRY(SIGSEGV, SIGBUS) {
    // 修改指定got表内容
    __atomic_store_n((uintptr_t *)got_addr, (uintptr_t)new_func, __ATOMIC_SEQ_CST);
    r = 0;
  }
  BYTESIG_CATCH() {
    bh_elf_set_error(caller_elf, true);
    bh_task_hooked(task, BYTEHOOK_STATUS_CODE_SET_GOT, caller_elf->pathname, orig_func);
    r = BYTEHOOK_STATUS_CODE_SET_GOT;
  }
  BYTESIG_EXIT

  // delete write permission
  // 删除写权限
  if (0 == (prot & PROT_WRITE)) bh_util_set_addr_protect(got_addr, prot);

  return r;
}
```



2.将got表中原始内容设置到task结构体中，以便unhook恢复

```c
 bh_task_set_manual_orig_func(task, orig_func);
 BH_LOG_INFO("hook chain: manual REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
              (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)task->new_func, task->sym_name,
              caller_elf->pathname);
```



3.return 原始地址

```c
// 这是作为指针传入的值，设置以后外部函数会使用这个值 
*orig_func_ret = orig_func;
```





##### automic mode

> 自动模式
>
> 1.添加hook function
>
> 2.将got表地址替换为trampo
>
> 3.返回原始函数地址

```c
// automatic mode:

// 1. add new-func to the hook chain
void *trampo = NULL;
void *orig_func_real = NULL;
r = bh_hook_manager_add_func(self, caller_elf, got_addr, orig_func, task, &trampo, &orig_func_real);

// 2. replace with the trampoline address if we haven't done it yet
if (0 == r && NULL != trampo) {
  // 将got表地址replace为trampo地址
  r = bh_hook_manager_replace_got_value(caller_elf, task, got_addr, orig_func, trampo);
  if (0 == r) { // hook成功 log
    BH_LOG_INFO("hook chain: auto REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
                (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)trampo, task->sym_name,
                caller_elf->pathname);
  } else { // hook失败移除之前添加的function
    bh_hook_manager_del_func(self, got_addr, task, NULL);
  }
}

// 3. return the original address
if (0 == r) *orig_func_ret = orig_func_real;
```



> 1.add function
>
> (1) 依据got表地址从红黑树中寻找hook结构体`bh_hook_t`
>
> (2) 如果没找到就创建一个hook结构体，插入红黑树
>
> ​	1）创建hook结构体
>
> ​	2）依据trampoline template生成trampoline function

```c
void *trampo = NULL;
void *orig_func_real = NULL;
r = bh_hook_manager_add_func(self, caller_elf, got_addr, orig_func, task, &trampo, &orig_func_real);

static int bh_hook_manager_add_func(bh_hook_manager_t *self, bh_elf_t *caller_elf, void *got_addr,
                                    void *orig_func, bh_task_t *task, void **trampo, void **orig_func_ret) {
  *trampo = NULL;
  int r;

  pthread_mutex_lock(&self->hooks_lock);

  // find or create hook chain
  bh_hook_t *hook = bh_hook_manager_find_hook(self, got_addr);
  *orig_func_ret = (NULL == hook ? orig_func : hook->orig_func);
  // 第一次插入显然是没有的，需要创建一个hook
  if (NULL == hook) hook = bh_hook_manager_create_hook(self, got_addr, orig_func, trampo);
  if (NULL == hook) {
    bh_task_hooked(task, BYTEHOOK_STATUS_CODE_NEW_TRAMPO, caller_elf->pathname, orig_func);
    r = BYTEHOOK_STATUS_CODE_NEW_TRAMPO;
    goto end;
  }

  // add new-func to hook chain
  // 将bh_hook_t添加进红黑树
  if (0 != (r = bh_hook_add_func(hook, task->new_func, task->id))) {
    bh_task_hooked(task, r, caller_elf->pathname, orig_func);
    goto end;
  }

  r = 0;  // OK

end:
  pthread_mutex_unlock(&self->hooks_lock);
  return r;
}
```



> hook结构体创建
>
> 1.结构体的初始化
>
> 2.创建trampoline function
>
> 3.插入hookmanager 红黑树中

```c
static bh_hook_t *bh_hook_manager_create_hook(bh_hook_manager_t *self, void *got_addr, void *orig_func,
                                              void **trampo) {
  // create hook chain
  // 结构体初始化
  bh_hook_t *hook = bh_hook_create(got_addr, orig_func);
  if (NULL == hook) return NULL;

  // create trampoline for the hook chain
  // 创建trampoline function
  *trampo = bh_trampo_create(hook);
  if (NULL == *trampo) {
    bh_hook_destroy(&hook);
    return NULL;
  }

  // save the hook chain
  // 插入到hookManager中
  RB_INSERT(bh_hook_tree, &self->hooks, hook);

  BH_LOG_INFO("hook chain: created for GOT %" PRIxPTR ", orig func %" PRIxPTR, (uintptr_t)got_addr,
              (uintptr_t)orig_func);
  return hook;
}
```



> 重点介绍下trampoline function的创建
>
> 过程如下
>
> 1.为trampoline function分配内存
>
> 2.填充code & data
>
> code填充的内容是bh_trampo_template函数
>
> data填充了两部分`bh_trampo_push_stack` 函数指针and `hook`结构体



> Node：
>
> trampo是一个跳板。
>
> 每一个got表会对应一个跳板函数。
>
> 也就是说我们的hook会由跳板去做管理。

```c
void *bh_trampo_create(bh_hook_t *hook) {
    // trampoline function 代码占据空间
  size_t code_size = (uintptr_t)(&bh_trampo_data) - (uintptr_t)(bh_trampo_template_pointer());
    // 存储数据占用空间
  size_t data_size = sizeof(void *) + sizeof(void *);

  // create trampoline
  // 为trampoline function分配内存
  void *trampo = bh_trampo_allocate(code_size + data_size);
  if (NULL == trampo) return NULL;

  // fill in code
  // 填充code
  // code填充的内容是bh_trampo_template函数
  // （源文件是汇编书写的，具体代码可见bh_trampo_XX.c，XX表示的是架构 arm、x86、...）
  BYTESIG_TRY(SIGSEGV, SIGBUS) {
    memcpy(trampo, bh_trampo_template_pointer(), code_size);
  }
  BYTESIG_CATCH() {
    return NULL;
  }
  BYTESIG_EXIT

  // file in data
  // 填充数据
  void **data = (void **)((uintptr_t)trampo + code_size);
  *data++ = (void *)bh_trampo_push_stack;
  *data = (void *)hook;

  // clear CPU cache
  __builtin___clear_cache((char *)trampo, (char *)trampo + code_size + data_size);

  BH_LOG_INFO("trampo: created for GOT %" PRIxPTR " at %" PRIxPTR ", size %zu + %zu = %zu",
              (uintptr_t)hook->got_addr, (uintptr_t)trampo, code_size, data_size, code_size + data_size);

#if defined(__arm__) && defined(__thumb__)
  trampo = (void *)((uintptr_t)trampo + 1);
#endif
  return trampo;
}
```



> 替换got表地址

```c
 // 2. replace with the trampoline address if we haven't done it yet
// 前提是trampo非null    
if (0 == r && NULL != trampo) {
    // 注意的是，这里的设置的函数地址不是func，是trampo！！
      r = bh_hook_manager_replace_got_value(caller_elf, task, got_addr, orig_func, trampo);
      if (0 == r) {
        BH_LOG_INFO("hook chain: auto REPLACE. GOT %" PRIxPTR ": %" PRIxPTR " -> %" PRIxPTR ", %s, %s",
                    (uintptr_t)got_addr, (uintptr_t)orig_func, (uintptr_t)trampo, task->sym_name,
                    caller_elf->pathname);
      } else {
        bh_hook_manager_del_func(self, got_addr, task, NULL);
      }
    }

```



> 返回origin address

```c
// 3. return the original address
    if (0 == r) *orig_func_ret = orig_func_real;
```






## bytehook_hook_partial



> 在分析了hook single以后，查看hook partial。
>
> 发现实现的原理都是类似的

```c
bytehook_stub_t bh_core_hook_partial(bytehook_caller_allow_filter_t caller_allow_filter,
                                     void *caller_allow_filter_arg, const char *callee_path_name,
                                     const char *sym_name, void *new_func, bytehook_hooked_t hooked,
                                     void *hooked_arg, uintptr_t caller_addr) {
  if (NULL == caller_allow_filter || NULL == sym_name || NULL == new_func) return NULL;
  if (BYTEHOOK_STATUS_CODE_OK != bh_core.init_status) return NULL;

  bh_task_t *task = bh_task_create_partial(caller_allow_filter, caller_allow_filter_arg, callee_path_name,
                                           sym_name, new_func, hooked, hooked_arg);
  if (NULL != task) {
    bh_task_manager_add(bh_core.task_mgr, task);
    bh_task_manager_hook(bh_core.task_mgr, task);
    bh_recorder_add_hook(BYTEHOOK_STATUS_CODE_MAX, "PARTIAL", sym_name, (uintptr_t)new_func, (uintptr_t)task,
                         caller_addr);
  }
  return (bytehook_stub_t)task;
}

```



> hook all & hook partial 的差别就是进入了不同的分支

```c
static void bh_task_handle(bh_task_t *self) {
  switch (self->type) {
    case BH_TASK_TYPE_SINGLE: {
      bh_elf_t *caller_elf = bh_elf_manager_find_elf(bh_core_global()->elf_mgr, self->caller_path_name);
      if (NULL != caller_elf) bh_task_hook_or_unhook(self, caller_elf);
      break;
    }
    case BH_TASK_TYPE_ALL:
    case BH_TASK_TYPE_PARTIAL:
      bh_elf_manager_iterate(bh_core_global()->elf_mgr, bh_task_elf_iterate_cb, (void *)self);
      break;
  }
}
```



> 主要的区别在于
>
> hook single由于知道caller & callee 直接就hook了。
>
> partial & all由于不知道caller具体有哪些，有些caller可能是后续dlopen加载的。
>
> 所以需要通过dl_iterator遍历所有elf文件

```c
bh_elf_manager_iterate(bh_core_global()->elf_mgr, bh_task_elf_iterate_cb, (void *)self);


static bool bh_task_elf_iterate_cb(bh_elf_t *elf, void *arg) {
  return bh_task_hook_or_unhook((bh_task_t *)arg, elf);
}
```



> bh_elf_manager_iterate。
>
> 1.`bh_elf_manager_t`中的elf指针全部拷贝一份
>
> 2.逐一调用callback
>
> 上述过程等价于遍历所有的elf文件逐一进行hook。



> `bh_elf_manager_t`的elf文件来源于dl monitor。
>
> dl monitor会hook dlopen方法，这样就能拿到所有加载的elf文件。

```c
void bh_elf_manager_iterate(bh_elf_manager_t *self, bh_elf_manager_iterate_cb_t cb, void *cb_arg) {
  if (0 == self->elfs_cnt) return;

  // get a copy of ELFs (only the pointers)
  bh_elf_t **copy_elfs = NULL;
  size_t copy_elfs_cnt = 0;
  pthread_rwlock_rdlock(&self->elfs_lock);
  if (self->elfs_cnt > 0) {
    if (NULL != (copy_elfs = malloc(sizeof(bh_elf_t *) * self->elfs_cnt))) {
      copy_elfs_cnt = self->elfs_cnt;
      size_t i = 0;
      bh_elf_t *elf;
      RB_FOREACH(elf, bh_elf_tree, &self->elfs) {
        copy_elfs[i++] = elf;
      }
    }
  }
  pthread_rwlock_unlock(&self->elfs_lock);

  // do callback copy ELFs (no need to lock)
  if (NULL != copy_elfs) {
    bool cb_next = true;
    for (size_t i = 0; i < copy_elfs_cnt; i++) {
      if (cb_next) cb_next = cb(copy_elfs[i], cb_arg);
    }
    free(copy_elfs);
  }
}
```



> 除了对需要hook的elf不确定以外。还有一大区别。
>
> 即是调用过滤。

```c
static bool bh_task_hook_or_unhook(bh_task_t *self, bh_elf_t *elf) {
  void (*hook_or_unhook)(bh_hook_manager_t *, bh_task_t *, bh_elf_t *) =
      (BH_TASK_STATUS_UNHOOKING == self->status ? bh_hook_manager_unhook : bh_hook_manager_hook);

  switch (self->type) {
    case BH_TASK_TYPE_SINGLE:
          // single hook 明确需要hook 调用链，只要caller match即可
      if (bh_elf_is_match(elf, self->caller_path_name)) {
        hook_or_unhook(bh_core_global()->hook_mgr, self, elf);
        if (BH_TASK_STATUS_UNHOOKING != self->status) self->status = BH_TASK_STATUS_FINISHED;
        return false;  // already found the ELF for single task, no need to continue
      }
      return true;  // continue
    case BH_TASK_TYPE_PARTIAL:
          // partial hook由于不明确调用链，所以需要一个过滤，以免hook过多。
      if (self->caller_allow_filter(elf->pathname, self->caller_allow_filter_arg))
        hook_or_unhook(bh_core_global()->hook_mgr, self, elf);
      return true;  // continue
    case BH_TASK_TYPE_ALL:
      hook_or_unhook(bh_core_global()->hook_mgr, self, elf);
      return true;  // continue
  }
}
```







## bytehook_hook_all



> 实现原理和hook partial && hook single 类似，hook all对比于hook partial没有过滤条件

```c
 case BH_TASK_TYPE_PARTIAL:
          // partial hook由于不明确调用链，所以需要一个过滤，以免hook过多。
      if (self->caller_allow_filter(elf->pathname, self->caller_allow_filter_arg))
        hook_or_unhook(bh_core_global()->hook_mgr, self, elf);
      return true;  // continue
case BH_TASK_TYPE_ALL:
      hook_or_unhook(bh_core_global()->hook_mgr, self, elf);
      return true;  // continue
```





# QA





## bh_dl_open_linker创建bh_dl_t的时候为什么要去读file？



> 描述：
>
> bh_dl_open_linker做了一件事情就是——创建bh_dl_t。
>
> 创建bh_dl_t需要做两个section的内容 & 大小（.symtab、.strtab）
>
> 
>
> 可以发现**// ELF info** 注解处其实是已经使用了从内存中获取的base地址获取ELF的基础信息。
>
> 为什么还需要bh_dl_load_symtab去读取文件呢？
>
> 直接使用base继续去读取section难道不会更快、更简单吗？

```c
void *bh_dl_open_linker(void) {
  uintptr_t base = bh_dl_find_linker_base_from_auxv();
#if __ANDROID_API__ < __ANDROID_API_J_MR2__
  if (0 == base) base = bh_dl_find_linker_base_from_maps();
#endif
  if (0 == base) return NULL;

  // ELF info
  ElfW(Ehdr) *ehdr = (ElfW(Ehdr) *)base;
  const ElfW(Phdr) *dlpi_phdr = (const ElfW(Phdr) *)(base + ehdr->e_phoff);
  ElfW(Half) dlpi_phnum = ehdr->e_phnum;

  // get bias
  uintptr_t min_vaddr = UINTPTR_MAX;
  for (size_t i = 0; i < dlpi_phnum; i++) {
    const ElfW(Phdr) *phdr = &(dlpi_phdr[i]);
    if (PT_LOAD == phdr->p_type) {
      if (min_vaddr > phdr->p_vaddr) min_vaddr = phdr->p_vaddr;
    }
  }
  if (UINTPTR_MAX == min_vaddr || base < min_vaddr) return NULL;
  uintptr_t load_bias = base - min_vaddr;

  // create bh_dl_t object
  bh_dl_t *self;
  if (NULL == (self = calloc(1, sizeof(bh_dl_t)))) return NULL;
  self->load_bias = load_bias;
  self->base = base;
  if (0 != bh_dl_load_symtab(self, BH_CONST_PATHNAME_LINKER)) {
    free(self);
    return NULL;
  }
  return (void *)self;
}
```



> 回答：
>
> 通过测试发现
>
> 如果使用base去读section会报错。
>
> Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr XXXX
>
> 也就是说，地址非法。
>
> 因为process在加载的时候不会加载section header



## automic mode & manual mode的区别？



> automic mode更适合复杂的hook。
>
> 因为有trampoline管理我们的hook链，更加适合可能出现重复hook的情况。



> manual mode适合简单的hook。
>
> 手动模式下只是简单的替换got表。
>
> 如果是重复hook，比谁后hook了。因为后一次的hook会覆盖前一次。



## PLT/GOT hook的局限性？



> 从上面的原理分析中我们可以知道一点。
>
> PLT/GOT hook 只能hook有PLT/GOT表参与的函数调用。
>
> 如果没有，就无法实现。



> 然而不是说所有的函数调用都有PLT/GOT表。
>
> 只有跨模块调用才有。即调用外部的so文件的情况下，编译器才会生成PLT/GOT



> **模块内**的函数调用是使用的相对地址。**没有PLT/GOT表的参与**，所以**Hook失效**
