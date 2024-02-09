---
title: bhook-principal
tags:
- bhook
cover:
---



# BHook原理解析



# 初始化



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



```c
int bh_linker_init(void) {
  bh_linker_g_dl_mutex_compatible = bh_linker_check_lock_compatible();
  int api_level = bh_util_get_api_level();

  // for Android 4.x
#if __ANDROID_API__ < __ANDROID_API_L__
  if (api_level < __ANDROID_API_L__) return bh_linker_init_android_4x();
#endif

  if (!bh_linker_g_dl_mutex_compatible) {
    // If the mutex ABI is not compatible, then we need to use an alternative.
    if (0 != pthread_key_create(&bh_linker_g_dl_mutex_key, NULL)) return -1;
  }

  void *linker = bh_dl_open_linker();
  if (NULL == linker) goto err;

  // for Android 5.0, 5.1, 7.0, 7.1 and all mutex ABI compatible cases
  if (__ANDROID_API_L__ == api_level || __ANDROID_API_L_MR1__ == api_level ||
      __ANDROID_API_N__ == api_level || __ANDROID_API_N_MR1__ == api_level ||
      bh_linker_g_dl_mutex_compatible) {
    bh_linker_g_dl_mutex = (pthread_mutex_t *)(bh_dl_dsym(linker, BH_CONST_SYM_G_DL_MUTEX));
    if (NULL == bh_linker_g_dl_mutex && api_level >= __ANDROID_API_U__)
      bh_linker_g_dl_mutex = (pthread_mutex_t *)(bh_dl_dsym(linker, BH_CONST_SYM_G_DL_MUTEX_U_QPR2));
    if (NULL == bh_linker_g_dl_mutex) goto err;
  }

  // for Android 7.0, 7.1
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
  if (NULL != linker) bh_dl_close(linker);
  bh_linker_do_dlopen = NULL;
  bh_linker_dlopen_ext = NULL;
  bh_linker_g_dl_mutex = NULL;
  bh_linker_get_error_buffer = NULL;
  bh_linker_bionic_format_dlerror = NULL;
  return -1;
}
```











