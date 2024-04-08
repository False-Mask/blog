---
title: ShadowHook原理分析
tags:
  - c
  - inline hook
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/shadow-hook-principle.drawio.png
date: 2024-04-08 17:40:04
---




# ShadowHook原理分析

![shadow-hook-principle.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/shadow-hook-principle.drawio.png)





# 初始化



> 无论是使用Native初始化还是Java进行初始化。最后其实都会调用到shadowhook_init方法



init的实际初始化逻辑包含如下几个过程

1. errno init

2. 信号量处理初始化（sigsegv、sigbus）

3. enter、exit初始化

4. mode相关初始化

   a) shared: safe_init + hub_init

   b) unique: linker_init

```c
int shadowhook_init(shadowhook_mode_t mode, bool debuggable) {
  bool do_init = false;
  // check是否没有初始化
  if (__predict_true(SHADOWHOOK_ERRNO_UNINIT == shadowhook_init_errno)) {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    // 加锁防止多线程重复初始化
    pthread_mutex_lock(&lock);
    if (__predict_true(SHADOWHOOK_ERRNO_UNINIT == shadowhook_init_errno)) {
      do_init = true;
      shadowhook_mode = mode;
      sh_log_set_debuggable(debuggable);

// 错误处理 <== 开始
#define GOTO_END(errnum)            \
  do {                              \
    shadowhook_init_errno = errnum; \
    goto end;                       \
  } while (0)
// 错误处理 ==> 结束

        // 实际的初始化
        // 异常处理初始化
      if (__predict_false(0 != sh_errno_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_ERRNO);
        // SIGSEGV信号处理
      if (__predict_false(0 != bytesig_init(SIGSEGV))) GOTO_END(SHADOWHOOK_ERRNO_INIT_SIGSEGV);
      	// SIGBUS信号处理
      if (__predict_false(0 != bytesig_init(SIGBUS))) GOTO_END(SHADOWHOOK_ERRNO_INIT_SIGBUS);
        // enter初始化
      if (__predict_false(0 != sh_enter_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_ENTER);
        // exit初始化
      sh_exit_init();
        // mode初始化
      if (SHADOWHOOK_MODE_SHARED == shadowhook_mode) {
        if (__predict_false(0 != sh_safe_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_SAFE);
        if (__predict_false(0 != sh_hub_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_HUB);
      } else {
        if (__predict_false(0 != sh_linker_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_LINKER);
      }

#undef GOTO_END

      shadowhook_init_errno = SHADOWHOOK_ERRNO_OK;
    }
  end:
    pthread_mutex_unlock(&lock);
  }

  SH_LOG_ALWAYS_SHOW("%s: shadowhook init(mode: %s, debuggable: %s), return: %d, real-init: %s",
                     shadowhook_get_version(), SHADOWHOOK_MODE_SHARED == mode ? "SHARED" : "UNIQUE",
                     debuggable ? "true" : "false", shadowhook_init_errno, do_init ? "yes" : "no");
  SH_ERRNO_SET_RET_ERRNUM(shadowhook_init_errno);
}
```



## errono init

> 为多线程环境初始化thread local。

```c
int sh_errno_init(void) {
    // 初始化 pthread_key(用于thread local)
  if (__predict_false(0 != pthread_key_create(&sh_errno_tls_key, NULL))) {
    sh_errno_global = SHADOWHOOK_ERRNO_INIT_ERRNO;
    return -1;
  }
  sh_errno_global = SHADOWHOOK_ERRNO_OK;
  return 0;
}
```

## signal init

> 信号的初始化包含两个部分
>
> sigsegv：段错误
>
> sigbus：总线错误

```c
 if (__predict_false(0 != bytesig_init(SIGSEGV))) GOTO_END(SHADOWHOOK_ERRNO_INIT_SIGSEGV);
 if (__predict_false(0 != bytesig_init(SIGBUS))) GOTO_END(SHADOWHOOK_ERRNO_INIT_SIGBUS);
```



```c
int bytesig_init(int signum) {
    // 判断值的合法性
  if (__predict_false(signum <= 0 || signum >= __SIGRTMIN || signum == SIGKILL || signum == SIGSTOP))
    return -1;
  if (__predict_false(BYTESIG_STATUS_UNAVAILABLE == bytesig_status)) return -1;
  if (__predict_false(NULL != bytesig_signal_array[signum])) return -1;
    // 加锁
  static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_lock(&lock);
  int ret = -1;
    // check是否init过了
  if (__predict_false(NULL != bytesig_signal_array[signum])) goto end;
	// 初始化结构体
  bytesig_signal_t *sig = calloc(1, sizeof(bytesig_signal_t));
  if (__predict_false(NULL == sig)) goto end;

#define SA_EXPOSE_TAGBITS 0x00000800

    // 信号量注册宏定义（通过suffix确认64位还是32位） 
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
  // 通过架构位数，判断是否哪个宏定义
  if (BYTESIG_STATUS_SIG64 == bytesig_status)
    REGISTER_SIGNAL_HANDLER(64);
  else
    REGISTER_SIGNAL_HANDLER();

  bytesig_signal_array[signum] = sig;
  ret = 0;  // OK

end:
  pthread_mutex_unlock(&lock);
  return ret;
}
```



## enter & exit init



> 只是初始化了sh_enter_trampo_mgr（也就是一个单链表）

```c
int sh_enter_init(void) {
  sh_trampo_init_mgr(&sh_enter_trampo_mgr, SH_ENTER_PAGE_NAME, SH_ENTER_SZ, SH_ENTER_DELAY_SEC);
  return 0;
}
```



```c
void sh_trampo_init_mgr(sh_trampo_mgr_t *mem_mgr, const char *page_name, size_t trampo_size,
                        time_t delay_sec) {
    // 初始化单链表
  SLIST_INIT(&mem_mgr->pages);
    // 初始化pthread mutex
  pthread_mutex_init(&mem_mgr->pages_lock, NULL);
    // page name复制
  mem_mgr->page_name = page_name;
    // 4字节对齐
  mem_mgr->trampo_size = SH_UTIL_ALIGN_END(trampo_size, SH_TRAMPO_ALIGN);
  mem_mgr->delay_sec = delay_sec;
}
```



> Exit 同Enter逻辑
>
> 只是多了一部分用来解析linker elf文件信息

```c
void sh_exit_init(void) {
  // init for out-library mode
  sh_trampo_init_mgr(&sh_exit_trampo_mgr, SH_EXIT_PAGE_NAME, SH_EXIT_SZ, SH_EXIT_DELAY_SEC);

  // init for in-library mode
  sh_exit_init_elfinfo(AT_PHDR, &sh_exit_app_process_info);
  sh_exit_init_elfinfo(AT_BASE, &sh_exit_linker_info);
  sh_exit_init_elfinfo(AT_SYSINFO_EHDR, &sh_exit_vdso_info);
}
```



## mode init

 

### shard

> Shard mode需要初始化
>
> safe & hub

```c
if (__predict_false(0 != sh_safe_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_SAFE);
if (__predict_false(0 != sh_hub_init())) GOTO_END(SHADOWHOOK_ERRNO_INIT_HUB);
```



> safe init
>
> 确保libc中存有如下方法
>
> - pthread_getspecific
> - pthread_setspecific
> - abort

```c
int sh_safe_init(void) {
  sh_safe_api_level = sh_util_get_api_level();

  void *handle = xdl_open("libc.so", XDL_DEFAULT);
  if (NULL == handle) return -1;

  int r = -1;
  if (__predict_false(0 != sh_safe_init_func(handle, "pthread_getspecific", SH_SAFE_IDX_PTHREAD_GETSPECIFIC)))
    goto end;
  if (__predict_false(0 != sh_safe_init_func(handle, "pthread_setspecific", SH_SAFE_IDX_PTHREAD_SETSPECIFIC)))
    goto end;
  if (__predict_false(0 != sh_safe_init_func(handle, "abort", SH_SAFE_IDX_ABORT))) goto end;
  r = 0;

end:
  xdl_close(handle);
  return r;
}
```



> hub init
>
> 1. 初始化tls key
> 2. 初始化hub stack cache & stack cache used（一个用来保存栈帧、一个用来初始化已使用的换成下标）
> 3. 初始化trampoline跳板函数。以及trampoline manager

```c
int sh_hub_init(void) {
  LIST_INIT(&sh_hub_delayed_destroy);
  pthread_mutex_init(&sh_hub_delayed_destroy_lock, NULL);

  // init TLS key
  if (__predict_false(0 != pthread_key_create(&sh_hub_stack_tls_key, sh_hub_stack_destroy))) return -1;

  // init hub's stack cache
  if (__predict_false(NULL == (sh_hub_stack_cache = malloc(SH_HUB_THREAD_MAX * sizeof(sh_hub_stack_t)))))
    return -1;
  if (__predict_false(NULL == (sh_hub_stack_cache_used = calloc(SH_HUB_THREAD_MAX, sizeof(uint8_t)))))
    return -1;

  // init hub's trampoline manager
  size_t code_size = (uintptr_t)(&sh_hub_trampo_template_data) - (uintptr_t)(sh_hub_trampo_template_start());
  size_t data_size = sizeof(void *) + sizeof(void *);
  sh_trampo_init_mgr(&sh_hub_trampo_mgr, SH_HUB_TRAMPO_PAGE_NAME, code_size + data_size,
                     SH_HUB_TRAMPO_DELAY_SEC);

  return 0;
}
```





### unique



> 初始化linker.
>
> 1. 根据指令集架构open linker or linker64
> 2. 获取g_dl_mutex地址
> 3. 获取do_dlopen地址

```c
int sh_linker_init(void) {
  memset(&sh_linker_dlopen_dlinfo, 0, sizeof(sh_linker_dlopen_dlinfo));

  int api_level = sh_util_get_api_level();
  if (__predict_true(api_level >= __ANDROID_API_L__)) {
    sh_linker_dlopen_addr = 0;
	// open linker or linker64
    void *handle = xdl_open(SH_LINKER_BASENAME, XDL_DEFAULT);
    if (__predict_false(NULL == handle)) return -1;
    xdl_info(handle, XDL_DI_DLINFO, (void *)&sh_linker_dlopen_dlinfo);
    sh_linker_dlopen_dlinfo.dli_fname = SH_LINKER_BASENAME;

    // get g_dl_mutex
    sh_linker_g_dl_mutex = (pthread_mutex_t *)(xdl_dsym(handle, SH_LINKER_SYM_G_DL_MUTEX, NULL));
    if (NULL == sh_linker_g_dl_mutex && api_level >= __ANDROID_API_U__)
      sh_linker_g_dl_mutex = (pthread_mutex_t *)(xdl_dsym(handle, SH_LINKER_SYM_G_DL_MUTEX_U_QPR2, NULL));

    // get do_dlopen
    if (api_level >= __ANDROID_API_O__)
      sh_linker_dlopen_dlinfo.dli_sname = SH_LINKER_SYM_DO_DLOPEN_O;
    else if (api_level >= __ANDROID_API_N__)
      sh_linker_dlopen_dlinfo.dli_sname = SH_LINKER_SYM_DO_DLOPEN_N;
    else
      sh_linker_dlopen_dlinfo.dli_sname = SH_LINKER_SYM_DO_DLOPEN_L;
    sh_linker_dlopen_dlinfo.dli_saddr =
        xdl_dsym(handle, sh_linker_dlopen_dlinfo.dli_sname, &(sh_linker_dlopen_dlinfo.dli_ssize));
    sh_linker_dlopen_addr = (uintptr_t)sh_linker_dlopen_dlinfo.dli_saddr;

    xdl_close(handle);
  }

  return (0 != sh_linker_dlopen_addr && (NULL != sh_linker_g_dl_mutex || api_level < __ANDROID_API_L__)) ? 0
                                                                                                      : -1;
}
```



# Hook





## shadowhook_hook_func_addr



> shadowhook_hook_func_addr——
>
> 1. 用于hook**已经加载到内存**中的so文件。
>
> 2. **只能**hook在**符号表**中**有记录**的函数



> Hookhook流程原理图如下：



![shadow-hook.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/shadow-hook.drawio.png)



图中有一些关键的要素信息，进行介绍

- target_addr

  > 被hook的方法的地址

- prev func

  > 被hook后返回的方法地址

- trampo

  > hook过程中会覆盖原方法中一定的区域，加上跳转方法

- exit

  > 用于跳转到指定hook方法的跳板。

- enter

  > 用于返回执行的跳板

可以发现其实Inline Hook其实就是——**修改需要Hook函数的前几位汇编代码，直接通过exit跳板跳转到hook方法。必要时再通过enter跳板跳转回来**。



接下来会进行详细的代码讲解。



> 根据func address hook指定的function

```c
void *shadowhook_hook_func_addr(void *func_addr, void *new_addr, void **orig_addr) {
  const void *caller_addr = __builtin_return_address(0);
  return shadowhook_hook_addr_impl(func_addr, new_addr, orig_addr, true, (uintptr_t)caller_addr);
}
```



> 内部实现
>
> 1. 检查参数
>
> 2. 创建task
>
> 3. hook

```c
static void *shadowhook_hook_addr_impl(void *sym_addr, void *new_addr, void **orig_addr,
                                       bool ignore_symbol_check, uintptr_t caller_addr) {
 // ......

  int r;
    // 参数检查
  if (NULL == sym_addr || NULL == new_addr) GOTO_ERR(SHADOWHOOK_ERRNO_INVALID_ARG);
  	// ......

  // create task
  sh_task_t *task =
      sh_task_create_by_target_addr((uintptr_t)sym_addr, (uintptr_t)new_addr, (uintptr_t *)orig_addr,
                                    ignore_symbol_check, (uintptr_t)caller_addr);
  if (NULL == task) GOTO_ERR(SHADOWHOOK_ERRNO_OOM);

  // do hook
  r = sh_task_hook(task);
  if (0 != r) {
    sh_task_destroy(task);
    GOTO_ERR(r);
  }

  // OK
  // ......

err:
  // 异常处理
  // ......
}
```



> task创建

```c
sh_task_t *sh_task_create_by_target_addr(uintptr_t target_addr, uintptr_t new_addr, uintptr_t *orig_addr,
                                         bool ignore_symbol_check, uintptr_t caller_addr) {
  sh_task_t *self = malloc(sizeof(sh_task_t)); // 分配内存
  if (NULL == self) return NULL;
    // 记录函数参数
  self->lib_name = NULL;
  self->sym_name = NULL;
  self->target_addr = target_addr;
  self->new_addr = new_addr;
  self->orig_addr = orig_addr;
  self->hooked = NULL;
  self->hooked_arg = NULL;
  self->caller_addr = caller_addr;
  self->finished = false;
  self->error = false;
  self->ignore_symbol_check = ignore_symbol_check;

  return self;
}
```



> Hook

```c
int sh_task_hook(sh_task_t *self) {
  int r;
  bool is_hook_sym_addr = true;
  char real_lib_name[512] = "unknown";
  char real_sym_name[1024] = "unknown";
  size_t backup_len = 0;

  // find target-address by library-name and symbol-name
  xdl_info_t dlinfo;
  memset(&dlinfo, 0, sizeof(xdl_info_t));
  if (0 == self->target_addr) { // 如果hook的addr为null，通过libname和symname寻找addr
    is_hook_sym_addr = false;
    strlcpy(real_lib_name, self->lib_name, sizeof(real_lib_name));
    strlcpy(real_sym_name, self->sym_name, sizeof(real_sym_name));
    r = sh_linker_get_dlinfo_by_sym_name(self->lib_name, self->sym_name, &dlinfo, real_lib_name,
                                         sizeof(real_lib_name));
    if (SHADOWHOOK_ERRNO_PENDING == r) {
      // we need to start monitor linker dlopen for handle the pending task
      if (0 != (r = sh_task_start_monitor(true))) goto end;
      r = SHADOWHOOK_ERRNO_PENDING;
      goto end;
    }
    if (0 != r) goto end;                             // error
    self->target_addr = (uintptr_t)dlinfo.dli_saddr;  // OK
  } else { // 获取dl_info
    r = sh_linker_get_dlinfo_by_addr((void *)self->target_addr, &dlinfo, real_lib_name, sizeof(real_lib_name),
                                     real_sym_name, sizeof(real_sym_name), self->ignore_symbol_check);
    if (0 != r) goto end;  // error
  }

  // 为unique mode hook dlopeb or do_dlopen函数
  if (sh_linker_need_to_hook_dlopen(self->target_addr)) {
    SH_LOG_INFO("task: hook dlopen/do_dlopen internal. target-address %" PRIxPTR, self->target_addr);
    if (0 != (r = sh_task_start_monitor(false))) goto end;
  }

  // 替换target address对应的function
  r = sh_switch_hook(self->target_addr, self->new_addr, self->orig_addr, &backup_len, &dlinfo);
  self->finished = true;

end:
  if (0 == r || SHADOWHOOK_ERRNO_PENDING == r)  // 如果请求为一个pending，则加入队列中
  {
    pthread_rwlock_wrlock(&sh_tasks_lock);
    TAILQ_INSERT_TAIL(&sh_tasks, self, link);
    if (!self->finished) __atomic_add_fetch(&sh_tasks_unfinished_cnt, 1, __ATOMIC_SEQ_CST);
    pthread_rwlock_unlock(&sh_tasks_lock);
  }

  // 记录hook结果
  sh_recorder_add_hook(r, is_hook_sym_addr, self->target_addr, real_lib_name, real_sym_name, self->new_addr,
                       backup_len, (uintptr_t)self, self->caller_addr);

  return r;
}
```





> inline hook
>
> 对unique & shared mode单独做处理
>
> 1. unique mode无需跳板函数（trampoline）
> 2. shared mode会由跳板函数管理hook请求

```c
int sh_switch_hook(uintptr_t target_addr, uintptr_t new_addr, uintptr_t *orig_addr, size_t *backup_len,
                   xdl_info_t *dlinfo) {
  int r;
  if (SHADOWHOOK_IS_UNIQUE_MODE)
    r = sh_switch_hook_unique(target_addr, new_addr, orig_addr, backup_len, dlinfo);
  else
    r = sh_switch_hook_shared(target_addr, new_addr, orig_addr, backup_len, dlinfo);

  if (0 == r)
    SH_LOG_INFO("switch: hook in %s mode OK: target_addr %" PRIxPTR ", new_addr %" PRIxPTR,
                SHADOWHOOK_IS_UNIQUE_MODE ? "UNIQUE" : "SHARED", target_addr, new_addr);

  return r;
}
```



### Unique Mode

> hook unique
>
> 1. check是否重复hook
> 2. 开辟新的switch
> 3. 插入新的switch 到 switch缓存（红黑树）
> 4. 进行hook

```c
static int sh_switch_hook_unique(uintptr_t target_addr, uintptr_t new_addr, uintptr_t *orig_addr,
                                 size_t *backup_len, xdl_info_t *dlinfo) {
    // check是否重复hook
  sh_switch_t *self = sh_switch_find(target_addr);
  if (NULL != self) return SHADOWHOOK_ERRNO_HOOK_DUP;

  // alloc new switch
  int r;
  if (0 != (r = sh_switch_create(&self, target_addr, NULL))) return r;

  sh_switch_t *useless = NULL;
  pthread_rwlock_wrlock(&sh_switches_lock);  // SYNC - start

  // insert new switch to switch-tree
  if (NULL != RB_INSERT(sh_switch_tree, &sh_switches, self)) {
    useless = self;
    r = SHADOWHOOK_ERRNO_HOOK_DUP;
    goto end;
  }

  // do hook
  if (0 != (r = sh_inst_hook(&self->inst, target_addr, dlinfo, new_addr, orig_addr, NULL))) {
    RB_REMOVE(sh_switch_tree, &sh_switches, self);
    useless = self;
    goto end;
  }
  *backup_len = self->inst.backup_len;
  sh_switch_dump_enter(self);

end:
  pthread_rwlock_unlock(&sh_switches_lock);  // SYNC - end
  if (NULL != useless) sh_switch_destroy(useless, false);
  return r;
}
```



> hook

```c
int sh_inst_hook(sh_inst_t *self, uintptr_t target_addr, xdl_info_t *dlinfo, uintptr_t new_addr,
                 uintptr_t *orig_addr, uintptr_t *orig_addr2) {
  self->enter_addr = sh_enter_alloc();
  if (0 == self->enter_addr) return SHADOWHOOK_ERRNO_HOOK_ENTER;

  int r;
#ifdef SH_CONFIG_TRY_WITH_EXIT
  if (0 == (r = sh_inst_hook_with_exit(self, target_addr, dlinfo, new_addr, orig_addr, orig_addr2))) return r;
#endif
  if (0 == (r = sh_inst_hook_without_exit(self, target_addr, dlinfo, new_addr, orig_addr, orig_addr2)))
    return r;

  // hook failed
  if (NULL != orig_addr) *orig_addr = 0;
  if (NULL != orig_addr2) *orig_addr2 = 0;
  sh_enter_free(self->enter_addr);
  return r;
}
```



> try with exit

```c
static int sh_inst_hook_with_exit(sh_inst_t *self, uintptr_t target_addr, xdl_info_t *dlinfo,
                                  uintptr_t new_addr, uintptr_t *orig_addr, uintptr_t *orig_addr2) {
  int r;
  uintptr_t pc = target_addr;
  // 备份长度为4
  self->backup_len = 4;

  if (dlinfo->dli_ssize < self->backup_len) return SHADOWHOOK_ERRNO_HOOK_SYMSZ;

  // 写入exit指令
  //  LDR X17, #8（new_addr）
  //  BR X17
  sh_a64_absolute_jump_with_br(self->exit, new_addr);
  // 分配一块内存，将exit的内容全部拷贝到这块内存中
  if (0 !=
      (r = sh_exit_alloc(&self->exit_addr, (uint16_t *)&self->exit_type, pc, dlinfo, (uint8_t *)(self->exit),
                         sizeof(self->exit), SH_INST_A64_B_RANGE_LOW, SH_INST_A64_B_RANGE_HIGH)))
    return r;

  // 设置hook函数位置的权限，[target_addr ~ target_addr + backup_len]（rwx）
  if (0 != sh_util_mprotect(target_addr, self->backup_len, PROT_READ | PROT_WRITE | PROT_EXEC)) {
    r = SHADOWHOOK_ERRNO_MPROT;
    goto err;
  }
  SH_SIG_TRY(SIGSEGV, SIGBUS) {
      // 写入enter指令
    r = sh_inst_hook_rewrite(self, target_addr, orig_addr, orig_addr2);
  }
  SH_SIG_CATCH() {
    r = SHADOWHOOK_ERRNO_HOOK_REWRITE_CRASH;
    goto err;
  }
  SH_SIG_EXIT
  if (0 != r) goto err;

  // 相对跳转 B <label>
  sh_a64_relative_jump(self->trampo, self->exit_addr, pc);
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  // 覆盖原函数开头四字节
  if (0 != (r = sh_util_write_inst(target_addr, self->trampo, self->backup_len))) goto err;

  SH_LOG_INFO("a64: hook (WITH EXIT) OK. target %" PRIxPTR " -> exit %" PRIxPTR " -> new %" PRIxPTR
              " -> enter %" PRIxPTR " -> remaining %" PRIxPTR,
              target_addr, self->exit_addr, new_addr, self->enter_addr, target_addr + self->backup_len);
  return 0;

err:
  sh_exit_free(self->exit_addr, (uint16_t)self->exit_type, (uint8_t *)(self->exit), sizeof(self->exit));
  self->exit_addr = 0;  // this is a flag for with-exit or without-exit
  return r;
}
```



> 可能还是不够直观，我们将一个Hook的示例代码进行演示他的hook原理

```c
// 原来函数地址
void *orig;
// stubs用于做取消
void *stub;

typedef void *(*malloc_t)(size_t);

void *my_malloc(size_t sz) {
    // 调用原函数
    return ((malloc_t) orig)(sz);
}

// 如下hook对malloc函数的进行了inline hook，将malloc调用强行跳转到了my_malloc
void do_hook(void) {
    stub = shadowhook_hook_func_addr((void *) malloc, (void *) my_malloc, &orig);
}

```



> 1. inline hook覆盖了malloc第一个指令，跳转到了exit跳板
> 2. exit跳板，直接跳转到了my_malloc函数地址
> 3. my_malloc函数中调用了origin函数指针，函数执行流程返回到了原malloc函数继续执行。

![shadow-hook-func.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/shadow-hook-func.drawio-1712142723865-3.png)



### Shared Mode



> Shared Mode

```c
static int sh_switch_hook_shared(uintptr_t target_addr, uintptr_t new_addr, uintptr_t *orig_addr,
                                 size_t *backup_len, xdl_info_t *dlinfo) {
  int r;
  pthread_rwlock_rdlock(&sh_switches_lock); 
    // 寻找是否已经hook
  sh_switch_t key = {.target_addr = target_addr};
  sh_switch_t *self = RB_FIND(sh_switch_tree, &sh_switches, &key);
    // 如果已经存在，将proxy加入hub中
  if (NULL != self)  
  {
    if (NULL != orig_addr) *orig_addr = sh_hub_get_orig_addr(self->hub);
    r = sh_hub_add_proxy(self->hub, new_addr);
    pthread_rwlock_unlock(&sh_switches_lock);  // SYNC(read) - end

    *backup_len = self->inst.backup_len;
    return r;
  }
  pthread_rwlock_unlock(&sh_switches_lock);  // SYNC(read) - end

  // first hook for this target_addr

  // 开辟sh_switch, 注意这里传入了hub_trampo
  // 即sh_switch_create中会用trampoline模板创建一个跳板函数
  uintptr_t hub_trampo;
  if (0 != (r = sh_switch_create(&self, target_addr, &hub_trampo))) return r;

  sh_switch_t *useless = NULL;
  pthread_rwlock_wrlock(&sh_switches_lock);  // SYNC - start

  // 将switch插入红黑树中
  sh_switch_t *exists;
  if (NULL != (exists = RB_INSERT(sh_switch_tree, &sh_switches, self))) {
    // 考虑线程安全问题。已经添加的情况
    useless = self;
    if (NULL != orig_addr) *orig_addr = sh_hub_get_orig_addr(exists->hub);
    r = sh_hub_add_proxy(exists->hub, new_addr);
    *backup_len = exists->inst.backup_len;
  } else {
    // do hook
    uintptr_t *safe_orig_addr_addr = sh_safe_get_orig_addr_addr(target_addr);
    if (0 != (r = sh_inst_hook(&self->inst, target_addr, dlinfo, hub_trampo,
                               sh_hub_get_orig_addr_addr(self->hub), safe_orig_addr_addr))) {
      RB_REMOVE(sh_switch_tree, &sh_switches, self);
      useless = self;
      goto end;
    }
    *backup_len = self->inst.backup_len;
    sh_switch_dump_enter(self);

    // return original-address
    if (NULL != orig_addr) *orig_addr = sh_hub_get_orig_addr(self->hub);

    // add proxy to hub
    if (0 != (r = sh_hub_add_proxy(self->hub, new_addr))) {
      sh_inst_unhook(&self->inst, target_addr);
      *backup_len = 0;
      RB_REMOVE(sh_switch_tree, &sh_switches, self);
      useless = self;
      goto end;
    }
  }

end:
  pthread_rwlock_unlock(&sh_switches_lock);  // SYNC - end
  if (NULL != useless) sh_switch_destroy(useless, false);

  return r;
}
```



> 这里一行代码就可以解释Shared & Unique Mode的差别
>
> unique mode下new_addr传入的用户指定的值，shared mode传入的是hub_trampo的值，即trampoline模板的值

```c
sh_inst_hook(&self->inst, target_addr, dlinfo, hub_trampo,
                               sh_hub_get_orig_addr_addr(self->hub), safe_orig_addr_addr)
```



> 所以我们可以得知，就hook原理上就只有一个区别。
>
> unique mode下函数是没有被包装的，shared mode会包装一层trampoline，由跳转管理我们的函数调用。



> 如下是template的代码
>
> 1.调用sh_hub_push_stack获取proxy函数地址
>
> 2.调用sh_hub_push_stack的返回的函数地址

```c
extern void *sh_hub_trampo_template_data __attribute__((visibility("hidden")));
__attribute__((naked)) static void sh_hub_trampo_template(void) {
#if defined(__arm__)
  __asm__(
      // Save parameter registers, LR
      "push  { r0 - r3, lr }     \n"

      // Call sh_hub_push_stack()
      "ldr   r0, hub_ptr         \n"
      "mov   r1, lr              \n"
      "ldr   ip, push_stack      \n"
      "blx   ip                  \n"

      // Save the hook function's address to IP register
      "mov   ip, r0              \n"

      // Restore parameter registers, LR
      "pop   { r0 - r3, lr }     \n"

      // Call hook function
      "bx    ip                  \n"

      "sh_hub_trampo_template_data:"
      ".global sh_hub_trampo_template_data;"
      "push_stack:"
      ".word 0;"
      "hub_ptr:"
      ".word 0;");
#elif defined(__aarch64__)
  __asm__(
      // Save parameter registers, XR(X8), LR
      "stp   x0, x1, [sp, #-0xd0]!    \n"
      "stp   x2, x3, [sp, #0x10]      \n"
      "stp   x4, x5, [sp, #0x20]      \n"
      "stp   x6, x7, [sp, #0x30]      \n"
      "stp   x8, lr, [sp, #0x40]      \n"
      "stp   q0, q1, [sp, #0x50]      \n"
      "stp   q2, q3, [sp, #0x70]      \n"
      "stp   q4, q5, [sp, #0x90]      \n"
      "stp   q6, q7, [sp, #0xb0]      \n"

      // Call sh_hub_push_stack()
      "ldr   x0, hub_ptr              \n"
      "mov   x1, lr                   \n"
      "ldr   x16, push_stack          \n"
      "blr   x16                      \n"

      // Save the hook function's address to IP register
      "mov   x16, x0                  \n"

      // Restore parameter registers, XR(X8), LR
      "ldp   q6, q7, [sp, #0xb0]      \n"
      "ldp   q4, q5, [sp, #0x90]      \n"
      "ldp   q2, q3, [sp, #0x70]      \n"
      "ldp   q0, q1, [sp, #0x50]      \n"
      "ldp   x8, lr, [sp, #0x40]      \n"
      "ldp   x6, x7, [sp, #0x30]      \n"
      "ldp   x4, x5, [sp, #0x20]      \n"
      "ldp   x2, x3, [sp, #0x10]      \n"
      "ldp   x0, x1, [sp], #0xd0      \n"

      // Call hook function
      "br    x16                      \n"

      "sh_hub_trampo_template_data:"
      ".global sh_hub_trampo_template_data;"
      "push_stack:"
      ".quad 0;"
      "hub_ptr:"
      ".quad 0;");
#endif
}
```





## shadowhook_hook_func_addr



> 我们可以对比之前分析的hook_func_addr 
>
> 可以发现——除了传入的参数有一个不太一样以外(ignore_symbol_check)，其他的过程是一模一样的
>
> （ignore_symbol_check）

```c
static void *shadowhook_hook_addr_impl(void *sym_addr, void *new_addr, void **orig_addr,
                                       bool ignore_symbol_check, uintptr_t caller_addr) {
    // ......
}

void *shadowhook_hook_func_addr(void *func_addr, void *new_addr, void **orig_addr) {
  const void *caller_addr = __builtin_return_address(0);
  return shadowhook_hook_addr_impl(func_addr, new_addr, orig_addr, true, (uintptr_t)caller_addr);
}

void *shadowhook_hook_sym_addr(void *sym_addr, void *new_addr, void **orig_addr) {
  const void *caller_addr = __builtin_return_address(0);
  return shadowhook_hook_addr_impl(sym_addr, new_addr, orig_addr, false, (uintptr_t)caller_addr);
}
```



> 在进行sh_linker 调用sh_linker_get_dlinfo_by_addr获取dl_info的时候有一定的差异
>
> - 如果ignore_symbol_check开启，没有找到匹配addr的符号信息，会忽略符号的检查，继续hook
>
> - 对于没有开启的，会直接结束hook流程。

```c
 bool crashed = false;
  void *dlcache = NULL;
  int r = 0;

// 通过addr寻找动态链接的信息，将信息存储在dlinfo变量中
  if (sh_util_get_api_level() >= __ANDROID_API_L__) {
    r = xdl_addr((void *)addr, dlinfo, &dlcache);
  } else {
    SH_SIG_TRY(SIGSEGV, SIGBUS) {
      r = xdl_addr((void *)addr, dlinfo, &dlcache);
    }
    SH_SIG_CATCH() {
      crashed = true;
    }
    SH_SIG_EXIT
  }

  // check error
  // ......

  // 对于没有找到addr对应的符号信息的hook项， symbol hook则关闭符号检测，func hook直接结束hook。
  if (NULL == dlinfo->dli_sname) {
    if (ignore_symbol_check) {
      dlinfo->dli_saddr = addr;
      dlinfo->dli_sname = "unknown";
      dlinfo->dli_ssize = 1024;  // big enough
    } else {
      const char *matched_dlfcn_name = NULL;
      if (NULL == (matched_dlfcn_name = sh_linker_match_dlfcn((uintptr_t)addr))) {
        r = SHADOWHOOK_ERRNO_HOOK_DLINFO;
        goto end;
      } else {
        dlinfo->dli_saddr = addr;
        dlinfo->dli_sname = matched_dlfcn_name;
        dlinfo->dli_ssize = 4;  // safe length, only relative jumps are allowed
        SH_LOG_INFO("task: match dlfcn, target_addr %p, sym_name %s", addr, matched_dlfcn_name);
      }
    }
  }

//......

end:
  xdl_addr_clean(&dlcache);
  return r;
}
```





## shadowhook_hook_sym_name



> 逻辑图如下：

![libname-symname-hook.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/libname-symname-hook.drawio.png)

> 这种方式可以 hook “当前已加载到进程中的动态库”，也可以 hook “还没有加载到进程中的动态库”（如果 hook 时动态库还未加载，ShadowHook 内部会记录当前的 hook “诉求”，后续一旦目标动态库被加载到内存中，将立刻执行 hook 操作）。



> 具体hook代码分析如下：

> hook sym name 换了一个方法控制hook逻辑（不同于func_addr、sym_addr）

```c
void *shadowhook_hook_sym_name(const char *lib_name, const char *sym_name, void *new_addr, void **orig_addr) {
  const void *caller_addr = __builtin_return_address(0);
  return shadowhook_hook_sym_name_impl(lib_name, sym_name, new_addr, orig_addr, NULL, NULL,
                                       (uintptr_t)caller_addr);
}
```



> hook大体的逻辑貌似是没什么变化
>
> 1. 创建task
> 2. 调用sh_task_hook进行inline hook



```c
static void *shadowhook_hook_sym_name_impl(const char *lib_name, const char *sym_name, void *new_addr,
                                           void **orig_addr, shadowhook_hooked_t hooked, void *hooked_arg,
                                           uintptr_t caller_addr) {

  // create task
  sh_task_t *task =
      sh_task_create_by_sym_name(lib_name, sym_name, (uintptr_t)new_addr, (uintptr_t *)orig_addr, hooked,
                                 hooked_arg, (uintptr_t)caller_addr);
  if (NULL == task) GOTO_ERR(SHADOWHOOK_ERRNO_OOM);

  // do hook
  r = sh_task_hook(task);
  if (0 != r && SHADOWHOOK_ERRNO_PENDING != r) {
    sh_task_destroy(task);
    GOTO_ERR(r);
  }

  // OK
  SH_LOG_INFO("shadowhook: hook_sym_name(%s, %s, %p) OK. return: %p. %d - %s", lib_name, sym_name, new_addr,
              (void *)task, r, sh_errno_to_errmsg(r));
  SH_ERRNO_SET_RET(r, (void *)task);

err:
  SH_LOG_ERROR("shadowhook: hook_sym_name(%s, %s, %p) FAILED. %d - %s", lib_name, sym_name, new_addr, r,
               sh_errno_to_errmsg(r));
  SH_ERRNO_SET_RET_NULL(r);
}
```



> 创建task，对比上面两种基于addr的hook有如下改变
>
> 1. addr被换成了lb_name和sym_name
> 2. 添加了参数hooked、hook_args（shadowhook_hook_sym_name这里传入的都是是null）
>
> 对于结构体初始化来说，差别也就是初始化不同，之外也没啥好说的。代码如下。

```c
sh_task_t *task =
      sh_task_create_by_sym_name(lib_name, sym_name, (uintptr_t)new_addr, (uintptr_t *)orig_addr, hooked,
                                 hooked_arg, (uintptr_t)caller_addr);

sh_task_t *sh_task_create_by_sym_name(const char *lib_name, const char *sym_name, uintptr_t new_addr,
                                      uintptr_t *orig_addr, shadowhook_hooked_t hooked, void *hooked_arg,
                                      uintptr_t caller_addr) {
  sh_task_t *self = malloc(sizeof(sh_task_t));
  if (NULL == self) return NULL;

  if (NULL == (self->lib_name = strdup(lib_name))) goto err;
  if (NULL == (self->sym_name = strdup(sym_name))) goto err;
  self->target_addr = 0;
  self->new_addr = new_addr;
  self->orig_addr = orig_addr;
  self->hooked = hooked;
  self->hooked_arg = hooked_arg;
  self->caller_addr = caller_addr;
  self->finished = false;
  self->error = false;
  self->ignore_symbol_check = false;

  return self;

err:
  if (NULL != self->lib_name) free(self->lib_name);
  if (NULL != self->sym_name) free(self->sym_name);
  free(self);
  return NULL;
}
```





> sh_task_hook我们之前分析过这个代码。
>
> 为了减少冗余部分、遇上相似的代码这里就直接跳过了。着重分析于之前hook的差异的地方



> 从如下代码中可以发现、差别在于下面标记的if else分支，通过lib name和symbol name hook的方案走了单独的分支

```c
int sh_task_hook(sh_task_t *self) {
  
  if (0 == self->target_addr) { // 1. 通过lib name、symbol name进行hook
    is_hook_sym_addr = false;
    strlcpy(real_lib_name, self->lib_name, sizeof(real_lib_name));
    strlcpy(real_sym_name, self->sym_name, sizeof(real_sym_name));
    r = sh_linker_get_dlinfo_by_sym_name(self->lib_name, self->sym_name, &dlinfo, real_lib_name,
                                         sizeof(real_lib_name));
    if (SHADOWHOOK_ERRNO_PENDING == r) { 
      // we need to start monitor linker dlopen for handle the pending task
      if (0 != (r = sh_task_start_monitor(true))) goto end;
      r = SHADOWHOOK_ERRNO_PENDING;
      goto end;
    }
    if (0 != r) goto end;                             // error
    self->target_addr = (uintptr_t)dlinfo.dli_saddr;  // OK
  } else { // 2. 通过addr进行hook
    r = sh_linker_get_dlinfo_by_addr((void *)self->target_addr, &dlinfo, real_lib_name, sizeof(real_lib_name),
                                     real_sym_name, sizeof(real_sym_name), self->ignore_symbol_check);
    if (0 != r) goto end;  // error
  }

}
```



> 对分支的内容的单独分析一下
>
> 可以得出如下结论：
>
> 1. 由于hook_sym_name只有lib name和sym name所以hook逻辑和前两者hook不太一样，走了单独的分支。
>
> 2. hook_sym_name中有两种处理方式：立即hook & 延迟hook，依据是hook的so是否加载
>
>    1）对于已经加载到内存的so，通过dl寻找函数的绝对地址，得到地址以后复用直接addr hook的逻辑。
>
>    2）对于没有加载到内存的so，会通过延期的方式加载，等到so加载以后会自动触发后续的hook逻辑。

```c
 if (0 == self->target_addr) {
    // 设计标记
    is_hook_sym_addr = false;
    // 拷贝lib name && sym name
    strlcpy(real_lib_name, self->lib_name, sizeof(real_lib_name));
    strlcpy(real_sym_name, self->sym_name, sizeof(real_sym_name));
     // 通过lib name & symbol name寻找函数的绝对地址
    r = sh_linker_get_dlinfo_by_sym_name(self->lib_name, self->sym_name, &dlinfo, real_lib_name,
                                         sizeof(real_lib_name));
     
     // 返回结果为pending标记、则hook逻辑会在so加载之后再触发（当前分析内容不涉及这个逻辑）
    if (SHADOWHOOK_ERRNO_PENDING == r) { 
      // we need to start monitor linker dlopen for handle the pending task
      if (0 != (r = sh_task_start_monitor(true))) goto end;
      r = SHADOWHOOK_ERRNO_PENDING;
      goto end;
    }
     // 由于获取到了addr，后续处理流程复用shadowhook_hook_func_addr/shadowhook_hook_func_addr逻辑
    if (0 != r) goto end;                             // error
    self->target_addr = (uintptr_t)dlinfo.dli_saddr;  // OK
  }
```





### 获取addr



> 怎么通过lib name & sym name获取的addr呢？
>
> 1. 首先通过lib name调用xdl_open打开lib获取elf首个地址
> 2. 通过elf首地址和函数名称搜索函数绝对地址

```c
int sh_linker_get_dlinfo_by_sym_name(const char *lib_name, const char *sym_name, xdl_info_t *dlinfo,
                                     char *real_lib_name, size_t real_lib_name_sz) {
  // open library
  bool crashed = false;
  void *handle = NULL;
  if (sh_util_get_api_level() >= __ANDROID_API_L__) {
    handle = xdl_open(lib_name, XDL_DEFAULT);
  } else {
    SH_SIG_TRY(SIGSEGV, SIGBUS) {
      handle = xdl_open(lib_name, XDL_DEFAULT);
    }
    SH_SIG_CATCH() {
      crashed = true;
    }
    SH_SIG_EXIT
  }
  if (crashed) return SHADOWHOOK_ERRNO_HOOK_DLOPEN_CRASH;
  if (NULL == handle) return SHADOWHOOK_ERRNO_PENDING;

  // get dlinfo
  xdl_info(handle, XDL_DI_DLINFO, (void *)dlinfo);

  // check error
  if (!sh_linker_check_arch(dlinfo)) {
    xdl_close(handle);
    return SHADOWHOOK_ERRNO_ELF_ARCH_MISMATCH;
  }

  // lookup symbol address
  crashed = false;
  void *addr = NULL;
  size_t sym_size = 0;
  SH_SIG_TRY(SIGSEGV, SIGBUS) {
    // do xdl_sym() or xdl_dsym() in an dlclosed-ELF will cause a crash
    addr = xdl_sym(handle, sym_name, &sym_size);
    if (NULL == addr) addr = xdl_dsym(handle, sym_name, &sym_size);
  }
  SH_SIG_CATCH() {
    crashed = true;
  }
  SH_SIG_EXIT

  // close library
  // ......
  return 0;
}
```



> xdl_open
>
> 1.通过auxv系统调用获取（linker, vDSO，app_process）地址
>
> 2.通过dl_iterate_phdr便利vmmap表（当前进程的so列表）

```c
void *xdl_open(const char *filename, int flags) {
  if (NULL == filename) return NULL;

  if (flags & XDL_ALWAYS_FORCE_LOAD)
    return xdl_open_always_force(filename);
  else if (flags & XDL_TRY_FORCE_LOAD)
    return xdl_open_try_force(filename);
  else
    return xdl_find(filename);
}

static xdl_t *xdl_find(const char *filename) {
  // 使用auxv系统调用 获取 (linker, vDSO)地址
  xdl_t *self = NULL;
  if (xdl_util_ends_with(filename, XDL_UTIL_LINKER_BASENAME))
    self = xdl_find_from_auxv(AT_BASE, XDL_UTIL_LINKER_PATHNAME);
  else if (xdl_util_ends_with(filename, XDL_UTIL_VDSO_BASENAME))
    self = xdl_find_from_auxv(AT_SYSINFO_EHDR, XDL_UTIL_VDSO_BASENAME);

  // 使用auxv系统调用 获取 (app_process) 地址
  const char *basename, *pathname;
#if (defined(__arm__) || defined(__i386__)) && __ANDROID_API__ < __ANDROID_API_L__
  if (xdl_util_get_api_level() < __ANDROID_API_L__) {
    basename = XDL_UTIL_APP_PROCESS_BASENAME_K;
    pathname = XDL_UTIL_APP_PROCESS_PATHNAME_K;
  } else
#endif
  {
    basename = XDL_UTIL_APP_PROCESS_BASENAME;
    pathname = XDL_UTIL_APP_PROCESS_PATHNAME;
  }
  if (xdl_util_ends_with(filename, basename)) self = xdl_find_from_auxv(AT_PHDR, pathname);

  if (NULL != self) return self;

  // 使用 dl_iterate_phdr遍历所有的so，寻找name匹配的条目返回so首地址。
  uintptr_t pkg[2] = {(uintptr_t)&self, (uintptr_t)filename};
  xdl_iterate_phdr(xdl_find_iterate_cb, pkg, XDL_DEFAULT);
  return self;
}

// dl_iterate_phdr回调
static int xdl_find_iterate_cb(struct dl_phdr_info *info, size_t size, void *arg) {
  (void)size;

  uintptr_t *pkg = (uintptr_t *)arg;
  xdl_t **self = (xdl_t **)*pkg++;
  const char *filename = (const char *)*pkg;

  // check load_bias
  if (0 == info->dlpi_addr || NULL == info->dlpi_name) return 0;

  // 匹配pathname
  if ('[' == filename[0]) {
    if (0 != strcmp(info->dlpi_name, filename)) return 0;
  } else if ('/' == filename[0]) {
    if ('/' == info->dlpi_name[0]) {
      if (0 != strcmp(info->dlpi_name, filename)) return 0;
    } else {
      if (!xdl_util_ends_with(filename, info->dlpi_name)) return 0;
    }
  } else {
    if ('/' == info->dlpi_name[0]) {
      if (!xdl_util_ends_with(info->dlpi_name, filename)) return 0;
    } else {
      if (0 != strcmp(info->dlpi_name, filename)) return 0;
    }
  }

  // 写入dl_phdr_info
  if (NULL == ((*self) = calloc(1, sizeof(xdl_t)))) return 1;  // return failed
  if (NULL == ((*self)->pathname = strdup((const char *)info->dlpi_name))) {
    free(*self);
    *self = NULL;
    return 1;  // return failed
  }
  (*self)->load_bias = info->dlpi_addr;
  (*self)->dlpi_phdr = info->dlpi_phdr;
  (*self)->dlpi_phnum = info->dlpi_phnum;
  (*self)->dynsym_try_load = false;
  (*self)->symtab_try_load = false;
  return 1;  // return OK
}
```



> 通过sym寻找func addr

```c
void *xdl_sym(void *handle, const char *symbol, size_t *symbol_size) {
    // 参数检查
  if (NULL == handle || NULL == symbol) return NULL;
  if (NULL != symbol_size) *symbol_size = 0;

  xdl_t *self = (xdl_t *)handle;

    // 加载.dynsym
  if (!self->dynsym_try_load) {
    self->dynsym_try_load = true;
    if (0 != xdl_dynsym_load(self)) return NULL;
  }

  // 通过.gnu.hash -> .dynsym -> .dynstr、.hash -> .dynsym -> .dynstr的方式寻找符号表
  if (NULL == self->dynsym) return NULL;
  ElfW(Sym) *sym = NULL;
  if (self->gnu_hash.buckets_cnt > 0) {
    // use GNU hash (.gnu.hash -> .dynsym -> .dynstr), O(x) + O(1) + O(1)
    sym = xdl_dynsym_find_symbol_use_gnu_hash(self, symbol);
  }
  if (NULL == sym && self->sysv_hash.buckets_cnt > 0) {
    // use SYSV hash (.hash -> .dynsym -> .dynstr), O(x) + O(1) + O(1)
    sym = xdl_dynsym_find_symbol_use_sysv_hash(self, symbol);
  }
  if (NULL == sym || !XDL_DYNSYM_IS_EXPORT_SYM(sym->st_shndx)) return NULL;

  if (NULL != symbol_size) *symbol_size = sym->st_size;
    // 返回符号表对应函数的绝对地址
  return (void *)(self->load_bias + sym->st_value);
}

```



### pending hook



> pending hook的原因是so没有加载到内存中，即在xdl_open搜索so以后没有找到符合的地址。
>
> if (NULL == handle) return SHADOWHOOK_ERRNO_PENDING;

```c
int sh_linker_get_dlinfo_by_sym_name(const char *lib_name, const char *sym_name, xdl_info_t *dlinfo,
                                     char *real_lib_name, size_t real_lib_name_sz) {
  // open library
  bool crashed = false;
  void *handle = NULL;
  if (sh_util_get_api_level() >= __ANDROID_API_L__) {
    handle = xdl_open(lib_name, XDL_DEFAULT);
  } else {
    SH_SIG_TRY(SIGSEGV, SIGBUS) {
      handle = xdl_open(lib_name, XDL_DEFAULT);
    }
    SH_SIG_CATCH() {
      crashed = true;
    }
    SH_SIG_EXIT
  }
  if (crashed) return SHADOWHOOK_ERRNO_HOOK_DLOPEN_CRASH;
    // 如果没有找到so文件首地址
  if (NULL == handle) return SHADOWHOOK_ERRNO_PENDING;

  // get dlinfo

  // check error


  // lookup symbol address
  

  // close library
  // ......
  return 0;
}
```



> 继续分析
>
> 开启pending以后，首先会开启monitor

```c
if (0 == self->target_addr) {
    is_hook_sym_addr = false;
    strlcpy(real_lib_name, self->lib_name, sizeof(real_lib_name));
    strlcpy(real_sym_name, self->sym_name, sizeof(real_sym_name));
    r = sh_linker_get_dlinfo_by_sym_name(self->lib_name, self->sym_name, &dlinfo, real_lib_name,
                                         sizeof(real_lib_name));
    if (SHADOWHOOK_ERRNO_PENDING == r) {
      // we need to start monitor linker dlopen for handle the pending task
      if (0 != (r = sh_task_start_monitor(true))) goto end;
      r = SHADOWHOOK_ERRNO_PENDING;
      goto end;
    }
    if (0 != r) goto end;                             // error
    self->target_addr = (uintptr_t)dlinfo.dli_saddr;  // OK
  }
```





> task monitor
>
> 过程如下：
>
> 1. hook dlopen方法，并在每次每次dlopen调用的时候回写/notify eventfd
> 2. 创建eventfd，创建线程等待evenfd事件触发hook操作

```c
static int sh_task_start_monitor(bool start_thread) {
  static bool thread_started = false;
  static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
  pthread_t thread;
  int r;

  // hook linker dlopen()
  if (0 != (r = sh_linker_hook_dlopen(sh_task_post_dlopen_callback, NULL))) return r;

  if (!start_thread) return 0;

  // start thread
  if (thread_started) return thread_started_result;
  pthread_mutex_lock(&lock);
  if (thread_started) goto end;

  if (0 > (sh_task_eventfd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC))) goto end;
  if (0 != pthread_create(&thread, NULL, &sh_task_thread_func, NULL)) goto end;

  // OK
  thread_started_result = 0;

end:
  thread_started = true;
  pthread_mutex_unlock(&lock);
  SH_LOG_INFO("task: start monitor %s, return: %d", 0 == thread_started_result ? "OK" : "FAILED",
              thread_started_result);
  return thread_started_result;
}
```



> hook dlopen.
>
> hook后dlopen会被重定向到sh_linker_proxy_dlopen

```c
static void *sh_linker_proxy_dlopen(const char *filename, int flag) {
  void *handle;
  if (SHADOWHOOK_IS_SHARED_MODE)
    handle = SHADOWHOOK_CALL_PREV(sh_linker_proxy_dlopen, sh_linker_proxy_dlopen_t, filename, flag);
  else
    handle = sh_linker_orig_dlopen(filename, flag);

  if (NULL != handle) sh_linker_post_dlopen(sh_linker_post_dlopen_arg);

  if (SHADOWHOOK_IS_SHARED_MODE) SHADOWHOOK_POP_STACK();
  return handle;
}
```



> 其中
>
> `if (NULL != handle) sh_linker_post_dlopen(sh_linker_post_dlopen_arg);`
>
> 会触发eventfd的回写

```c
static void sh_task_post_dlopen_callback(void *arg) {
  (void)arg;

  if (0 == thread_started_result && __atomic_load_n(&sh_tasks_unfinished_cnt, __ATOMIC_SEQ_CST) > 0) {
    uint64_t ev_val = 1;
    SH_UTIL_TEMP_FAILURE_RETRY(write(sh_task_eventfd, &ev_val, sizeof(ev_val)));
  }
}
```





> 新线程

```c
 if (0 > (sh_task_eventfd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC))) goto end;
 if (0 != pthread_create(&thread, NULL, &sh_task_thread_func, NULL)) goto end;

```



> 会死循环poll事件，当有dlopen调用后会被唤醒。之后会进行如下操作
>
> 1. 调用xdl_iterate_phdr遍历所有vmmaps
>
> 2. 执行hook

```c
__noreturn static void *sh_task_thread_func(void *arg) {
  (void)arg;
  pthread_t thread = pthread_self();
  pthread_setname_np(thread, SH_TASK_THREAD_NAME);
  pthread_detach(thread);

  struct pollfd ev = {.fd = sh_task_eventfd, .events = POLLIN, .revents = 0};
  while (1) {
    int n = SH_UTIL_TEMP_FAILURE_RETRY(poll(&ev, 1, -1));
    if (n < 0) {
      sleep(1);
      continue;
    } else if (n > 0) {
      uint64_t ev_val;
      SH_UTIL_TEMP_FAILURE_RETRY(read(sh_task_eventfd, &ev_val, sizeof(ev_val)));

      if (sh_util_get_api_level() >= __ANDROID_API_L__) {
        xdl_iterate_phdr(sh_task_hook_pending, NULL, XDL_DEFAULT);
      } else {
        SH_SIG_TRY(SIGSEGV, SIGBUS) {
          xdl_iterate_phdr(sh_task_hook_pending, NULL, XDL_DEFAULT);
        }
        SH_SIG_CATCH() {
          SH_LOG_WARN("task: dliterate crashed");
        }
        SH_SIG_EXIT
      }
    }
  }
}
```



> 对每一条vmmaps记录进行处理。

```c
static int sh_task_hook_pending(struct dl_phdr_info *info, size_t size, void *arg) {
  (void)size, (void)arg;

  pthread_rwlock_rdlock(&sh_tasks_lock);

  sh_task_t *task;
    // 遍历每一个task，对未完成的task进行hook。
  TAILQ_FOREACH(task, &sh_tasks, link) {
    if (task->finished) continue;
    if ('/' == info->dlpi_name[0] && NULL == strstr(info->dlpi_name, task->lib_name)) continue;
    if ('/' != info->dlpi_name[0] && NULL == strstr(task->lib_name, info->dlpi_name)) continue;

    xdl_info_t dlinfo;
    char real_lib_name[512];
    int r = sh_linker_get_dlinfo_by_sym_name(task->lib_name, task->sym_name, &dlinfo, real_lib_name,
                                             sizeof(real_lib_name));
    task->target_addr = (uintptr_t)dlinfo.dli_saddr;
    if (SHADOWHOOK_ERRNO_PENDING != r) {
      size_t backup_len = 0;
      if (0 == r) {
        r = sh_switch_hook(task->target_addr, task->new_addr, task->orig_addr, &backup_len, &dlinfo);
        if (0 != r) task->error = true;
      } else {
        strlcpy(real_lib_name, task->lib_name, sizeof(real_lib_name));
        task->error = true;
      }
      sh_recorder_add_hook(r, false, task->target_addr, real_lib_name, task->sym_name, task->new_addr,
                           backup_len, (uintptr_t)task, task->caller_addr);
      task->finished = true;
      sh_task_do_callback(task, r);
      if (0 == __atomic_sub_fetch(&sh_tasks_unfinished_cnt, 1, __ATOMIC_SEQ_CST)) break;
    }
  }

  pthread_rwlock_unlock(&sh_tasks_lock);

  return __atomic_load_n(&sh_tasks_unfinished_cnt, __ATOMIC_SEQ_CST) > 0 ? 0 : 1;
}
```





## shadowhook_hook_sym_name_callback

> sym_name_callback类似于之前sym_name的回调。
>
> 不一样的是多了callback回调，也就是多了两个传入的参数。其他没啥差别。



> sym_name_callback与sym_name的差别是：hooked_arg和hooked的差别。

```c
void *shadowhook_hook_sym_name_callback(const char *lib_name, const char *sym_name, void *new_addr,
                                        void **orig_addr, shadowhook_hooked_t hooked, void *hooked_arg) {
  const void *caller_addr = __builtin_return_address(0);
  return shadowhook_hook_sym_name_impl(lib_name, sym_name, new_addr, orig_addr, hooked, hooked_arg,
                                       (uintptr_t)caller_addr);
}
```



> 多传入的参数会在初始化task的时候传入。存在`sh_task_t`结构体中

```c
sh_task_t *sh_task_create_by_sym_name(const char *lib_name, const char *sym_name, uintptr_t new_addr,
                                      uintptr_t *orig_addr, shadowhook_hooked_t hooked, void *hooked_arg,
                                      uintptr_t caller_addr) {
  sh_task_t *self = malloc(sizeof(sh_task_t));
  if (NULL == self) return NULL;

  if (NULL == (self->lib_name = strdup(lib_name))) goto err;
  if (NULL == (self->sym_name = strdup(sym_name))) goto err;
  self->target_addr = 0;
  self->new_addr = new_addr;
  self->orig_addr = orig_addr;
  self->hooked = hooked;
  self->hooked_arg = hooked_arg;
  self->caller_addr = caller_addr;
  self->finished = false;
  self->error = false;
  self->ignore_symbol_check = false;

  return self;

err:
  if (NULL != self->lib_name) free(self->lib_name);
  if (NULL != self->sym_name) free(self->sym_name);
  free(self);
  return NULL;
}
```



> 在hook pending函数调用中，hook后通过调用sh_task_do_callback调用hooked回调。

```c
static int sh_task_hook_pending(struct dl_phdr_info *info, size_t size, void *arg) {
  (void)size, (void)arg;

// .......
  sh_task_t *task;
  TAILQ_FOREACH(task, &sh_tasks, link) {
   // .......
    task->target_addr = (uintptr_t)dlinfo.dli_saddr;
    if (SHADOWHOOK_ERRNO_PENDING != r) {
      size_t backup_len = 0;
      if (0 == r) {
        r = sh_switch_hook(task->target_addr, task->new_addr, task->orig_addr, &backup_len, &dlinfo);
        if (0 != r) task->error = true;
      } else {
        strlcpy(real_lib_name, task->lib_name, sizeof(real_lib_name));
        task->error = true;
      }
      sh_recorder_add_hook(r, false, task->target_addr, real_lib_name, task->sym_name, task->new_addr,
                           backup_len, (uintptr_t)task, task->caller_addr);
      task->finished = true;
        // 回调hooked callback
      sh_task_do_callback(task, r);
      if (0 == __atomic_sub_fetch(&sh_tasks_unfinished_cnt, 1, __ATOMIC_SEQ_CST)) break;
    }
  }

  return __atomic_load_n(&sh_tasks_unfinished_cnt, __ATOMIC_SEQ_CST) > 0 ? 0 : 1;
}


static void sh_task_do_callback(sh_task_t *self, int error_number) {
  if (NULL != self->hooked)
    self->hooked(error_number, self->lib_name, self->sym_name, (void *)self->target_addr,
                 (void *)self->new_addr, self->orig_addr, self->hooked_arg);
}

```



# Unhook



> 函数原型

```c
int shadowhook_unhook(void *stub);

int shadowhook_unhook(void *stub) {
  const void *caller_addr = __builtin_return_address(0);
  SH_LOG_INFO("shadowhook: unhook(%p) ...", stub);
  sh_errno_reset();

  // 参数检查 
  int r;
  if (NULL == stub) GOTO_ERR(SHADOWHOOK_ERRNO_INVALID_ARG);
  if (SHADOWHOOK_ERRNO_OK != shadowhook_init_errno) GOTO_ERR(shadowhook_init_errno);
    
  sh_task_t *task = (sh_task_t *)stub;
  r = sh_task_unhook(task, (uintptr_t)caller_addr); // 取消hook
  sh_task_destroy(task); // 摧毁结构体
  if (0 != r) GOTO_ERR(r);

  // OK
  SH_LOG_INFO("shadowhook: unhook(%p) OK", stub);
  SH_ERRNO_SET_RET_ERRNUM(SHADOWHOOK_ERRNO_OK);

err:
  SH_LOG_ERROR("shadowhook: unhook(%p) FAILED. %d - %s", stub, r, sh_errno_to_errmsg(r));
  SH_ERRNO_SET_RET_FAIL(r);
}
```



> 实际的unhook逻辑

```c
int sh_task_unhook(sh_task_t *self, uintptr_t caller_addr) {
  pthread_rwlock_wrlock(&sh_tasks_lock);
  TAILQ_REMOVE(&sh_tasks, self, link);
  if (!self->finished) __atomic_sub_fetch(&sh_tasks_unfinished_cnt, 1, __ATOMIC_SEQ_CST);
  pthread_rwlock_unlock(&sh_tasks_lock);

  // check task status
  int r;
  if (self->error) {
    r = SHADOWHOOK_ERRNO_UNHOOK_ON_ERROR;
    goto end;
  }
  if (!self->finished) {
    r = SHADOWHOOK_ERRNO_UNHOOK_ON_UNFINISHED;
    goto end;
  }

  // do unhook
  r = sh_switch_unhook(self->target_addr, self->new_addr);

end:
  // record
  sh_recorder_add_unhook(r, (uintptr_t)self, caller_addr);
  return r;
}

int sh_switch_unhook(uintptr_t target_addr, uintptr_t new_addr) {
  int r;
  if (SHADOWHOOK_IS_UNIQUE_MODE) {
    r = sh_switch_unhook_unique(target_addr);
    if (0 == r) SH_LOG_INFO("switch: unhook in UNIQUE mode OK: target_addr %" PRIxPTR, target_addr);
  } else {
    r = sh_switch_unhook_shared(target_addr, new_addr);
    if (0 == r)
      SH_LOG_INFO("switch: unhook in SHARED mode OK: target_addr %" PRIxPTR ", new_addr %" PRIxPTR,
                  target_addr, new_addr);
  }

  return r;
}
```





> unique mode & shared mode有一定的差别，但是无非就是如下几步
>
> 1. 删除数据结构
> 2. 将inline hook改变的函数地址恢复原状

```c

static int sh_switch_unhook_unique(uintptr_t target_addr) {
  int r;
  sh_switch_t *useless = NULL;

  pthread_rwlock_wrlock(&sh_switches_lock);  // SYNC - start

  sh_switch_t key = {.target_addr = target_addr};
  sh_switch_t *self = RB_FIND(sh_switch_tree, &sh_switches, &key);
  if (NULL == self) {
    r = SHADOWHOOK_ERRNO_UNHOOK_NOTFOUND;
    goto end;
  }
  r = sh_inst_unhook(&self->inst, target_addr);
  RB_REMOVE(sh_switch_tree, &sh_switches, self);
  useless = self;

end:
  pthread_rwlock_unlock(&sh_switches_lock);  // SYNC - end
  if (NULL != useless) sh_switch_destroy(useless, false);
  return r;
}

static int sh_switch_unhook_shared(uintptr_t target_addr, uintptr_t new_addr) {
  int r;
  sh_switch_t *useless = NULL;

  pthread_rwlock_wrlock(&sh_switches_lock);  // SYNC - start

  sh_switch_t key = {.target_addr = target_addr};
  sh_switch_t *self = RB_FIND(sh_switch_tree, &sh_switches, &key);
  if (NULL == self) {
    r = SHADOWHOOK_ERRNO_UNHOOK_NOTFOUND;
    goto end;
  }

  // delete proxy in hub
  bool have_enabled_proxy;
  if (0 != sh_hub_del_proxy(self->hub, new_addr, &have_enabled_proxy)) {
    r = SHADOWHOOK_ERRNO_UNHOOK_NOTFOUND;
    goto end;
  }
  r = 0;

  // unhook inst, remove current switch from switch-tree
  if (!have_enabled_proxy) {
    r = sh_inst_unhook(&self->inst, target_addr);

    uintptr_t *safe_orig_addr_addr = sh_safe_get_orig_addr_addr(target_addr);
    if (NULL != safe_orig_addr_addr) __atomic_store_n(safe_orig_addr_addr, 0, __ATOMIC_SEQ_CST);

    RB_REMOVE(sh_switch_tree, &sh_switches, self);
    useless = self;
  }

end:
  pthread_rwlock_unlock(&sh_switches_lock);  // SYNC - end
  if (NULL != useless) sh_switch_destroy(useless, true);
  return r;
}

```



# 宏





> 即宏定义



## SHADOWHOOK_CALL_PREV



> 宏定义
>
> （实际是方法的调用）

```c
#ifdef __cplusplus
#define SHADOWHOOK_CALL_PREV(func, ...) \
  ((decltype(&(func)))shadowhook_get_prev_func((void *)(func)))(__VA_ARGS__)
#else
#define SHADOWHOOK_CALL_PREV(func, func_sig, ...) \
  ((func_sig)shadowhook_get_prev_func((void *)(func)))(__VA_ARGS__)
#endif
```



> 函数原型

```c
void *shadowhook_get_prev_func(void *func);
```



> 实现

```c
void *shadowhook_get_prev_func(void *func) {
    // 只适用于shared mode
  if (__predict_false(SHADOWHOOK_IS_UNIQUE_MODE)) abort();
  return sh_hub_get_prev_func(func);
}


void *sh_hub_get_prev_func(void *func) {
    // 通过thread local获取栈帧
  sh_hub_stack_t *stack = (sh_hub_stack_t *)sh_safe_pthread_getspecific(sh_hub_stack_tls_key);
  if (0 == stack->frames_cnt) sh_safe_abort();  // called in a non-hook status?
  sh_hub_frame_t *frame = &stack->frames[stack->frames_cnt - 1];

  // 从proxies中寻找下一个可以调用的函数地址
  bool found = false;
  sh_hub_proxy_t *proxy;
  SLIST_FOREACH(proxy, &(frame->proxies), link) {
    if (!found) {
      if (proxy->func == func) found = true;
    } else {
      if (proxy->enabled) break;
    }
  }
  if (NULL != proxy) {
    SH_LOG_DEBUG("hub: get_prev_func() return next enabled proxy %p", proxy->func);
    return proxy->func;
  }

  SH_LOG_DEBUG("hub: get_prev_func() return orig_addr %p", (void *)frame->orig_addr);
  // did not find, return the original-function
  return (void *)frame->orig_addr;
}
```



## SHADOWHOOK_POP_STACK

> 宏定义。
>
> SHADOWHOOK_IS_SHARED_MODE说明了当前宏定义只适用于，shared mode

```c
#define SHADOWHOOK_POP_STACK()                                                        \
  do {                                                                                \
    if (SHADOWHOOK_IS_SHARED_MODE) shadowhook_pop_stack(__builtin_return_address(0)); \
  } while (0)
```



> 宏定义最后调用的是如下方法

```c
void shadowhook_pop_stack(void *return_address) {
  if (__predict_false(SHADOWHOOK_IS_UNIQUE_MODE)) abort();
  sh_hub_pop_stack(return_address);
}
```



> 实现原理很轻松，其实就是把thread local中的调用栈。
>
> 减去一层，前提是frame->return_address == return_address。
>
> 即当前frame的最后一个函数调用完成了。

```c
void sh_hub_pop_stack(void *return_address) {
  sh_hub_stack_t *stack = (sh_hub_stack_t *)sh_safe_pthread_getspecific(sh_hub_stack_tls_key);
  if (0 == stack->frames_cnt) return;
  sh_hub_frame_t *frame = &stack->frames[stack->frames_cnt - 1];

  // only the first proxy will actually execute pop-stack()
  if (frame->return_address == return_address) {
    stack->frames_cnt--;
    SH_LOG_DEBUG("hub: frames_cnt-- = %zu", stack->frames_cnt);
  }
}
```



## SHADOWHOOK_STACK_SCOPE



> pop stack是用于C++代理函数的一个方法，功能与SHADOWHOOK_POP_STACK完全一致。
>
> 唯一的区别就是——**只能用于C++**

```c
// pop stack in proxy-function (for C++ only)
#ifdef __cplusplus
class ShadowhookStackScope {
 public:
  ShadowhookStackScope(void *return_address) : return_address_(return_address) {}
  ~ShadowhookStackScope() {
    if (SHADOWHOOK_IS_SHARED_MODE) shadowhook_pop_stack(return_address_);
  }

 private:
  void *return_address_;
};
#define SHADOWHOOK_STACK_SCOPE() ShadowhookStackScope shadowhook_stack_scope_obj(__builtin_return_address(0))
#endif
```



> 其实现原理不难，就是利用了C++的析构函数。
>
> 宏定义创建了一个栈变量，在函数结束的时候栈变量被摧毁。
>
> 自动调用析构函数，析构函数调用了pop_stack减去了，shadow hook自己维护的栈帧。

```c++
ShadowhookStackScope shadowhook_stack_scope_obj(__builtin_return_address(0));

~ShadowhookStackScope() {
    if (SHADOWHOOK_IS_SHARED_MODE) shadowhook_pop_stack(return_address_);
}
```



## SHADOWHOOK_ALLOW_REENTRANT



> 用于运行proxy 函数的重入

```c
// allow reentrant of the current proxy-function
#define SHADOWHOOK_ALLOW_REENTRANT()                                                        \
  do {                                                                                      \
    if (SHADOWHOOK_IS_SHARED_MODE) shadowhook_allow_reentrant(__builtin_return_address(0)); \
  } while (0)
```



> 具体逻辑。
>
> 只是修改了当前的frame的一个参数。
>
> frame->flags |= SH_HUB_FRAME_FLAG_ALLOW_REENTRANT

```c
void shadowhook_allow_reentrant(void *return_address) {
  if (__predict_false(SHADOWHOOK_IS_UNIQUE_MODE)) abort();
  sh_hub_allow_reentrant(return_address);
}

void sh_hub_allow_reentrant(void *return_address) {
  sh_hub_frame_t *frame = sh_hub_get_current_frame(return_address);
  if (NULL != frame) {
    frame->flags |= SH_HUB_FRAME_FLAG_ALLOW_REENTRANT;
    SH_LOG_DEBUG("hub: allow reentrant frame %p", return_address);
  }
}
```



> 这个参数会在`sh_hub_push_stack`时检查递归的过程中使用。

```c
static void *sh_hub_push_stack(sh_hub_t *self, void *return_address) {
    
  // check whether a recursive call occurred
  bool recursive = false;
  for (size_t i = stack->frames_cnt; i > 0; i--) {
    sh_hub_frame_t *frame = &stack->frames[i - 1];
    // 如果不允许重入，并且出现了重复的栈帧，判定为递归，结束循环。
    if (0 == (frame->flags & SH_HUB_FRAME_FLAG_ALLOW_REENTRANT) && (frame->orig_addr == self->orig_addr)) {
      // recursive call found
      recursive = true;
      break;
    }
  }
    
}
```



## SHADOWHOOK_DISALLOW_REENTRANT



> 宏定义

```c
#define SHADOWHOOK_DISALLOW_REENTRANT()                                                        \
  do {                                                                                         \
    if (SHADOWHOOK_IS_SHARED_MODE) shadowhook_disallow_reentrant(__builtin_return_address(0)); \
  } while (0)
```



> 同之前的allow，只是设置了相反的参数。

```c
void shadowhook_disallow_reentrant(void *return_address) {
  if (__predict_false(SHADOWHOOK_IS_UNIQUE_MODE)) abort();
  sh_hub_disallow_reentrant(return_address);
}

void sh_hub_disallow_reentrant(void *return_address) {
  sh_hub_frame_t *frame = sh_hub_get_current_frame(return_address);
  if (NULL != frame) {
    frame->flags &= ~SH_HUB_FRAME_FLAG_ALLOW_REENTRANT;
    SH_LOG_DEBUG("hub: disallow reentrant frame %p", return_address);
  }
}
```






## SHADOWHOOK_RETURN_ADDRESS



> 宏定义
>
> 依旧是对shared mode做的处理。

```c
// get return address in proxy-function
#define SHADOWHOOK_RETURN_ADDRESS() \
  ((void *)(SHADOWHOOK_IS_SHARED_MODE ? shadowhook_get_return_address() : __builtin_return_address(0)))
```



> 具体的逻辑

```c
void *shadowhook_get_return_address(void) {
  if (__predict_false(SHADOWHOOK_IS_UNIQUE_MODE)) abort();
  return sh_hub_get_return_address();
}

// 获取hook前函数的调用返回位置。排除多个proxies对__builtin_return_address的影响。
void *sh_hub_get_return_address(void) {
  sh_hub_stack_t *stack = (sh_hub_stack_t *)sh_safe_pthread_getspecific(sh_hub_stack_tls_key);
  if (0 == stack->frames_cnt) sh_safe_abort();  // called in a non-hook status?
  sh_hub_frame_t *frame = &stack->frames[stack->frames_cnt - 1];

  return frame->return_address;
}
```





