---
title: bhook
tags:
  - hook
  - c/c++
cover:  https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/unhook_without_trampoline.png
date: 2023-12-28 10:19:38
---




# BHooK基础使用



# 概念



## BHook



BHook是一个PLT hook框架



## PLT hook



PLT hook即Procedure Linkage Table Hook，即利用ELF文件链接过程的特性，修改PLT链接的函数地址。

实现对指定函数进行hook的效果





# Quick Start



具体可见[官网教程](https://github.com/bytedance/bhook.git)



具体步骤

1. 导入依赖
   1. Java/Kotlin依赖导入
   2. Cpp依赖导入
2. 初始化
3. Hook





# Hook API



> 在讲解API以前，需要说明一点，***BHook是一个PLT Hook框架***。
>
> PLT是一种Native Hook技术，也就是说Hook的是C/C++代码



- Caller调用方

> 函数调用中主动调用函数的一方

- Callee被调用方

> 函数调用中被调用的一方



如下：

其中functionA是Caller

functionB是Callee

```c
void functionA() {
    // invoke
    functionB();
}

void functionB() {
    // do some
}
```



## bytehook_init



> 初始化ByteHook



> Note：
>
> 这里有[两种模式](https://github.com/bytedance/bhook/blob/main/doc/java_manual.zh-CN.md#%E5%BC%80%E5%90%AF--%E5%85%B3%E9%97%AD%E8%B0%83%E8%AF%95%E6%97%A5%E5%BF%97)
>
> - 自动模式
> - 手动模式



如果设置不当可能会出现[如下问题](https://github.com/bytedance/bhook/discussions/54)







## bytehook_hook_single



> 对指定的Caller & Callee进行Hook



```cpp
bytehook_stub_t bytehook_hook_single(
    const char *caller_path_name,  //调用者的pathname或basename（不可为NULL）
    const char *callee_path_name,  //被调用者的pathname
    const char *sym_name, 		   //需要hook的函数名（不可为NULL） 
    void *new_func, 			   //hook后调用的函数地址（不可为NULL）
    bytehook_hooked_t hooked,      //hook后的回调函数        
    void *hooked_arg			   //回调函数的自定义参数
)
```



> 实例：

```cpp
void tester(
        bytehook_stub_t task_stub,
        int status_code, const char *caller_path_name,
        const char *sym_name,
        void *new_func,
        void *prev_func,
        void *arg
) {




}

// hook libpartial.so 对于 libsingle.so 中对于testSingle的调用
bytehook_stub_t t = bytehook_hook_single(
            "libpartial.so", 			//Caller
            "libsingle.so",				// Callee
            "testSingle", 				// 符号表名称
            (void *) (singleHookProxy), // 代理函数
            tester, 					// Hook Callback回调
            NULL 						// 额外的参数
); 

if (t == 0) {
  LOGE("Error", NULL)
}
```



> Note：代理函数中需要调[用宏平栈操作](https://github.com/bytedance/bhook/blob/main/doc/native_manual.zh-CN.md#bytehook_stack_scope-%E5%92%8C-bytehook_pop_stack)

如下：

```c++
static void singleHookProxy(void) {
    BYTEHOOK_STACK_SCOPE();
    // log.e
    LOGE("Single Proxy", NULL)
}
```





> 最后发现，libpartial -> libsingle的testSingle调用都被hook了

```
2023-12-27 11:36:18.121  1095-1095  Hooker                  com.example.demo                     E  Single Proxy
2023-12-27 11:36:18.121  1095-1095  TestPartial             com.example.demo                     E  this is testPartial
2023-12-27 11:36:18.302  1095-1095  Hooker                  com.example.demo                     E  Single Proxy
2023-12-27 11:36:18.302  1095-1095  TestPartial             com.example.demo                     E  this is testPartial
```







## bytehook_hook_partial



根据指定的过滤规则hook方法



```c++
bytehook_stub_t bytehook_hook_partial(
    bytehook_caller_allow_filter_t caller_allow_filter, //过滤函数
    void *caller_allow_filter_arg,  					//额外的参数
    const char *callee_path_name,						//被调用这的路径，NULL表示所有
    const char *sym_name, 								//方法名称
    void *new_func, 									//代理方法
    bytehook_hooked_t hooked,							//hook回调函数
    void *hooked_arg									//回调函数额外的参数
);
```





> 实例：

```cpp
bytehook_hook_partial(
             filter,
             NULL,
             NULL,
             "testPartial",
             (void *)testPartialProxy,
             NULL,NULL);


void testPartialProxy() {
    BYTEHOOK_STACK_SCOPE();
    LOGE("Test Partial Proxy")
}
```







## bytehook_hook_all



> Hook所有的调用
>
> 其实有点类似于上面的hook_partial



```c++
bytehook_stub_t bytehook_hook_all(
    const char *callee_path_name,  //被调用者路径，NULL表示所有被调用者
    const char *sym_name,  		   //符号名，（not null）
    void *new_func,				   //代理函数
    bytehook_hooked_t hooked, 	   //Hook回调
    void *hooked_arg			   //自定义用于Hook回调的参数
);
```



> 实例

> 其实可以发现hook_all其实就是相当于hook_partial filter全返回true。

```c++
void hookAllProxy() {
    BYTEHOOK_STACK_SCOPE();
    LOGE("Test All Proxy")
}

bytehook_hook_all(
            NULL,
            "testPartial",
            (void *) hookAllProxy,
            NULL,
            NULL
);
```



## bytehook_unhook



> 动态解除Hook



> Note：
>
> 对于同一个库的Hook是反向执行的，即先声明hook的，实际会后执行。



> 需要注意的是，需要传入bytehook_hook_single、bytehook_hook_partial、bytehook_hook_all的返回值
>
> 可见[官方文档](https://github.com/bytedance/bhook/blob/main/doc/overview.zh-CN.md#trampoline)

```cpp
extern "C"
JNIEXPORT void JNICALL
Java_com_example_demo_TestHooker_unHookSingle(JNIEnv *env, jobject thiz) {

    bytehook_unhook(singleHook);

}
extern "C"
JNIEXPORT void JNICALL
Java_com_example_demo_TestHooker_unHookPartial(JNIEnv *env, jobject thiz) {

    bytehook_unhook(hookPartial);

}
extern "C"
JNIEXPORT void JNICALL
Java_com_example_demo_TestHooker_unHookAll(JNIEnv *env, jobject thiz) {

    bytehook_unhook(hookAll);

}
```





## bytehook_add_ignore



 ```cpp
 int bytehook_add_ignore(const char *caller_path_name);
 ```



> 同,用于添加caller_path的ignore

```java
ByteHook.addIgnore()
    
 public static int addIgnore(String callerPathName) {
    if (initStatus == ERRNO_OK) {
        return nativeAddIgnore(callerPathName);
    }
    return initStatus;
}
```





## BYTEHOOK_CALL_PREV



> [官方网站](https://github.com/bytedance/bhook/blob/main/doc/native_manual.zh-CN.md#bytehook_call_prev)



> 这个API的作用是用于调用Hook以前的函数调用



```c++
// proxy函数
void hookAllProxy() {
    BYTEHOOK_STACK_SCOPE();
    BYTEHOOK_CALL_PREV(hookAllProxy);
    LOGE("Test All Proxy")
}

// hook
bytehook_stub_t t = bytehook_hook_all(
        NULL,
        "testPartial",
        (void *) hookAllProxy,
        NULL,
        NULL
);
```





## BYTEHOOK_RETURN_ADDRESS



> 即获取调用的的函数地址——也就是return address
>
> 有点类似于__builtin_return_address();



__builtin_return_address会获取堆栈中具体偏移的地址。

- 0表示调用方地址，

- 1表示调用方的调用方地址。

- 2表示三级调用方地址

......



> BYTEHOOK_RETURN_ADDRESS所做的也就是获取——堆栈中第一个没有被Hook的函数地址





## BYTEHOOK_POP_STACK & BYTEHOOK_POP_STACK



> [官方网站](https://github.com/bytedance/bhook/blob/main/doc/native_manual.zh-CN.md#bytehook_stack_scope-%E5%92%8C-bytehook_pop_stack)



- 每个 proxy 函数中都必须执行 ByteHook 的 stack 清理逻辑。有两种方式：
  - **在 C++ 代码中：在“proxy 函数”开头调用一次 `BYTEHOOK_STACK_SCOPE` 宏。（其中会通过析构函数的方式，来保证 stack 清理逻辑一定会被执行）**
  - **在 C 代码中：请在“proxy 函数”的每一个“返回分支”末尾都调用 `BYTEHOOK_POP_STACK` 宏。**



可能Proxy的内部调用采用了栈的结构，如果没有清理逻辑就会导致内部执行逻辑混乱。

（具体是怎么设计的，得分析源码以后才知道）



> 不过这都是无所谓的，咱在使用的时候记着调用宏定义即可。

