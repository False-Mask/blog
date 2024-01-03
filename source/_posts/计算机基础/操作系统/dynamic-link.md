---
title: 动态链接过程分析
tags:
  - 操作系统
  - linux
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/dynamic-link.png'
date: 2024-01-03 16:04:40
---




# 动态链接执行过程



动态链接的执行分两类

1. 首次会从plt表跳got.plt表，最后通过链接器写入got.plt，调用实际函数
2. 之后访问会直接从plt表跳转到实际函数



# 概念 & 基础分析



- GOT

> GOT全称 Global Offset Table 全局偏移表
>
> GOT包含两部分
>
> - .got	(存放全局变量)
> - .got.plt  (存放函数引用地址)

- plt

> `.plt` 主要用于懒惰绑定，执行时负责解析函数地址并填充 `.got.plt`。

- plt.got

> `.plt.got` 是一个结合了 `.plt` 和 `.got` 的 section。
>
> 它包含了 `.plt` 中的包装器，并在执行时填充 `.got.plt` 和 `.got`。这样，第一次调用时，函数地址被填充到 `.got.plt` 和 `.got`，后续调用直接跳转到 `.got` 中的地址。——ChatGPT

关于plt.got & plt差别可见[StackOverflow](https://stackoverflow.com/questions/58076539/plt-plt-got-what-is-different)

> The difference between `.plt` and `.plt.got` is that `.plt` uses lazy binding and `.plt.got` uses non-lazy binding.
>
> Lazy binding is possible when all uses of a function are simple function calls. However, if anything requires the address of the function, then non-lazy binding must be used, since binding can only occur when the function is called, and we may need to know the address before the first call. Note that when obtaining the address, the GOT entry is accessed directly; only the function calls go via `.plt` and `.plt.got`. If the `-fno-plt` compiler option is used, then neither `.plt` nor `.plt.got` are emitted, and function calls also directly access the GOT entry.
>
> In the following examples, `objdump -d` is used for disassembly, and `readelf -r` is used to list relocations.



实际测试一下

> plt表读取

```shell
objdump -d plt

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
```

> got表读取

```shell
➜  c readelf -x .got plt

Hex dump of section '.got':
  0x00003fd8 00000000 00000000 00000000 00000000 ................
  0x00003fe8 00000000 00000000 00000000 00000000 ................
  0x00003ff8 00000000 00000000                   ........

➜  c readelf -x .got.plt plt

Hex dump of section '.got.plt':
 NOTE: This section has relocations against it, but these have NOT been applied to this dump.
  0x00004000 f83d0000 00000000 00000000 00000000 .=..............
  0x00004010 00000000 00000000 36100000 00000000 ........6.......
```





> Note:
>
> 可以理解为：
>
> "***PLT里面存放的是用于链接的代码***"
>
> "***GOT存放的是实际函数的地址。**"





# 过程分析



> 源代码

```c
#include <stdio.h>

int main() {
        printf("Hello World");
        printf("Hello World2");
}
```



> 编译

```shell
gcc -o -g plt plt.c
```





![plt.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/plt.drawio.png)



## 首次调用



### 调试



> debug

```shell
gdb ./plt
```



> 打断点

```shell
b main
b printf@plt
```



### plt





> step1 调用plt

```shell
start


   0x555555555130 <frame_dummy>:        jmp    0x5555555550b0 <register_tm_clones>
   0x555555555135 <main>:       push   rbp
   0x555555555136 <main+1>:     mov    rbp,rsp
=> 0x555555555139 <main+4>:     lea    rdi,[rip+0xec4]        # 0x555555556004
   0x555555555140 <main+11>:    mov    eax,0x0
   0x555555555145 <main+16>:    call   0x555555555030 <printf@plt>
   # 调用printf函数
   0x55555555514a <main+21>:    lea    rdi,[rip+0xebf]        # 0x555555556010
   0x555555555151 <main+28>:    mov    eax,0x0
```



> 跳到下一个断点

```shell
c

   0x555555555021:      xor    eax,0x2fe2
   0x555555555026:      jmp    QWORD PTR [rip+0x2fe4]        # 0x555555558010
   0x55555555502c:      nop    DWORD PTR [rax+0x0]
=> 0x555555555030 <printf@plt>: jmp    QWORD PTR [rip+0x2fe2]        # 0x555555558018 <printf@got.plt>
 | 0x555555555036 <printf@plt+6>:       push   0x0
 | 0x55555555503b <printf@plt+11>:      jmp    0x555555555020
 | 0x555555555040 <__cxa_finalize@plt>: jmp    QWORD PTR [rip+0x2fb2]        # 0x555555557ff8
 | 0x555555555046 <__cxa_finalize@plt+6>:       xchg   ax,ax
 |->   0x555555555036 <printf@plt+6>:   push   0x0
       0x55555555503b <printf@plt+11>:  jmp    0x555555555020
       0x555555555040 <__cxa_finalize@plt>:     jmp    QWORD PTR [rip+0x2fb2]        # 0x555555557ff8
       0x555555555046 <__cxa_finalize@plt+6>:   xchg   ax,ax
```



### got



> step2 跳转got表

```shell
0x555555555030 <printf@plt>: jmp    QWORD PTR [rip+0x2fe2]
```



> 跳转地址计算

*(rip + 1 + 0x2fe2)（这里的+1是因为x86下的jump会使得rip前进一位，所以应该取下一条指令的rip）

> +1不是数值1是下一条指令

所以需要查看的内存为

> 0x555555555036 + 0x2fe2 = 0x555555558018



> 查看内存

```shell
gdb-peda$ x/gx 0x555555558018
0x555555558018 <printf@got.plt>:        0x0000555555555036
```



> 0x0000555555555036就是jump指令的下一条指令(这里的“巧合”咱先不用管，先梳理具体的执行流程)
>
> step3 无地址信息

```shell
=> 0x555555555030 <printf@plt>: jmp    QWORD PTR [rip+0x2fe2]        # 0x555555558018 <printf@got.plt>
 | 0x555555555036 <printf@plt+6>:       push   0x0
```



> 向栈空间中添加

```shell
push   0x0
```





> 又一次jump

```shell
0x55555555503b <printf@plt+11>:      jmp    0x555555555020
```



> 又一次plt调用

```shell
=> 0x555555555020:      push   QWORD PTR [rip+0x2fe2]        # 0x555555558008
   0x555555555026:      jmp    QWORD PTR [rip+0x2fe4]        # 0x555555558010
```



> 计算得到push内容

```shell
gdb-peda$ x/gx 0x555555558008
0x555555558008: 0x00007ffff7ffe180
```



> step4 跳转/lib64/ld-linux-x86-64.so.2

```shell
0x555555555026:      jmp    QWORD PTR [rip+0x2fe4]        # 0x555555558010
```



### ld-linux-x86-64.so



```asm
Dump of assembler code for function _dl_runtime_resolve_xsavec:
   0x00007ffff7fe8610 <+0>:     push   rbx
   0x00007ffff7fe8611 <+1>:     mov    rbx,rsp # 创建栈帧
   0x00007ffff7fe8614 <+4>:     and    rsp,0xffffffffffffffc0 # 堆栈64字节对齐
   0x00007ffff7fe8618 <+8>:     sub    rsp,QWORD PTR [rip+0x14089] # 0x7ffff7ffc6a8 <_rtld_global_ro+232>
   0x00007ffff7fe861f <+15>:    mov    QWORD PTR [rsp],rax
   0x00007ffff7fe8623 <+19>:    mov    QWORD PTR [rsp+0x8],rcx
   0x00007ffff7fe8628 <+24>:    mov    QWORD PTR [rsp+0x10],rdx
   0x00007ffff7fe862d <+29>:    mov    QWORD PTR [rsp+0x18],rsi
   0x00007ffff7fe8632 <+34>:    mov    QWORD PTR [rsp+0x20],rdi
   0x00007ffff7fe8637 <+39>:    mov    QWORD PTR [rsp+0x28],r8
   0x00007ffff7fe863c <+44>:    mov    QWORD PTR [rsp+0x30],r9
   0x00007ffff7fe8641 <+49>:    mov    eax,0xee 
   0x00007ffff7fe8646 <+54>:    xor    edx,edx
   0x00007ffff7fe8648 <+56>:    mov    QWORD PTR [rsp+0x250],rdx
   0x00007ffff7fe8650 <+64>:    mov    QWORD PTR [rsp+0x258],rdx
   0x00007ffff7fe8658 <+72>:    mov    QWORD PTR [rsp+0x260],rdx
   0x00007ffff7fe8660 <+80>:    mov    QWORD PTR [rsp+0x268],rdx
   0x00007ffff7fe8668 <+88>:    mov    QWORD PTR [rsp+0x270],rdx
   0x00007ffff7fe8670 <+96>:    mov    QWORD PTR [rsp+0x278],rdx # 存储寄存器信息
   0x00007ffff7fe8678 <+104>:   xsavec [rsp+0x40] # 存储处理器状态
   0x00007ffff7fe867d <+109>:   mov    rsi,QWORD PTR [rbx+0x10] 
   0x00007ffff7fe8681 <+113>:   mov    rdi,QWORD PTR [rbx+0x8] # 读取传入的参数信息
   0x00007ffff7fe8685 <+117>:   call   0x7ffff7fe1550 <_dl_fixup> ; step 5,6 寻找地址，写入got表
   # 调用_dl_fixup函数，会将真实函数的地址写入got.plt & rax寄存器
   0x00007ffff7fe868a <+122>:   mov    r11,rax # 暂存printf函数的real地址
   0x00007ffff7fe868d <+125>:   mov    eax,0xee
   0x00007ffff7fe8692 <+130>:   xor    edx,edx
   0x00007ffff7fe8694 <+132>:   xrstor [rsp+0x40] # 与xavec对应，回复处理器状态
   0x00007ffff7fe8699 <+137>:   mov    r9,QWORD PTR [rsp+0x30]
   0x00007ffff7fe869e <+142>:   mov    r8,QWORD PTR [rsp+0x28]
   0x00007ffff7fe86a3 <+147>:   mov    rdi,QWORD PTR [rsp+0x20]
   0x00007ffff7fe86a8 <+152>:   mov    rsi,QWORD PTR [rsp+0x18]
   0x00007ffff7fe86ad <+157>:   mov    rdx,QWORD PTR [rsp+0x10]
   0x00007ffff7fe86b2 <+162>:   mov    rcx,QWORD PTR [rsp+0x8]
   0x00007ffff7fe86b7 <+167>:   mov    rax,QWORD PTR [rsp]
   0x00007ffff7fe86bb <+171>:   mov    rsp,rbx
   0x00007ffff7fe86be <+174>:   mov    rbx,QWORD PTR [rsp] # 恢复状态
   0x00007ffff7fe86c2 <+178>:   add    rsp,0x18 # 平堆栈
   0x00007ffff7fe86c6 <+182>:   bnd jmp r11 # step7 跳转printf函数
End of assembler dump.
```





## 二次调用







### plt

> step 1 调用plt

```shell
   0x555555555145 <main+16>:    call   0x555555555030 <printf@plt>
   0x55555555514a <main+21>:    lea    rdi,[rip+0xebf]        # 0x555555556010
   0x555555555151 <main+28>:    mov    eax,0x0
=> 0x555555555156 <main+33>:    call   0x555555555030 <printf@plt>
   0x55555555515b <main+38>:    mov    eax,0x0
   0x555555555160 <main+43>:    pop    rbp
   0x555555555161 <main+44>:    ret
   0x555555555162:      nop    WORD PTR cs:[rax+rax*1+0x0]
```



### got

> step 2 调用got表

```shell
   0x555555555021:      xor    eax,0x2fe2
   0x555555555026:      jmp    QWORD PTR [rip+0x2fe4]        # 0x555555558010
   0x55555555502c:      nop    DWORD PTR [rax+0x0]
=> 0x555555555030 <printf@plt>: jmp    QWORD PTR [rip+0x2fe2]        # 0x555555558018 <printf@got.plt>
 | 0x555555555036 <printf@plt+6>:       push   0x0
 | 0x55555555503b <printf@plt+11>:      jmp    0x555555555020
 | 0x555555555040 <__cxa_finalize@plt>: jmp    QWORD PTR [rip+0x2fb2]        # 0x555555557ff8
 | 0x555555555046 <__cxa_finalize@plt+6>:       xchg   ax,ax
 |->   0x7ffff7e42cf0 <__printf>:       sub    rsp,0xd8
       0x7ffff7e42cf7 <__printf+7>:     mov    r10,rdi
       0x7ffff7e42cfa <__printf+10>:    mov    QWORD PTR [rsp+0x28],rsi
       0x7ffff7e42cff <__printf+15>:    mov    QWORD PTR [rsp+0x30],rdx
```



> 查看跳转地址

```shell
gdb-peda$ x/gx 0x555555558018
0x555555558018 <printf@got.plt>:        0x00007ffff7e42cf0
gdb-peda$ info symbol 0x00007ffff7e42cf0
printf in section .text of /lib/x86_64-linux-gnu/libc.so.6
```



### 实际函数调用

> step 3 调用printf

```shell
[----------------------------------registers-----------------------------------]
RAX: 0x0
RBX: 0x0
RCX: 0x0
RDX: 0x0
RSI: 0x64 ('d')
RDI: 0x555555556010 ("Hello World2")
RBP: 0x7fffffffd920 --> 0x555555555170 (<__libc_csu_init>:      push   r15)
RSP: 0x7fffffffd918 --> 0x55555555515b (<main+38>:      mov    eax,0x0)
RIP: 0x7ffff7e42cf0 (<__printf>:        sub    rsp,0xd8)
R8 : 0x5555555592a0 ("Hello World")
R9 : 0x7ffff7fbdbe0 --> 0x5555555596a0 --> 0x0
R10: 0x6e ('n')
R11: 0x410
R12: 0x555555555050 (<_start>:  xor    ebp,ebp)
R13: 0x0
R14: 0x0
R15: 0x0
EFLAGS: 0x206 (carry PARITY adjust zero sign trap INTERRUPT direction overflow)
[-------------------------------------code-------------------------------------]
   0x7ffff7e42cde <__fprintf+174>:      call   0x7ffff7efa510 <__stack_chk_fail>
   0x7ffff7e42ce3:      nop    WORD PTR cs:[rax+rax*1+0x0]
   0x7ffff7e42ced:      nop    DWORD PTR [rax]
=> 0x7ffff7e42cf0 <__printf>:   sub    rsp,0xd8
   0x7ffff7e42cf7 <__printf+7>: mov    r10,rdi
   0x7ffff7e42cfa <__printf+10>:        mov    QWORD PTR [rsp+0x28],rsi
   0x7ffff7e42cff <__printf+15>:        mov    QWORD PTR [rsp+0x30],rdx
   0x7ffff7e42d04 <__printf+20>:        mov    QWORD PTR [rsp+0x38],rcx
[------------------------------------stack-------------------------------------]
0000| 0x7fffffffd918 --> 0x55555555515b (<main+38>:     mov    eax,0x0)
0008| 0x7fffffffd920 --> 0x555555555170 (<__libc_csu_init>:     push   r15)
0016| 0x7fffffffd928 --> 0x7ffff7e12d0a (<__libc_start_main+234>:       mov    edi,eax)
0024| 0x7fffffffd930 --> 0x7fffffffda18 --> 0x7fffffffdcf6 ("/home/fool/c/plt")
0032| 0x7fffffffd938 --> 0x100000000
0040| 0x7fffffffd940 --> 0x555555555135 (<main>:        push   rbp)
0048| 0x7fffffffd948 --> 0x7ffff7e127cf (<init_cacheinfo+287>:  mov    rbp,rax)
0056| 0x7fffffffd950 --> 0x0
[------------------------------------------------------------------------------]
Legend: code, data, rodata, value
__printf (format=0x555555556010 "Hello World2") at printf.c:28
28      {
gdb-peda$
```







# 参考



[GOT表执行过程](https://ff-0xff.github.io/2020/04/14/GOT%E8%A1%A8/#%E5%88%86%E6%9E%90-Hello-World)

[GOT/PLT执行过程分析](https://delcoding.github.io/2018/11/got-plt-study/)

[XSavec](https://www.owalle.com/2023/08/06/xsave/)

[StackOverflow plt & .plt.got的差别](https://stackoverflow.com/questions/58076539/plt-plt-got-what-is-different)