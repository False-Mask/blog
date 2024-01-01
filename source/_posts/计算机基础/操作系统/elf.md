---
title: ELF文件格式基础介绍
tags:
  - 操作系统
  - linux
cover: >-
  https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/1704117958437.png
date: 2024-01-01 21:34:23
---




# ELF文件



全称为（Executable and Linkable Format）

![1704117958437](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/1704117958437.png)





## 概念



ELF文件本质上是一种数据结构，数据的载体。



于ELF相关的几个概念：

- Section

> 组成ELF内容的最基本单元。
>
> 具体的可见上图.dynsym，.dynstr，.hash，.bss，.txt，......
>
> 每一个都是一个section

- Segment

> 执行过程中的加载映射的最小单元，一个Segment即是多个Section的集合。

- Linkable View

> ELF 未被加载到内存执行前，以 section 为单位的数据组织形式

- Executable View

> ELF 被加载到内存后，以 segment 为单位的数据组织形式





看到这可以会有一个问题——“关于为什么有Section，Segment，Linkable View，Executable View“

> 其实很简单，ELF被切分成两个大的过程 编译，执行

- Section & Linkable View是编译过程的数据呈现形式
- Segment & Executable View是运行过程中的数据呈现形式

| 构建过程 | ![build.png](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/010b2244f4584f35b7001c9eb18ff757~tplv-k3u1fbpfcp-jj-mark:3024:0:0:0:q75.awebp#?w=880&h=695&s=102389&e=png&b=ffffff) |
| -------- | ------------------------------------------------------------ |
| 链接过程 | ![runtime.png](https://p9-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/1af76d261d2f444198fd328d31c2ff70~tplv-k3u1fbpfcp-jj-mark:3024:0:0:0:q75.awebp#?w=537&h=657&s=81331&e=png&b=fffbfb) |





## 基础Section介绍



**.text**：可谓是最重要的部分，存放 `CPU` 执行的机器码。

**.rela.text**：记录 `.text` `Section` 中的重定向地址，简单来说就是 `.text` 中的某些使用到的地址是不可用的，需要借助 `.rela.text` 重新计算地址。当别的 `Section` 也需要重新计算地址时也会有一个对应的 `.rela.xxx` 的 `Section`，例如 `.rela.plt`。

**.symtab**：符号表，描述了我们定义的方法和全局变量等等，我们可以通过符号表中的信息定位到这些符号所对应的地址。

**.shstrtab** / **.strtab**：字符表，描述程序中用到的字符，比如代码中用到的方法名，变量名等等。它的记录方法很简单就是一个字符串相对于该表的偏移量，每一个字符串结束都用 `\0` 表示。

**.data**：存放已经初始化后的全局变量。

**.bss**：存放没有初始化的全局变量。

**.rodata**：存放常量。



# Binutils



> [官网](https://www.gnu.org/software/binutils/)



> 了解一个概念的最好手段，一定是手动实践



> Binutils 是 GNU开源的一系列处理二进制的工具。
>
> 当然这里的二进制包含ELF，我们可以借助这部分工具check一下ELF文件是否是和概念上说的一致。



> Note：急急国王可直接跳到objdump，readelf介绍部分，动手实践



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



> nm查看符号表



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



- **B (大写)**: 表示未初始化的数据段（BSS段）中的全局变量。在这个例子中，`__bss_start` 和 `__TMC_END__` 是这种类型的符号。
- **b (小写)**: 与大写B相似，表示未初始化的数据段中的局部变量。在这个例子中，`completed.0` 是这种类型的符号。
- **D**: 表示已初始化的数据段中的全局变量。在这个例子中，`__data_start` 是这种类型的符号。
- **W**: 表示弱引用，这些符号可能会被链接器优化或者被其他强符号覆盖。在这个例子中，`__cxa_finalize` 和 `data_start` 是这种类型的符号。
- **T**: 表示代码段中的全局函数。在这个例子中，`_fini`、`main`、`printHello` 和 `_start` 是这种类型的符号。
- **t**: 与大写T相似，表示代码段中的局部函数。在这个例子中，`deregister_tm_clones`、`__do_global_dtors_aux`、`frame_dummy` 和 `register_tm_clones` 是这种类型的符号。
- **U**: 表示未定义的符号，需要在链接时解析。在这个例子中，`__libc_start_main` 和 `printf` 是这种类型的符号。
- **R**: 表示只读数据段中的全局变量。在这个例子中，`_IO_stdin_used` 是这种类型的符号。
- **w**: 与大写W相似，表示弱引用的全局符号。在这个例子中，`__gmon_start__`、`_ITM_deregisterTMCloneTable` 和 `_ITM_registerTMCloneTable` 是这种类型的符号。
- **V**: 表示弱引用的局部符号，类似于小写b。

——By ChatGPT



## objcopy



> Copies and translates object files.
>
> 拷贝转换文件格式



### 复制



> 仅仅针对于二进制格式的文件
>
> objcopy: supported targets: elf64-x86-64 elf32-i386 elf32-iamcu elf32-x86-64 pei-i386 pei-x86-64 elf64-l1om elf64-k1om elf64-little elf64-big elf32-little elf32-big pe-x86-64 pe-bigobj-x86-64 pe-i386 srec symbolsrec verilog tekhex binary ihex plugin

```shell
➜  c objcopy a.out b.out
```



### 格式转换

> objcopy -O 输出转化格式 in out

```shell
➜  c objcopy -O elf32-x86-64 a.out b.out
➜  c file b.out
b.out: ELF 32-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=aa9b4b8402c7419098657e348074064e2b4d0c03, for GNU/Linux 3.2.0, not stripped
➜  c file a.out
a.out: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=aa9b4b8402c7419098657e348074064e2b4d0c03, for GNU/Linux 3.2.0, not stripped
➜  c
```



## objdump



> Displays information from object files.



### 汇编



```shell
➜  c objdump -d a.out
```



```plaintText

Disassembly of section .init:

0000000000001000 <_init>:
    1000:       48 83 ec 08             sub    $0x8,%rsp
    1004:       48 8b 05 dd 2f 00 00    mov    0x2fdd(%rip),%rax        # 3fe8 <__gmon_start__>
    100b:       48 85 c0                test   %rax,%rax
    100e:       74 02                   je     1012 <_init+0x12>
    1010:       ff d0                   callq  *%rax
    1012:       48 83 c4 08             add    $0x8,%rsp
    1016:       c3                      retq

Disassembly of section .plt:

0000000000001020 <.plt>:
    1020:       ff 35 e2 2f 00 00       pushq  0x2fe2(%rip)        # 4008 <_GLOBAL_OFFSET_TABLE_+0x8>
    1026:       ff 25 e4 2f 00 00       jmpq   *0x2fe4(%rip)        # 4010 <_GLOBAL_OFFSET_TABLE_+0x10>
    102c:       0f 1f 40 00             nopl   0x0(%rax)

0000000000001030 <printf@plt>:
    1030:       ff 25 e2 2f 00 00       jmpq   *0x2fe2(%rip)        # 4018 <printf@GLIBC_2.2.5>
    1036:       68 00 00 00 00          pushq  $0x0
    103b:       e9 e0 ff ff ff          jmpq   1020 <.plt>

Disassembly of section .plt.got:

0000000000001040 <__cxa_finalize@plt>:
    1040:       ff 25 b2 2f 00 00       jmpq   *0x2fb2(%rip)        # 3ff8 <__cxa_finalize@GLIBC_2.2.5>
    1046:       66 90                   xchg   %ax,%ax

Disassembly of section .text:

0000000000001050 <_start>:
    1050:       31 ed                   xor    %ebp,%ebp
    1052:       49 89 d1                mov    %rdx,%r9
    1055:       5e                      pop    %rsi
    1056:       48 89 e2                mov    %rsp,%rdx
    1059:       48 83 e4 f0             and    $0xfffffffffffffff0,%rsp
    105d:       50                      push   %rax
    105e:       54                      push   %rsp
    105f:       4c 8d 05 7a 01 00 00    lea    0x17a(%rip),%r8        # 11e0 <__libc_csu_fini>
    1066:       48 8d 0d 13 01 00 00    lea    0x113(%rip),%rcx        # 1180 <__libc_csu_init>
    106d:       48 8d 3d f1 00 00 00    lea    0xf1(%rip),%rdi        # 1165 <main>
    1074:       ff 15 66 2f 00 00       callq  *0x2f66(%rip)        # 3fe0 <__libc_start_main@GLIBC_2.2.5>
    107a:       f4                      hlt
    107b:       0f 1f 44 00 00          nopl   0x0(%rax,%rax,1)

0000000000001080 <deregister_tm_clones>:
    1080:       48 8d 3d a9 2f 00 00    lea    0x2fa9(%rip),%rdi        # 4030 <__TMC_END__>
    1087:       48 8d 05 a2 2f 00 00    lea    0x2fa2(%rip),%rax        # 4030 <__TMC_END__>
    108e:       48 39 f8                cmp    %rdi,%rax
    1091:       74 15                   je     10a8 <deregister_tm_clones+0x28>
    1093:       48 8b 05 3e 2f 00 00    mov    0x2f3e(%rip),%rax        # 3fd8 <_ITM_deregisterTMCloneTable>
    109a:       48 85 c0                test   %rax,%rax
    109d:       74 09                   je     10a8 <deregister_tm_clones+0x28>
    109f:       ff e0                   jmpq   *%rax
    10a1:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)
    10a8:       c3                      retq
    10a9:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

00000000000010b0 <register_tm_clones>:
    10b0:       48 8d 3d 79 2f 00 00    lea    0x2f79(%rip),%rdi        # 4030 <__TMC_END__>
    10b7:       48 8d 35 72 2f 00 00    lea    0x2f72(%rip),%rsi        # 4030 <__TMC_END__>
    10be:       48 29 fe                sub    %rdi,%rsi
    10c1:       48 89 f0                mov    %rsi,%rax
    10c4:       48 c1 ee 3f             shr    $0x3f,%rsi
    10c8:       48 c1 f8 03             sar    $0x3,%rax
    10cc:       48 01 c6                add    %rax,%rsi
    10cf:       48 d1 fe                sar    %rsi
    10d2:       74 14                   je     10e8 <register_tm_clones+0x38>
    10d4:       48 8b 05 15 2f 00 00    mov    0x2f15(%rip),%rax        # 3ff0 <_ITM_registerTMCloneTable>
    10db:       48 85 c0                test   %rax,%rax
    10de:       74 08                   je     10e8 <register_tm_clones+0x38>
    10e0:       ff e0                   jmpq   *%rax
    10e2:       66 0f 1f 44 00 00       nopw   0x0(%rax,%rax,1)
    10e8:       c3                      retq
    10e9:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

00000000000010f0 <__do_global_dtors_aux>:
    10f0:       80 3d 39 2f 00 00 00    cmpb   $0x0,0x2f39(%rip)        # 4030 <__TMC_END__>
    10f7:       75 2f                   jne    1128 <__do_global_dtors_aux+0x38>
    10f9:       55                      push   %rbp
    10fa:       48 83 3d f6 2e 00 00    cmpq   $0x0,0x2ef6(%rip)        # 3ff8 <__cxa_finalize@GLIBC_2.2.5>
    1101:       00
    1102:       48 89 e5                mov    %rsp,%rbp
    1105:       74 0c                   je     1113 <__do_global_dtors_aux+0x23>
    1107:       48 8b 3d 1a 2f 00 00    mov    0x2f1a(%rip),%rdi        # 4028 <__dso_handle>
    110e:       e8 2d ff ff ff          callq  1040 <__cxa_finalize@plt>
    1113:       e8 68 ff ff ff          callq  1080 <deregister_tm_clones>
    1118:       c6 05 11 2f 00 00 01    movb   $0x1,0x2f11(%rip)        # 4030 <__TMC_END__>
    111f:       5d                      pop    %rbp
    1120:       c3                      retq
    1121:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)
    1128:       c3                      retq
    1129:       0f 1f 80 00 00 00 00    nopl   0x0(%rax)

0000000000001130 <frame_dummy>:
    1130:       e9 7b ff ff ff          jmpq   10b0 <register_tm_clones>

0000000000001135 <_Z13helloWorldCppv>:
    1135:       55                      push   %rbp
    1136:       48 89 e5                mov    %rsp,%rbp
    1139:       48 8d 3d c4 0e 00 00    lea    0xec4(%rip),%rdi        # 2004 <_IO_stdin_used+0x4>
    1140:       b8 00 00 00 00          mov    $0x0,%eax
    1145:       e8 e6 fe ff ff          callq  1030 <printf@plt>
    114a:       90                      nop
    114b:       5d                      pop    %rbp
    114c:       c3                      retq

000000000000114d <helloWorldC>:
    114d:       55                      push   %rbp
    114e:       48 89 e5                mov    %rsp,%rbp
    1151:       48 8d 3d ac 0e 00 00    lea    0xeac(%rip),%rdi        # 2004 <_IO_stdin_used+0x4>
    1158:       b8 00 00 00 00          mov    $0x0,%eax
    115d:       e8 ce fe ff ff          callq  1030 <printf@plt>
    1162:       90                      nop
    1163:       5d                      pop    %rbp
    1164:       c3                      retq

0000000000001165 <main>:
    1165:       55                      push   %rbp
    1166:       48 89 e5                mov    %rsp,%rbp
    1169:       e8 c7 ff ff ff          callq  1135 <_Z13helloWorldCppv>
    116e:       e8 da ff ff ff          callq  114d <helloWorldC>
    1173:       b8 00 00 00 00          mov    $0x0,%eax
    1178:       5d                      pop    %rbp
    1179:       c3                      retq
    117a:       66 0f 1f 44 00 00       nopw   0x0(%rax,%rax,1)

0000000000001180 <__libc_csu_init>:
    1180:       41 57                   push   %r15
    1182:       4c 8d 3d 5f 2c 00 00    lea    0x2c5f(%rip),%r15        # 3de8 <__frame_dummy_init_array_entry>
    1189:       41 56                   push   %r14
    118b:       49 89 d6                mov    %rdx,%r14
    118e:       41 55                   push   %r13
    1190:       49 89 f5                mov    %rsi,%r13
    1193:       41 54                   push   %r12
    1195:       41 89 fc                mov    %edi,%r12d
    1198:       55                      push   %rbp
    1199:       48 8d 2d 50 2c 00 00    lea    0x2c50(%rip),%rbp        # 3df0 <__do_global_dtors_aux_fini_array_entry>
    11a0:       53                      push   %rbx
    11a1:       4c 29 fd                sub    %r15,%rbp
    11a4:       48 83 ec 08             sub    $0x8,%rsp
    11a8:       e8 53 fe ff ff          callq  1000 <_init>
    11ad:       48 c1 fd 03             sar    $0x3,%rbp
    11b1:       74 1b                   je     11ce <__libc_csu_init+0x4e>
    11b3:       31 db                   xor    %ebx,%ebx
    11b5:       0f 1f 00                nopl   (%rax)
    11b8:       4c 89 f2                mov    %r14,%rdx
    11bb:       4c 89 ee                mov    %r13,%rsi
    11be:       44 89 e7                mov    %r12d,%edi
    11c1:       41 ff 14 df             callq  *(%r15,%rbx,8)
    11c5:       48 83 c3 01             add    $0x1,%rbx
    11c9:       48 39 dd                cmp    %rbx,%rbp
    11cc:       75 ea                   jne    11b8 <__libc_csu_init+0x38>
    11ce:       48 83 c4 08             add    $0x8,%rsp
    11d2:       5b                      pop    %rbx
    11d3:       5d                      pop    %rbp
    11d4:       41 5c                   pop    %r12
    11d6:       41 5d                   pop    %r13
    11d8:       41 5e                   pop    %r14
    11da:       41 5f                   pop    %r15
    11dc:       c3                      retq
    11dd:       0f 1f 00                nopl   (%rax)

00000000000011e0 <__libc_csu_fini>:
    11e0:       c3                      retq

Disassembly of section .fini:

00000000000011e4 <_fini>:
    11e4:       48 83 ec 08             sub    $0x8,%rsp
    11e8:       48 83 c4 08             add    $0x8,%rsp
    11ec:       c3                      retq
```



> 这里注意下不是只有代码段有代码
>
> .init
>
> .plt
>
> .plt.got
>
> .text
>
> .fini
>
> 都有代码。



### 显示符号表



```shell
➜  c objdump -t a.out
```



```plaitText
a.out:     file format elf64-x86-64

SYMBOL TABLE:
00000000000002a8 l    d  .interp        0000000000000000              .interp
00000000000002c4 l    d  .note.gnu.build-id     0000000000000000              .note.gnu.build-id
00000000000002e8 l    d  .note.ABI-tag  0000000000000000              .note.ABI-tag
0000000000000308 l    d  .gnu.hash      0000000000000000              .gnu.hash
0000000000000330 l    d  .dynsym        0000000000000000              .dynsym
00000000000003d8 l    d  .dynstr        0000000000000000              .dynstr
000000000000045c l    d  .gnu.version   0000000000000000              .gnu.version
0000000000000470 l    d  .gnu.version_r 0000000000000000              .gnu.version_r
0000000000000490 l    d  .rela.dyn      0000000000000000              .rela.dyn
0000000000000550 l    d  .rela.plt      0000000000000000              .rela.plt
0000000000001000 l    d  .init  0000000000000000              .init
0000000000001020 l    d  .plt   0000000000000000              .plt
0000000000001040 l    d  .plt.got       0000000000000000              .plt.got
0000000000001050 l    d  .text  0000000000000000              .text
00000000000011e4 l    d  .fini  0000000000000000              .fini
0000000000002000 l    d  .rodata        0000000000000000              .rodata
0000000000002010 l    d  .eh_frame_hdr  0000000000000000              .eh_frame_hdr
0000000000002060 l    d  .eh_frame      0000000000000000              .eh_frame
0000000000003de8 l    d  .init_array    0000000000000000              .init_array
0000000000003df0 l    d  .fini_array    0000000000000000              .fini_array
0000000000003df8 l    d  .dynamic       0000000000000000              .dynamic
0000000000003fd8 l    d  .got   0000000000000000              .got
0000000000004000 l    d  .got.plt       0000000000000000              .got.plt
0000000000004020 l    d  .data  0000000000000000              .data
0000000000004030 l    d  .bss   0000000000000000              .bss
0000000000000000 l    d  .comment       0000000000000000              .comment
0000000000000000 l    df *ABS*  0000000000000000              crtstuff.c
0000000000001080 l     F .text  0000000000000000              deregister_tm_clones
00000000000010b0 l     F .text  0000000000000000              register_tm_clones
00000000000010f0 l     F .text  0000000000000000              __do_global_dtors_aux
0000000000004030 l     O .bss   0000000000000001              completed.0
0000000000003df0 l     O .fini_array    0000000000000000              __do_global_dtors_aux_fini_array_entry
0000000000001130 l     F .text  0000000000000000              frame_dummy
0000000000003de8 l     O .init_array    0000000000000000              __frame_dummy_init_array_entry
0000000000000000 l    df *ABS*  0000000000000000              a.cpp
0000000000000000 l    df *ABS*  0000000000000000              crtstuff.c
00000000000021a4 l     O .eh_frame      0000000000000000              __FRAME_END__
0000000000000000 l    df *ABS*  0000000000000000
0000000000003df0 l       .init_array    0000000000000000              __init_array_end
0000000000003df8 l     O .dynamic       0000000000000000              _DYNAMIC
0000000000003de8 l       .init_array    0000000000000000              __init_array_start
0000000000002010 l       .eh_frame_hdr  0000000000000000              __GNU_EH_FRAME_HDR
0000000000004000 l     O .got.plt       0000000000000000              _GLOBAL_OFFSET_TABLE_
0000000000001000 l     F .init  0000000000000000              _init
00000000000011e0 g     F .text  0000000000000001              __libc_csu_fini
0000000000000000  w      *UND*  0000000000000000              _ITM_deregisterTMCloneTable
0000000000004020  w      .data  0000000000000000              data_start
0000000000004030 g       .data  0000000000000000              _edata
00000000000011e4 g     F .fini  0000000000000000              .hidden _fini
0000000000000000       F *UND*  0000000000000000              printf@GLIBC_2.2.5
0000000000000000       F *UND*  0000000000000000              __libc_start_main@GLIBC_2.2.5
0000000000004020 g       .data  0000000000000000              __data_start
0000000000000000  w      *UND*  0000000000000000              __gmon_start__
0000000000004028 g     O .data  0000000000000000              .hidden __dso_handle
0000000000002000 g     O .rodata        0000000000000004              _IO_stdin_used
0000000000001180 g     F .text  000000000000005d              __libc_csu_init
0000000000004038 g       .bss   0000000000000000              _end
0000000000001050 g     F .text  000000000000002b              _start
0000000000004030 g       .bss   0000000000000000              __bss_start
0000000000001165 g     F .text  0000000000000015              main
0000000000004030 g     O .data  0000000000000000              .hidden __TMC_END__
0000000000000000  w      *UND*  0000000000000000              _ITM_registerTMCloneTable
000000000000114d g     F .text  0000000000000018              helloWorldC
0000000000000000  w    F *UND*  0000000000000000              __cxa_finalize@GLIBC_2.2.5
0000000000001135 g     F .text  0000000000000018              _Z13helloWorldCppv
```



### 显示所有section



```shell
➜  c objdump -h a.out
```



```plaitText
Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .interp       0000001c  00000000000002a8  00000000000002a8  000002a8  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  1 .note.gnu.build-id 00000024  00000000000002c4  00000000000002c4  000002c4  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  2 .note.ABI-tag 00000020  00000000000002e8  00000000000002e8  000002e8  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  3 .gnu.hash     00000024  0000000000000308  0000000000000308  00000308  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  4 .dynsym       000000a8  0000000000000330  0000000000000330  00000330  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  5 .dynstr       00000084  00000000000003d8  00000000000003d8  000003d8  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  6 .gnu.version  0000000e  000000000000045c  000000000000045c  0000045c  2**1
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  7 .gnu.version_r 00000020  0000000000000470  0000000000000470  00000470  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  8 .rela.dyn     000000c0  0000000000000490  0000000000000490  00000490  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  9 .rela.plt     00000018  0000000000000550  0000000000000550  00000550  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
 10 .init         00000017  0000000000001000  0000000000001000  00001000  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
 11 .plt          00000020  0000000000001020  0000000000001020  00001020  2**4
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
 12 .plt.got      00000008  0000000000001040  0000000000001040  00001040  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
 13 .text         00000191  0000000000001050  0000000000001050  00001050  2**4
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
 14 .fini         00000009  00000000000011e4  00000000000011e4  000011e4  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
 15 .rodata       00000010  0000000000002000  0000000000002000  00002000  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
 16 .eh_frame_hdr 0000004c  0000000000002010  0000000000002010  00002010  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
 17 .eh_frame     00000148  0000000000002060  0000000000002060  00002060  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
 18 .init_array   00000008  0000000000003de8  0000000000003de8  00002de8  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 19 .fini_array   00000008  0000000000003df0  0000000000003df0  00002df0  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 20 .dynamic      000001e0  0000000000003df8  0000000000003df8  00002df8  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 21 .got          00000028  0000000000003fd8  0000000000003fd8  00002fd8  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 22 .got.plt      00000020  0000000000004000  0000000000004000  00003000  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 23 .data         00000010  0000000000004020  0000000000004020  00003020  2**3
                  CONTENTS, ALLOC, LOAD, DATA
 24 .bss          00000008  0000000000004030  0000000000004030  00003030  2**0
                  ALLOC
 25 .comment      00000027  0000000000000000  0000000000000000  00003030  2**0
                  CONTENTS, READONLY
```



### 显示重定位表



> 编辑

```c
#include<stdio.h>

void printTest();

int main() {

        printTest();
}
➜  c
```



> 编译

```shell
➜  c gcc -o tester.o -c tester.c
```

> 查看重定位表

```shell
➜  c objdump -t tester.o

tester.o:     file format elf64-x86-64

SYMBOL TABLE:
0000000000000000 l    df *ABS*  0000000000000000 tester.c
0000000000000000 l    d  .text  0000000000000000 .text
0000000000000000 l    d  .data  0000000000000000 .data
0000000000000000 l    d  .bss   0000000000000000 .bss
0000000000000000 l    d  .note.GNU-stack        0000000000000000 .note.GNU-stack
0000000000000000 l    d  .eh_frame      0000000000000000 .eh_frame
0000000000000000 l    d  .comment       0000000000000000 .comment
0000000000000000 g     F .text  0000000000000015 main
0000000000000000         *UND*  0000000000000000 _GLOBAL_OFFSET_TABLE_
0000000000000000         *UND*  0000000000000000 printTest
```



### 查看动态链接表



```shell
➜  c objdump -T a.out

a.out:     file format elf64-x86-64

DYNAMIC SYMBOL TABLE:
0000000000000000  w   D  *UND*  0000000000000000              _ITM_deregisterTMCloneTable
0000000000000000      DF *UND*  0000000000000000  GLIBC_2.2.5 printf
0000000000000000      DF *UND*  0000000000000000  GLIBC_2.2.5 __libc_start_main
0000000000000000  w   D  *UND*  0000000000000000              __gmon_start__
0000000000000000  w   D  *UND*  0000000000000000              _ITM_registerTMCloneTable
0000000000000000  w   DF *UND*  0000000000000000  GLIBC_2.2.5 __cxa_finalize
```





## readelf



> `readelf` 是一个用于查看 ELF（Executable and Linkable Format，可执行与可链接格式）文件信息的命令行工具。ELF 是一种常见的二进制文件格式，用于执行文件、共享库和目标文件。



### 读取文件头



```shell
➜  c readelf -h a.out
ELF Header:
  Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              DYN (Shared object file)
  Machine:                           Advanced Micro Devices X86-64
  Version:                           0x1
  Entry point address:               0x1050
  Start of program headers:          64 (bytes into file)
  Start of section headers:          14768 (bytes into file)
  Flags:                             0x0
  Size of this header:               64 (bytes)
  Size of program headers:           56 (bytes)
  Number of program headers:         11
  Size of section headers:           64 (bytes)
  Number of section headers:         30
  Section header string table index: 29
```



### 读取section header & sections



```shell
➜  c readelf -S a.out
There are 30 section headers, starting at offset 0x39b0:

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .interp           PROGBITS         00000000000002a8  000002a8
       000000000000001c  0000000000000000   A       0     0     1
  [ 2] .note.gnu.bu[...] NOTE             00000000000002c4  000002c4
       0000000000000024  0000000000000000   A       0     0     4
  [ 3] .note.ABI-tag     NOTE             00000000000002e8  000002e8
       0000000000000020  0000000000000000   A       0     0     4
  [ 4] .gnu.hash         GNU_HASH         0000000000000308  00000308
       0000000000000024  0000000000000000   A       5     0     8
  [ 5] .dynsym           DYNSYM           0000000000000330  00000330
       00000000000000a8  0000000000000018   A       6     1     8
  [ 6] .dynstr           STRTAB           00000000000003d8  000003d8
       0000000000000084  0000000000000000   A       0     0     1
  [ 7] .gnu.version      VERSYM           000000000000045c  0000045c
       000000000000000e  0000000000000002   A       5     0     2
  [ 8] .gnu.version_r    VERNEED          0000000000000470  00000470
       0000000000000020  0000000000000000   A       6     1     8
  [ 9] .rela.dyn         RELA             0000000000000490  00000490
       00000000000000c0  0000000000000018   A       5     0     8
  [10] .rela.plt         RELA             0000000000000550  00000550
       0000000000000018  0000000000000018  AI       5    23     8
  [11] .init             PROGBITS         0000000000001000  00001000
       0000000000000017  0000000000000000  AX       0     0     4
  [12] .plt              PROGBITS         0000000000001020  00001020
       0000000000000020  0000000000000010  AX       0     0     16
  [13] .plt.got          PROGBITS         0000000000001040  00001040
       0000000000000008  0000000000000008  AX       0     0     8
  [14] .text             PROGBITS         0000000000001050  00001050
       0000000000000191  0000000000000000  AX       0     0     16
  [15] .fini             PROGBITS         00000000000011e4  000011e4
       0000000000000009  0000000000000000  AX       0     0     4
  [16] .rodata           PROGBITS         0000000000002000  00002000
       0000000000000010  0000000000000000   A       0     0     4
  [17] .eh_frame_hdr     PROGBITS         0000000000002010  00002010
       000000000000004c  0000000000000000   A       0     0     4
  [18] .eh_frame         PROGBITS         0000000000002060  00002060
       0000000000000148  0000000000000000   A       0     0     8
  [19] .init_array       INIT_ARRAY       0000000000003de8  00002de8
       0000000000000008  0000000000000008  WA       0     0     8
  [20] .fini_array       FINI_ARRAY       0000000000003df0  00002df0
       0000000000000008  0000000000000008  WA       0     0     8
  [21] .dynamic          DYNAMIC          0000000000003df8  00002df8
       00000000000001e0  0000000000000010  WA       6     0     8
  [22] .got              PROGBITS         0000000000003fd8  00002fd8
       0000000000000028  0000000000000008  WA       0     0     8
  [23] .got.plt          PROGBITS         0000000000004000  00003000
       0000000000000020  0000000000000008  WA       0     0     8
  [24] .data             PROGBITS         0000000000004020  00003020
       0000000000000010  0000000000000000  WA       0     0     8
  [25] .bss              NOBITS           0000000000004030  00003030
       0000000000000008  0000000000000000  WA       0     0     1
  [26] .comment          PROGBITS         0000000000000000  00003030
       0000000000000027  0000000000000001  MS       0     0     1
  [27] .symtab           SYMTAB           0000000000000000  00003058
       0000000000000630  0000000000000018          28    45     8
  [28] .strtab           STRTAB           0000000000000000  00003688
       000000000000021c  0000000000000000           0     0     1
  [29] .shstrtab         STRTAB           0000000000000000  000038a4
       0000000000000107  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  l (large), p (processor specific)                                                                      
```



### 读取program header & segments



```shell
➜  c readelf -l a.out

Elf file type is DYN (Shared object file)
Entry point 0x1050
There are 11 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000000040 0x0000000000000040
                 0x0000000000000268 0x0000000000000268  R      0x8
  INTERP         0x00000000000002a8 0x00000000000002a8 0x00000000000002a8
                 0x000000000000001c 0x000000000000001c  R      0x1
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000568 0x0000000000000568  R      0x1000
  LOAD           0x0000000000001000 0x0000000000001000 0x0000000000001000
                 0x00000000000001ed 0x00000000000001ed  R E    0x1000
  LOAD           0x0000000000002000 0x0000000000002000 0x0000000000002000
                 0x00000000000001a8 0x00000000000001a8  R      0x1000
  LOAD           0x0000000000002de8 0x0000000000003de8 0x0000000000003de8
                 0x0000000000000248 0x0000000000000250  RW     0x1000
  DYNAMIC        0x0000000000002df8 0x0000000000003df8 0x0000000000003df8
                 0x00000000000001e0 0x00000000000001e0  RW     0x8
  NOTE           0x00000000000002c4 0x00000000000002c4 0x00000000000002c4
                 0x0000000000000044 0x0000000000000044  R      0x4
  GNU_EH_FRAME   0x0000000000002010 0x0000000000002010 0x0000000000002010
                 0x000000000000004c 0x000000000000004c  R      0x4
  GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000000 0x0000000000000000  RW     0x10
  GNU_RELRO      0x0000000000002de8 0x0000000000003de8 0x0000000000003de8
                 0x0000000000000218 0x0000000000000218  R      0x1

 Section to Segment mapping:
  Segment Sections...
   00
   01     .interp
   02     .interp .note.gnu.build-id .note.ABI-tag .gnu.hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt
   03     .init .plt .plt.got .text .fini
   04     .rodata .eh_frame_hdr .eh_frame
   05     .init_array .fini_array .dynamic .got .got.plt .data .bss
   06     .dynamic
   07     .note.gnu.build-id .note.ABI-tag
   08     .eh_frame_hdr
   09
   10     .init_array .fini_array .dynamic .got
```



### 读取符号表



```shell
➜  c readelf -s a.out

Symbol table '.dynsym' contains 7 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_deregisterT[...]
     2: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND [...]@GLIBC_2.2.5 (2)
     3: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND [...]@GLIBC_2.2.5 (2)
     4: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND __gmon_start__
     5: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_registerTMC[...]
     6: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND [...]@GLIBC_2.2.5 (2)

Symbol table '.symtab' contains 66 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 00000000000002a8     0 SECTION LOCAL  DEFAULT    1
     2: 00000000000002c4     0 SECTION LOCAL  DEFAULT    2
     3: 00000000000002e8     0 SECTION LOCAL  DEFAULT    3
     4: 0000000000000308     0 SECTION LOCAL  DEFAULT    4
     5: 0000000000000330     0 SECTION LOCAL  DEFAULT    5
     6: 00000000000003d8     0 SECTION LOCAL  DEFAULT    6
     7: 000000000000045c     0 SECTION LOCAL  DEFAULT    7
     8: 0000000000000470     0 SECTION LOCAL  DEFAULT    8
     9: 0000000000000490     0 SECTION LOCAL  DEFAULT    9
    10: 0000000000000550     0 SECTION LOCAL  DEFAULT   10
    11: 0000000000001000     0 SECTION LOCAL  DEFAULT   11
    12: 0000000000001020     0 SECTION LOCAL  DEFAULT   12
    13: 0000000000001040     0 SECTION LOCAL  DEFAULT   13
    14: 0000000000001050     0 SECTION LOCAL  DEFAULT   14
    15: 00000000000011e4     0 SECTION LOCAL  DEFAULT   15
    16: 0000000000002000     0 SECTION LOCAL  DEFAULT   16
    17: 0000000000002010     0 SECTION LOCAL  DEFAULT   17
    18: 0000000000002060     0 SECTION LOCAL  DEFAULT   18
    19: 0000000000003de8     0 SECTION LOCAL  DEFAULT   19
    20: 0000000000003df0     0 SECTION LOCAL  DEFAULT   20
    21: 0000000000003df8     0 SECTION LOCAL  DEFAULT   21
    22: 0000000000003fd8     0 SECTION LOCAL  DEFAULT   22
    23: 0000000000004000     0 SECTION LOCAL  DEFAULT   23
    24: 0000000000004020     0 SECTION LOCAL  DEFAULT   24
    25: 0000000000004030     0 SECTION LOCAL  DEFAULT   25
    26: 0000000000000000     0 SECTION LOCAL  DEFAULT   26
    27: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS crtstuff.c
    28: 0000000000001080     0 FUNC    LOCAL  DEFAULT   14 deregister_tm_clones
    29: 00000000000010b0     0 FUNC    LOCAL  DEFAULT   14 register_tm_clones
    30: 00000000000010f0     0 FUNC    LOCAL  DEFAULT   14 __do_global_dtors_aux
    31: 0000000000004030     1 OBJECT  LOCAL  DEFAULT   25 completed.0
    32: 0000000000003df0     0 OBJECT  LOCAL  DEFAULT   20 __do_global_dtor[...]
    33: 0000000000001130     0 FUNC    LOCAL  DEFAULT   14 frame_dummy
    34: 0000000000003de8     0 OBJECT  LOCAL  DEFAULT   19 __frame_dummy_in[...]
    35: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS a.cpp
    36: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS crtstuff.c
    37: 00000000000021a4     0 OBJECT  LOCAL  DEFAULT   18 __FRAME_END__
    38: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS
    39: 0000000000003df0     0 NOTYPE  LOCAL  DEFAULT   19 __init_array_end
    40: 0000000000003df8     0 OBJECT  LOCAL  DEFAULT   21 _DYNAMIC
    41: 0000000000003de8     0 NOTYPE  LOCAL  DEFAULT   19 __init_array_start
    42: 0000000000002010     0 NOTYPE  LOCAL  DEFAULT   17 __GNU_EH_FRAME_HDR
    43: 0000000000004000     0 OBJECT  LOCAL  DEFAULT   23 _GLOBAL_OFFSET_TABLE_
    44: 0000000000001000     0 FUNC    LOCAL  DEFAULT   11 _init
    45: 00000000000011e0     1 FUNC    GLOBAL DEFAULT   14 __libc_csu_fini
    46: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_deregisterT[...]
    47: 0000000000004020     0 NOTYPE  WEAK   DEFAULT   24 data_start
    48: 0000000000004030     0 NOTYPE  GLOBAL DEFAULT   24 _edata
    49: 00000000000011e4     0 FUNC    GLOBAL HIDDEN    15 _fini
    50: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND printf@GLIBC_2.2.5
    51: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND __libc_start_mai[...]
    52: 0000000000004020     0 NOTYPE  GLOBAL DEFAULT   24 __data_start
    53: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND __gmon_start__
    54: 0000000000004028     0 OBJECT  GLOBAL HIDDEN    24 __dso_handle
    55: 0000000000002000     4 OBJECT  GLOBAL DEFAULT   16 _IO_stdin_used
    56: 0000000000001180    93 FUNC    GLOBAL DEFAULT   14 __libc_csu_init
    57: 0000000000004038     0 NOTYPE  GLOBAL DEFAULT   25 _end
    58: 0000000000001050    43 FUNC    GLOBAL DEFAULT   14 _start
    59: 0000000000004030     0 NOTYPE  GLOBAL DEFAULT   25 __bss_start
    60: 0000000000001165    21 FUNC    GLOBAL DEFAULT   14 main
    61: 0000000000004030     0 OBJECT  GLOBAL HIDDEN    24 __TMC_END__
    62: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND _ITM_registerTMC[...]
    63: 000000000000114d    24 FUNC    GLOBAL DEFAULT   14 helloWorldC
    64: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND __cxa_finalize@G[...]
    65: 0000000000001135    24 FUNC    GLOBAL DEFAULT   14 _Z13helloWorldCppv
```



### 读取重定位表



```shell
➜  c readelf -r a.out

Relocation section '.rela.dyn' at offset 0x490 contains 8 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000003de8  000000000008 R_X86_64_RELATIVE                    1130
000000003df0  000000000008 R_X86_64_RELATIVE                    10f0
000000004028  000000000008 R_X86_64_RELATIVE                    4028
000000003fd8  000100000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_deregisterTM[...] + 0
000000003fe0  000300000006 R_X86_64_GLOB_DAT 0000000000000000 __libc_start_main@GLIBC_2.2.5 + 0
000000003fe8  000400000006 R_X86_64_GLOB_DAT 0000000000000000 __gmon_start__ + 0
000000003ff0  000500000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_registerTMCl[...] + 0
000000003ff8  000600000006 R_X86_64_GLOB_DAT 0000000000000000 __cxa_finalize@GLIBC_2.2.5 + 0

Relocation section '.rela.plt' at offset 0x550 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000004018  000200000007 R_X86_64_JUMP_SLO 0000000000000000 printf@GLIBC_2.2.5 + 0
```





## size



> 用于查看各sections的大小分布



```shell
➜  c size a.out
   text    data     bss     dec     hex filename
   1587     584       8    2179     883 a.out
```



这个表格中的各列的含义如下：

- `text`：代码段的大小，包含可执行代码。
- `data`：数据段的大小，包含初始化的全局和静态变量。
- `bss`：未初始化的数据段（Block Started by Symbol）的大小，包含未初始化的全局和静态变量。
- `dec`：所有段的总大小（`text + data + bss`）。
- `hex`：以十六进制表示的总大小。
- `filename`：目标文件或可执行文件的名称。





```shell
➜  c size -A a.out
a.out  :
section              size    addr
.interp                28     680
.note.gnu.build-id     36     708
.note.ABI-tag          32     744
.gnu.hash              36     776
.dynsym               168     816
.dynstr               132     984
.gnu.version           14    1116
.gnu.version_r         32    1136
.rela.dyn             192    1168
.rela.plt              24    1360
.init                  23    4096
.plt                   32    4128
.plt.got                8    4160
.text                 401    4176
.fini                   9    4580
.rodata                16    8192
.eh_frame_hdr          76    8208
.eh_frame             328    8288
.init_array             8   15848
.fini_array             8   15856
.dynamic              480   15864
.got                   40   16344
.got.plt               32   16384
.data                  16   16416
.bss                    8   16432
.comment               39       0
Total                2218

```



## strings



> "strings" 命令用于在二进制文件中查找并打印可打印字符组成的字符串。

```shell
➜  c strings a.out
/lib64/ld-linux-x86-64.so.2
printf
__cxa_finalize
__libc_start_main
libc.so.6
GLIBC_2.2.5
_ITM_deregisterTMCloneTable
__gmon_start__
_ITM_registerTMCloneTable
u/UH
[]A\A]A^A_
Hello world
;*3$"
GCC: (Debian 10.2.1-6) 10.2.1 20210110
crtstuff.c
deregister_tm_clones
__do_global_dtors_aux
completed.0
__do_global_dtors_aux_fini_array_entry
frame_dummy
__frame_dummy_init_array_entry
a.cpp
__FRAME_END__
__init_array_end
_DYNAMIC
__init_array_start
__GNU_EH_FRAME_HDR
_GLOBAL_OFFSET_TABLE_
__libc_csu_fini
_ITM_deregisterTMCloneTable
_edata
printf@GLIBC_2.2.5
__libc_start_main@GLIBC_2.2.5
__data_start
__gmon_start__
__dso_handle
_IO_stdin_used
__libc_csu_init
__bss_start
main
__TMC_END__
_ITM_registerTMCloneTable
helloWorldC
__cxa_finalize@GLIBC_2.2.5
_Z13helloWorldCppv
.symtab
.strtab
.shstrtab
.interp
.note.gnu.build-id
.note.ABI-tag
.gnu.hash
.dynsym
.dynstr
.gnu.version
.gnu.version_r
.rela.dyn
.rela.plt
.init
.plt.got
.text
.fini
.rodata
.eh_frame_hdr
.eh_frame
.init_array
.fini_array
.dynamic
.got.plt
.data
.bss
.comment
```





## 其他



这部分内容由于不是重点不做介绍，但是为了知识的完整性列一下





可执行工具

- gold

> gold - The GNU ELF linker（同ld）



> 区别



> ld是一个默认的linker，性能也一般
>
> gold是新一代的linker，内存占用更少，有更强的性能。



- dlltool

> 用于修复Windows平台dll动态链接库的工具



- ranlib

> 在早期的 UNIX 系统中，`ar` 工具并不会自动创建符号表索引，而需要使用 `ranlib` 工具来显式地为静态库添加索引。`ranlib` 的存在是为了解决链接速度的问题。——ChatGPT



- strip

> `strip` 是一个用于去除可执行文件或目标文件中的符号表、调试信息以及其他不必要信息的工具。这个工具通常用于减小二进制文件的大小，特别是在发布产品版本时。



- windmc

> `windmc` 是 Windows 平台上的一个工具，用于处理 Windows 消息资源文件（`.mc` 文件），生成消息定义文件（`.h` 文件）和二进制消息资源文件（`.rc` 文件）。——ChatGPT



- windres

> `windres` 是用于处理 Windows 资源文件的工具，它通常用于将资源文件（如图标、位图、对话框模板等）编译成 Windows 可执行文件中的二进制资源。



- nlmconv

> Converts object code into an NLM
>
> `nlmconv` 是 Novell NetWare 操作系统中的一个实用程序，用于将 NetWare Loadable Module (NLM) 的源代码或可执行文件转换为 NLM 格式。



- gprof

> Displays profiling information
>
> 用于展示性能分析信息



- gprofng

> Collects and displays application performance data
>
> 收集展示性能数据





library

- libctf

> `libctf` 是用于处理 CTF（Compact C Type Format）格式的库。CTF 是一种用于表示和交换 C 编程语言中类型信息的二进制格式。这种格式通常用于支持调试信息、静态分析和其他需要了解程序中类型信息的工具。



- libbfd

> `libbfd` 是 GNU Binutils 工具集中的一部分，用于处理二进制文件的库。它提供了对多种目标文件格式（例如 ELF、COFF、Mach-O 等）的统一接口，以便进行操作、解析和生成二进制文件。



- libopcodes

> `libopcodes` 是 GNU Binutils 工具集中的一部分，提供了一套用于解析和处理操作码（opcodes）的库。这个库允许开发者编写工具，能够解析和操作各种体系结构的指令集。



- libsframe

>  A library for manipulating the SFRAME debug format
>
> 用于操作 SFRAME 调试格式的库





- elfedit

> `elfedit` 是一个用于修改 ELF（Executable and Linkable Format，可执行与可链接格式）文件的命令行工具。
>
> 主要是用来修改指令架构，文件类型（动态链接，执行文件）









# 参考



[字节跳动开源 Android PLT hook 方案 bhook](https://juejin.cn/post/6998085562573783076?searchId=202401012045486B11463DB83409B59A7C)

[手把手教你如何 Hook Native 方法](https://juejin.cn/post/7307451255412473894?searchId=20240101204359F523FD304A83459938CE)

[关于 ELF 格式文件的笔记（一）](https://juejin.cn/post/7299667259902263306)
[关于 ELF 格式文件的笔记（二）](https://juejin.cn/post/7301098227214286860)
[关于 ELF 格式文件的笔记（三）](https://juejin.cn/post/7302003014113001498)











