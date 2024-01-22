---
title: risc-v指令架构基础
tags:
- risc-v
cover:

---

# RISC-V指令基础

- la

> 在 RISC-V 汇编语言中，`la` 指令通常是 Load Address 的缩写，用于将一个标签（label）的地址加载到目标寄存器中。这样，你可以使用 `la` 指令来获取某个标签的地址，而不是标签所代表的内容。

```assembly
.data
my_data_label:
    .word 42   # 一个包含值 42 的数据标签

.text
.global _start

_start:
    la a0, my_data_label  # 将 my_data_label 的地址加载到寄存器 a0 中
```



- li

> 在 RISC-V 汇编语言中，`li` 指令通常是 Load Immediate 的缩写，用于将一个立即数加载到目标寄存器中。`li` 指令实际上并不是 RISC-V 汇编的标准指令，而是一些汇编器提供的宏指令，用于方便地加载立即数。

```assembly
li a0, 42    # 将立即数 42 加载到寄存器 a0 中
```



- csrr

> 在 RISC-V 汇编语言中，`csrr` 指令用于读取控制和状态寄存器（Control and Status Register，CSR）的值。CSR 是一组特殊的寄存器，用于存储处理器的控制和状态信息。

```assembly
csrr rd, csr
# rd 是目标寄存器，用于存储从 CSR 读取的值。
# csr 是 CSR 的名称或编码，指示要读取的控制和状态寄存器。
```

```assembly
csrr a0, mhartid    # 从 mhartid 寄存器中读取当前硬件线程的标识符，存储到寄存器 a0 中
```



- add/addi

> `addi`加载立即数到寄存器，并执行加法操作。
>
> **`add` 指令：** 执行寄存器之间的加法操作。

```assembly
addi a0, a1, 5    # 将 a1 寄存器的值加上立即数 5，结果存储到 a0 中
add a0, a1, a2    # 将 a1 寄存器的值与 a2 寄存器的值相加，结果存储到 a0 中
```



- mul/muli

> **`muli` 指令：** 将寄存器与立即数进行乘法操作。
>
> **`mul` 指令：** 执行寄存器之间的乘法操作。

```assembly
mul a0, a1, a2    # 将 a1 寄存器的值与 a2 寄存器的值相乘，结果存储到 a0 中
muli a0, a1, 5    # 将 a1 寄存器的值与立即数 5 相乘，结果存储到 a0 中
```



- jal

> 在 RISC-V 中，函数调用的实现通常涉及到多个指令，包括保存和恢复寄存器、设置参数、跳转等。
>
> Jump And Link 的缩写，用于跳转到目标地址并将下一条指令的地址保存到链接寄存器（通常是 `ra`，也称为 `x1`）中。

```assembly
.text
.global _start

# 函数声明
.global my_function

# 主程序入口
_start:
    # 设置参数
    li a0, 42

    # 调用函数
    jal ra, my_function

    # 结束程序
    li a7, 10       # 系统调用号 10 表示退出程序
    ecall

# 函数定义
my_function:
    # 在这里执行函数的代码
    # 函数返回
    ret

```



# 场景分析





## 函数调用





## 分支循环



