---
title: Shadowhook基础使用
tags:
  - c
  - inline hook
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/test.png'
date: 2024-03-27 20:44:18
---




# ShadowHook



> 什么是ShadowHook
>
> 请看[官网](https://github.com/bytedance/android-inline-hook)



> **ShadowHook** 是一个 Android inline hook 库，它支持 thumb、arm32 和 arm64。



# 基础概念



## inline-hook



> Inline-hook 通过直接修改目标函数的机器指令来实现。通常情况下，会将目标函数的开头几条指令替换为跳转指令，指向一段插入的代码。这段插入的代码可以执行额外的操作，例如记录函数参数、修改函数返回值，或者完全改变函数的执行逻辑。
>
> ——from Gemini（快说：谢谢Gemini）



> Android 的Native Hook技术有两类，PLT Hook & Inline Hook
>
> PLT Hook用于有外部的依赖库调用的Hook。
>
> Inline Hook用于Hook内部库的调用



>  如下是是PLT Hook和Inline Hook的使用场景以及区别

Plt Hook

![plt-hook.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/plt-hook.drawio.png)

Inline Hook

![inline-hook.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/inline-hook.drawio.png)





## shadow hook



> Shadow hook是一个Inline Hook框架。



# Shadow Hook基础使用





## Quick Start



> Note: 具体可见[官方文档](https://github.com/bytedance/android-inline-hook/blob/main/README.zh-CN.md#%E5%BF%AB%E9%80%9F%E5%BC%80%E5%A7%8B)



1. 添加build.gradle依赖

   ```groovy
   android {
       buildFeatures {
           prefab true
       }
   }
   
   dependencies {
       implementation 'com.bytedance.android:shadowhook:1.0.9'
   }
   
   ```

   

2. 添加C++依赖

    ```cmake
    find_package(shadowhook REQUIRED CONFIG)
    
    add_library(mylib SHARED mylib.c)
    target_link_libraries(mylib shadowhook::shadowhook)
    
    ```

3. 初始化

   ```java
   import com.bytedance.shadowhook.ShadowHook;
   
   public class MySdk {
       public static void init() {
           ShadowHook.init(new ShadowHook.ConfigBuilder()
               .setMode(ShadowHook.Mode.UNIQUE)
               .build());
       }
   }
   ```

4. hook & unhook

- `shadowhook_hook_func_addr`: 通过绝对地址 hook 一个在 ELF 中没有符号信息的函数。
- `shadowhook_hook_sym_addr`：通过绝对地址 hook 一个在 ELF 中有符号信息的函数。
- `shadowhook_hook_sym_name`：通过符号名和 ELF 的文件名或路径名 hook 一个函数。
- `shadowhook_hook_sym_name_callback`：和 `shadowhook_hook_sym_name` 类似，但是会在 hook 完成后调用指定的回调函数。
- `shadowhook_unhook`：unhook。



## 初始化



- **可以在 java 层或 native 层初始化，二选一即可。**
- java 层初始化逻辑实际上只做了两件事：`System.loadLibrary`、调用 native 层的 `init` 函数。
- 可以并发的多次的执行初始化，但只有第一次实际生效，后续的初始化调用将直接返回第一次初始化的返回值。



Mode

- `shared` 模式（默认值）：可对同一个 hook 点并发执行多个 hook 和 unhook，彼此互不干扰。自动避免代理函数之间可能形成的递归调用和环形调用。建议复杂的机构或组织使用 shared 模式。
- `unique` 模式：同一个 hook 点只能被 hook 一次（unhook 后可以再次 hook）。需要自己处理代理函数之间可能形成的递归调用和环形调用。个人或小型的 app，或某些调试场景中（例如希望跳过 ShadowHook 的 proxy 管理机制，调试分析比较单纯的 inlinehook 流程），可以使用该模式。



示例代码

Java

```java
import com.bytedance.shadowhook.ShadowHook;

public class MySdk {
    public static void init() {
        ShadowHook.init(new ShadowHook.ConfigBuilder()
            .setMode(ShadowHook.Mode.SHARED)
            .setDebuggable(true)
            .setRecordable(true)
            .build());
    }
}
```

Native

```c++
#include "shadowhook.h"

typedef enum
{
    SHADOWHOOK_MODE_SHARED = 0,
    SHADOWHOOK_MODE_UNIQUE = 1
} shadowhook_mode_t;

int shadowhook_init(shadowhook_mode_t mode, bool debuggable);
```





## 工具方法



```c
#include "shadowhook.h"

void *shadowhook_dlopen(const char *lib_name);
void shadowhook_dlclose(void *handle);
void *shadowhook_dlsym(void *handle, const char *sym_name);
void *shadowhook_dlsym_dynsym(void *handle, const char *sym_name);
void *shadowhook_dlsym_symtab(void *handle, const char *sym_name);
```



这组 API 的用法类似于系统提供的 `dlopen`，`dlclose`，`dlsym`。

- `shadowhook_dlsym_dynsym` 只能查找 `.dynsym` 中的符号，速度较快。
- `shadowhook_dlsym_symtab` 能查找 `.symtab` 和 `.symtab in .gnu_debugdata` 中的符号，但是速度较慢。
- `shadowhook_dlsym` 会先尝试在 `.dynsym` 中查找符号，如果找不到，会继续尝试在 `.symtab` 和 `.symtab in .gnu_debugdata` 中查找。



## Hook



### 通过“符号地址“Hook

```c
#include "shadowhook.h"

void *shadowhook_hook_sym_addr(void *sym_addr, void *new_addr, void **orig_addr);
```



> 这种方式只能 hook “当前已加载到进程中的动态库”。



- 参数

1. `sym_addr`（必须指定）：需要被 hook 的函数的绝对地址。

2. `new_addr`（必须指定）：新函数（proxy 函数）的绝对地址。

3. `orig_addr`（不需要的话可传 `NULL`）：返回原函数地址。

- 返回值

1. 非 `NULL`：hook 成功。返回值是个 stub，可保存返回值，后续用于 unhook。

2. `NULL`：hook 失败。可调用 `shadowhook_get_errno` 获取 errno，可继续调用 `shadowhook_to_errmsg` 获取 error message。

- 举例

```c
void *orig;
void *stub = shadowhook_hook_sym_addr(malloc, my_malloc, &orig);
if(stub == NULL)
{
    int error_num = shadowhook_get_errno();
    const char *error_msg = shadowhook_to_errmsg(error_num);
    __android_log_print(ANDROID_LOG_WARN,  "test", "hook failed: %d - %s", error_num, error_msg);
}
```







### 通过“函数地址“Hook



```c
#include "shadowhook.h"

void *shadowhook_hook_func_addr(void *func_addr, void *new_addr, void **orig_addr);

```

> 这种方式只能 hook “当前已加载到进程中的动态库”。



- 参数

1. `func_addr`（必须指定）：需要被 hook 的函数的绝对地址。

2. `new_addr`（必须指定）：新函数（proxy 函数）的绝对地址。

3. `orig_addr`（不需要的话可传 `NULL`）：返回原函数地址。

- 返回值

1. 非 `NULL`：hook 成功。返回值是个 stub，可保存返回值，后续用于 unhook。

2. `NULL`：hook 失败。可调用 `shadowhook_get_errno` 获取 errno，可继续调用 `shadowhook_to_errmsg` 获取 error message。

- 示例

```c
void *orig;
void *func = get_hidden_func_addr();
void *stub = shadowhook_hook_func_addr(func, my_func, &orig);
if(stub == NULL)
{
    int error_num = shadowhook_get_errno();
    const char *error_msg = shadowhook_to_errmsg(error_num);
    __android_log_print(ANDROID_LOG_WARN,  "test", "hook failed: %d - %s", error_num, error_msg);
}
```



### 通过“库名+函数名”Hook



```c
#include "shadowhook.h"

void *shadowhook_hook_sym_name(const char *lib_name, const char *sym_name, void *new_addr, void **orig_addr);
```

> 这种方式可以 hook “当前已加载到进程中的动态库”，也可以 hook “还没有加载到进程中的动态库”（如果 hook 时动态库还未加载，ShadowHook 内部会记录当前的 hook “诉求”，后续一旦目标动态库被加载到内存中，将立刻执行 hook 操作）。



- 参数

1. `lib_name`（必须指定）：符号所在 ELF 的 basename 或 pathname。对于在进程中确认唯一的动态库，可以只传 basename，例如：`libart.so`。对于不唯一的动态库，需要根据安卓版本和 arch 自己处理兼容性，例如：`/system/lib64/libbinderthreadstate.so` 和 `/system/lib64/vndk-sp-29/libbinderthreadstate.so`。否则，ShadowHook 只会 hook 进程中第一个匹配到 basename 的动态库。

2. `sym_name`（必须指定）：符号名。

3. `new_addr`（必须指定）：新函数（proxy 函数）的绝对地址。

4. `orig_addr`（不需要的话可传 `NULL`）：返回原函数地址。

- 返回值

1. 非 `NULL`（errno == 0）：hook 成功。返回值是个 stub，可保存返回值，后续用于 unhook。

2. 非 `NULL`（errno == 1）：由于目标动态库还没有加载，导致 hook 无法执行。ShadowHook 内部会记录当前的 hook “诉求”，后续一旦目标动态库被加载到内存中，将立刻执行 hook 操作。返回值是个 stub，可保存返回值，后续用于 unhook。

3. `NULL`：hook 失败。可调用 `shadowhook_get_errno` 获取 errno，可继续调用 `shadowhook_to_errmsg` 获取 error message。

- 示例

```c
void *orig;
void *stub = shadowhook_hook_sym_name("libart.so", "_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc", my_invoke, &orig);

int error_num = shadowhook_get_errno();
const char *error_msg = shadowhook_to_errmsg(error_num);
__android_log_print(ANDROID_LOG_WARN,  "test", "hook return: %p, %d - %s", stub, error_num, error_msg);
```



### 通过“库名+函数名“Hook（包含回调）



```c
#include "shadowhook.h"

typedef void (*shadowhook_hooked_t)(int error_number, const char *lib_name, const char *sym_name, void *sym_addr, void *new_addr, void *orig_addr, void *arg);

void *shadowhook_hook_sym_name_callback(const char *lib_name, const char *sym_name, void *new_addr, void **orig_addr, shadowhook_hooked_t hooked, void *hooked_arg);
```



> 除回调外一致与“库名+函数名”一致。

- 示例

```c
typedef void my_hooked_callback(int error_number, const char *lib_name, const char *sym_name, void *sym_addr, void *new_addr, void *orig_addr, void *arg);
{
    const char *error_msg = shadowhook_to_errmsg(error_number);
    __android_log_print(ANDROID_LOG_WARN,  "test", "hooked: %s, %s, %d - %s", lib_name, sym_name, error_number, error_msg);
}

void do_hook(void)
{
    void *orig;
    void *stub = shadowhook_hook_sym_name_callback("libart.so", "_ZN3art9ArtMethod6InvokeEPNS_6ThreadEPjjPNS_6JValueEPKc", my_invoke, &orig, my_hooked_callback, NULL);

    int error_num = shadowhook_get_errno();
    const char *error_msg = shadowhook_to_errmsg(error_num);
    __android_log_print(ANDROID_LOG_WARN,  "test", "hook return: %p, %d - %s", stub, error_num, error_msg);
}
```



### unhook

```c
#include "shadowhook.h"

int shadowhook_unhook(void *stub);
```



- 参数

`stub`（必须指定）：hook 函数返回的 stub 值。

- 返回值

1. `0`：unhook 成功。

2. `-1`：unhook 失败。可调用 `shadowhook_get_errno` 获取 errno，可继续调用 `shadowhook_to_errmsg` 获取 error message。

- 示例

```c
int result = shadowhook_unhook(stub);
if(result != 0)
{
    int error_num = shadowhook_get_errno();
    const char *error_msg = shadowhook_to_errmsg(error_num);
    __android_log_print(ANDROID_LOG_WARN,  "test", "unhook failed: %d - %s", error_num, error_msg);
}
```



### 代理函数





#### shared



- `SHADOWHOOK_CALL_PREV` 

  用于在代理函数内部调用原函数

- `SHADOWHOOK_POP_STACK`  & `SHADOWHOOK_STACK_SCOPE`

  代理函数中做一些额外的事情，即“执行 ShadowHook 内部的 stack 清理”，这需要你在 proxy 函数中调用 `SHADOWHOOK_POP_STACK` 宏或 `SHADOWHOOK_STACK_SCOPE` 宏来完成（二选一）

- `SHADOWHOOK_RETURN_ADDRESS`

  遇到需要通过__builtin_return_address(0)获取返回后地址的位置，由于shared使用了trampoline改变了return addr，所以需要通过此宏定义间接获取。

- `SHADOWHOOK_ALLOW_REENTRANT`  &  `SHADOWHOOK_DISALLOW_REENTRANT `

  在 shared 模式中，默认是不允许 proxy 函数被重入的，因为重入可能发生在多个使用 ShadowHook 的 SDK 之间，最终形成了一个无限循环的调用环。Note：所谓的重入即是，代理函数是否被允许递归调用。





#### unique

> unique 模式中。请始终通过 hook 函数返回的原函数地址 `orig_addr` 调用原函数。

```c
// 原来函数地址
void *orig;
// stubs用于做取消
void *stub;

typedef void *(*malloc_t)(size_t);

void *my_malloc(size_t sz)
{
    if(sz > 1024)
        return nullptr;

    // 调用原函数
    return ((malloc_t)orig)(sz);
}

// hook
void do_hook(void)
{
    stub = shadowhook_hook_sym_addr(malloc, my_malloc, &orig);
}

// unhook
void do_unhook(void)
{
    shadowhook_unhook(stub);
    stub = NULL;
}
```

