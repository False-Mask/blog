---
title: risc-v指令架构基础
tags:
  - risc-v
date: 2024-02-01 16:51:08
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/riscv.png
---


# RISC-V指令基础



## RV32





### RV32I



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3TZ3Q72ly59C7c98c.jpg" style="zoom:50%;" />

### RV32M



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3oG3Lz2ly59Cf3eb8.jpg" style="zoom:50%;" />


### RV32F & RV32D



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3Td3Lz2ly59C2ec8d.jpg" style="zoom:50%;" />



### RV32A



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3Cz6LAB4E5Cj01F6eece.jpg" style="zoom:50%;" />





### RV32C



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3H76L5B4G5Cj01F3b256.jpg" style="zoom:50%;" />





### RV32V



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3LF6L4B4D5Cj01F94427.jpg" style="zoom:50%;" />



## RV64



### RV64I



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3PN6LBB4D5Cj01Ff3024.jpg" style="zoom:50%;" />





### RV64M & RV64A



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3PN6LBB4E5Cj01F94b59.jpg" style="zoom:50%;" />



### RV64F & RV64D



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3TV6L2B4D5Cj01F105a2.jpg" style="zoom:50%;" />



### RV64C



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3TV6L2B4E5Cj01Fb34f3.jpg" style="zoom:50%;" />



# RiscV中断



<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/CB_3300083840_5ajANw3bo3D26LB3Xd6L7B4D5Cj01Fbd632.jpg" style="zoom:50%;" />



## 分类



在Riscv中中断的类型分为3种

- software interrupt——软件中断
- timer interrupt——时钟中断
- external interrupt——外部中断



- mstatus(Machine Status)，维护各种状态，如全局中断使能状态。

- mip(Machine Interrupt Pending)，记录当前的中断请求。
- mie(Machine Interrupt Enable)，维护处理器的中断使能状态。
- mcause(Machine Exception Cause)，指示发生了何种异常。
- mtvec(Machine Trap Vector)，存放发生异常时处理器跳转的地址。
- mtval(Machine Trap Value)，存放与当前自陷相关的额外信息，如地址异常的故障地址、非法指令异常的指令，发生其他异常时其值为0。
- mepc(Machine Exception PC)，指向发生异常的指令。
- mscratch(Machine Scratch)，向异常处理程序提供一个字的临时存储。



<img src="https://tinylab.org/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220707145631097.png" alt="image-20220707145631097" style="zoom:50%;" />





# RiscV特权

> 在RiscV中有3大权限模式



- M——Machine Mode

  > 最简单嵌入式系统只支持Machine模式

- S——Supervisor Mode

  > 支持虚拟内存概念的类Unix系统，需要支持Machine,User和Supervisor三种模式

- U——User Mode

  > 安全的嵌入式系统支持Machine模式和User模式





特权指令

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/8c7739f22898de40eeb7ab610c991651.png" alt="在这里插入图片描述" style="zoom:50%;" />

- sret : 监管者模式下的异常和中断返回
- mret : 机器模式下的异常和中断返回
- sfence.vma : 刷新虚拟内存映射(tlb)
- wfi ：使处理器暂停执行，并进入低功耗的等待状态，使处理器暂停执行，并进入低功耗的等待状态



## 特权级切换



```assembly
.section .text
.globl start
start:
    la      t0, supervisor
    csrw    mepc, t0
    la      t1, m_trap
    csrw    mtvec, t1
    li      t2, 0x1800
    csrc    mstatus, t2
    li      t3, 0x800
    csrs    mstatus, t3
    li      t4, 0x100
    csrs    medeleg, t4
    mret
m_trap:
    csrr    t0, mepc
    csrr    t1, mcause
    la      t2, supervisor
    csrw    mepc, t2
    mret
supervisor:
    la      t0, user
    csrw    sepc, t0
    la      t1, s_trap
    csrw    stvec, t1
    sret
s_trap:
    csrr    t0, sepc
    csrr    t1, scause
    ecall
user:
    csrr    t0, instret # 这里仅为了展示在 U 模式下可以访问的为数不多的 CSR，表示当前硬件线程已执行指令的条数
    ecall
```





流程图：

![image-20240201162905307](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240201162905307.png)







# 参考



[Linux Lab](https://tinylab.org/cpu-design-part1-riscv-privilleged-instruction/)

