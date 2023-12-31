---
title: ELF文件格式基础介绍
tags:
- 操作系统
cover: https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/987550a25a5b41f1a4fc5ad1487a4ed6~tplv-k3u1fbpfcp-zoom-in-crop-mark:1512:0:0:0.awebp
---



# ELF文件



全称为（Executable and Linkable Format）





# Binutils



> [官网](https://www.gnu.org/software/binutils/)



## ld



> **ld命令** 是GNU的连接器，将目标文件连接为可执行程序。



> 这个指令通常不会单独去使用，通常是由编译器调用





> collect2是ld链接器的

```c++
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64'

 /usr/lib/gcc/x86_64-linux-gnu/10/collect2 -plugin /usr/lib/gcc/x86_64-linux-gnu/10/liblto_plugin.so -plugin-opt=/usr/lib/gcc/x86_64-linux-gnu/10/lto-wrapper -plugin-opt=-fresolution=/tmp/cc1oQl50.res -plugin-opt=-pass-through=-lgcc -plugin-opt=-pass-through=-lgcc_s -plugin-opt=-pass-through=-lc -plugin-opt=-pass-through=-lgcc -plugin-opt=-pass-through=-lgcc_s --build-id --eh-frame-hdr -m elf_x86_64 --hash-style=gnu --as-needed -dynamic-linker /lib64/ld-linux-x86-64.so.2 -pie /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/Scrt1.o /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/crti.o /usr/lib/gcc/x86_64-linux-gnu/10/crtbeginS.o -L/usr/lib/gcc/x86_64-linux-gnu/10 -L/usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu -L/usr/lib/gcc/x86_64-linux-gnu/10/../../../../lib -L/lib/x86_64-linux-gnu -L/lib/../lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib -L/usr/lib/gcc/x86_64-linux-gnu/10/../../.. /tmp/cccQGsO0.o /tmp/ccafF9v1.o -lgcc --push-state --as-needed -lgcc_s --pop-state -lc -lgcc --push-state --as-needed -lgcc_s --pop-state /usr/lib/gcc/x86_64-linux-gnu/10/crtendS.o /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/crtn.o
COLLECT_GCC_OPTIONS='-v' '-mtune=generic' '-march=x86-64'
```





## as



test.c

```c
#include <stdio.h>

void printA() {
        printf("Hello PrintA");
}
```



main.c

```c
#include <stdio.h>

void printA();

int main() {
        printA();
        return 0;
}
```



>  C语言编译成汇编

```shell
gcc -S test1.c main.c
```



> 使用汇编进行汇编

```shell
as -ac main.s
```

```shell
as -ac test1.s
```



## gold



> gold - The GNU ELF linker（同ld）



> 区别



> ld是一个默认的linker，性能也一般
>
> gold是新一代的linker，内存占用更少，有更强的性能。





## addr2line



> 和名称和符合，address to line
>
> 将地址对应到行号
>
> (注意需要有符号表才可以读取)



> 准备工作



> 书写测试代码

```c
#include <stdio.h>

void test();

int main() {
        test();
}

void test() {
        printf("Hello World");
}
```



> 编译（加入符号表）

```shell
gcc -g -o main.out main.c
```



> 运行一下

```shell
➜  c ./main.out
Hello World% 
```



> 读取函数地址

```shell
➜  c readelf -s main.out

# ...... 发现test的地址为0x000000000000114a
000000000000114a    24 FUNC    GLOBAL DEFAULT   14 test
```



> 使用addr2line

```shell
➜  c addr2line -e main.out 0x000000000000114a
/home/fool/c/main.c:9
```



> 对照一下源代码发现，index索引正常

![image-20231229164458211](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20231229164458211.png)

## ar



> A utility for creating, modifying and extracting from archives



> ar是一个一个用于创建，修改，导出archives格式文件的工具（即.a文件）



### 创建



> 创建.a文件

```c
#include <stdio.h>

void printHello() {
        printf("Hello");
}
```



> 编译.o文件

```shell
➜  c gcc -o test.o -c test.c
```



> 创建

```shell
# -r 插入或者replace源文件
# -c 如果文件不存在则创建
➜  c ar cr test.a test.o
```



> 查看

```shell
# t 查看指定archive文件的内容
➜  c ar t modified.a
test2.o
test.o
```



### 修改



> 编写文件

```c
#include <stdio.h>

void sayHi() {
        printf("sayHi");
}
```



> 编译

```shell
➜  c gcc -o test2.o -c test2.c
```



> 插入

```shell
➜  c ar rc modified.a test.a test2.o
```



> 查看文件

```shell
➜  c file modified.a
modified.a: current ar archive
```





> 删除文件

```shell
# d删除指定的file
# ar d 需要操作的文件 需要删除的文件列表
➜  c ar d modified.a test.o
```



> 查看

```shell
➜  c ar t modified.a
test2.o
```





### 导出



> 把之前创建的test.o，test1.o合并成一个.a文件

```shell
➜  c ar cr all.a test.o test2.o
```



> 创建文件 & 放入 & 进入路径

```shell
➜  c mkdir test
➜  c mv all.a test
➜  c cd test
```



> 提取导出

```shell
➜  test ar x all.a
```



> 查看

```shell
➜  test ll
total 12K
-rw-r--r-- 1 fool fool 3.3K Dec 29 22:13 all.a
-rw-r--r-- 1 fool fool 1.5K Dec 29 22:15 test2.o
-rw-r--r-- 1 fool fool 1.5K Dec 29 22:15 test.o
```





## c++filt



> 用于读取c++的mangled name输出复原后的函数名称



> cpp是支持面向对象的，是支持函数重载的，代价是c++编译器需要对C++ 函数名做变换。
>
> 会依据函数名，函数参数生成另外一个函数名称，这个过程叫name mangling



> 我们可以编写一部分代码来check一下



> 代码编写

```cpp
#include <stdio.h>

void helloWorldCpp() {
        printf("Hello world");
}

extern "C" void helloWorldC() {
        printf("Hello world");
}

int main() {
        helloWorldCpp();
        helloWorldC();
}
```



> 编译

```shell
 g++ -o a.out a.cpp
```



> 读取下子符号表

```shell
readelf -s a.out
```



```plaintText
	......
    63: 000000000000114d    24 FUNC    GLOBAL DEFAULT   14 helloWorldC
    ......
    65: 0000000000001135    24 FUNC    GLOBAL DEFAULT   14 _Z13helloWorldCppv
```

- _Z表示开头

- 13表示函数名称为13个字符（不信你自己数）
- v表示函数参数列表为void





> 切入正题，c++filt有啥用?
>
> 复原mangled name

```shell
➜  c c++filt _Z13helloWorldCppv
helloWorldCpp()
```





## dlltool



> 用于修复Windows平台dll动态链接库的工具



## elfedit







## gprof



## gprofng



## nlmconv



## nm



> 用于查看二进制文件中的符号表信息



> 使用

```shell
#include <stdio.h>

void printHello() {
        printf("Hello World");
}

int main() {
        printHello();
}
```



> 编译

```shell
gcc -o testNm testnm.c
```



> nm查看



> 输出结果有三行
>
> 相对偏移，类型，符号内容

```shell
➜  c nm testNm
0000000000004030 B __bss_start
0000000000004030 b completed.0
                 w __cxa_finalize@GLIBC_2.2.5
0000000000004020 D __data_start
0000000000004020 W data_start
0000000000001080 t deregister_tm_clones
00000000000010f0 t __do_global_dtors_aux
0000000000003df0 d __do_global_dtors_aux_fini_array_entry
0000000000004028 D __dso_handle
0000000000003df8 d _DYNAMIC
0000000000004030 D _edata
0000000000004038 B _end
00000000000011d4 T _fini
0000000000001130 t frame_dummy
0000000000003de8 d __frame_dummy_init_array_entry
000000000000217c r __FRAME_END__
0000000000004000 d _GLOBAL_OFFSET_TABLE_
                 w __gmon_start__
0000000000002010 r __GNU_EH_FRAME_HDR
0000000000001000 t _init
0000000000003df0 d __init_array_end
0000000000003de8 d __init_array_start
0000000000002000 R _IO_stdin_used
                 w _ITM_deregisterTMCloneTable
                 w _ITM_registerTMCloneTable
00000000000011d0 T __libc_csu_fini
0000000000001170 T __libc_csu_init
                 U __libc_start_main@GLIBC_2.2.5
000000000000114d T main
                 U printf@GLIBC_2.2.5
0000000000001135 T printHello
00000000000010b0 t register_tm_clones
0000000000001050 T _start
0000000000004030 D __TMC_END__
```









## objcopy



## objdump





## ranlib



## readelf



## size



## strings



## strip





## windmc



## windres





## libbfd



## lbctf



## libopcodes



## libsframe

