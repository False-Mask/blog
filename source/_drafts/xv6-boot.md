---
title: Xv6启动过程
tags:
- xv6
- 操作系统
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/xv6.png'
---



# Xv6启动过程



# Xv6 调试



> 需要两个终端



> 终端1
>
> 运行gdb-server



> 终端2
>
> attach localhost



> 终端一

```shell
make qemu-gdb
```



> 终端二



> 开启gdb（需要在项目的路径，因为有.gdbinit文件）

```shell
gdb-multiarch
```



> 然后就能看见调试开启了

![image-20240115232954085](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240115232954085.png)





# kernel.ld文件解析



Linkscript中声明了入口的位置

[官方文档](https://ftp.gnu.org/old-gnu/Manuals/ld-2.9.1/html_mono/ld.html#SEC6)

> 入口函数为_entry

```ld
# 告知链接器产物输出位riscv架构
OUTPUT_ARCH( "riscv" )
# 指定入口函数为_entry函数
ENTRY( _entry )
# 定义Sections布局
SECTIONS
{
  /*
   * ensure that entry.S / _entry is at 0x80000000,
   * where qemu's -kernel jumps.
   */
   ## 将当前链接地址设置为0x80000000
  . = 0x80000000;

  .text : {
  	# *()表示匹配所有()内的sections，即匹配所有的.text .text.* sections和并到.text sections中 
    *(.text .text.*)
    # 当前地址与0x1000对齐
    . = ALIGN(0x1000);
    # 将符号 _trampoline 的值设置为当前链接地址（.）
    _trampoline = .;
    # 匹配trampsec
    *(trampsec)
    # 当前地址与0x1000对齐
    . = ALIGN(0x1000);
    # 判断trampsec是否小于一页(0x1000)
    ASSERT(. - _trampoline == 0x1000, "error: trampoline larger than one page");
    # 生成etext符号，方便程序中引用
    PROVIDE(etext = .);
  }

  .rodata : {
  	# 当前地址16位对齐 
    . = ALIGN(16);
    # 同上.text
    *(.srodata .srodata.*) /* do not need to distinguish this from .rodata */
    . = ALIGN(16);
    *(.rodata .rodata.*)
  }

  .data : {
    . = ALIGN(16);
    *(.sdata .sdata.*) /* do not need to distinguish this from .data */
    . = ALIGN(16);
    *(.data .data.*)
  }

  .bss : {
    . = ALIGN(16);
    *(.sbss .sbss.*) /* do not need to distinguish this from .bss */
    . = ALIGN(16);
    *(.bss .bss.*)
  }

  # 结束标识
  PROVIDE(end = .);
}

```





# user.ld文件解析



> 没什么特殊的地方，链接脚本属于是比较简单的那种
>
> 函数的起始地址位_main

```ld
# 指定输出架构和函数
OUTPUT_ARCH( "riscv" )
ENTRY( _main )


SECTIONS
{

 # 当前开始地址为0
 . = 0x0;
 
  .text : {
    *(.text .text.*)
  }

  .rodata : {
    # rodata起始地址16字节对齐
    . = ALIGN(16);
    *(.srodata .srodata.*) /* do not need to distinguish this from .rodata */
    . = ALIGN(16);
    *(.rodata .rodata.*)
    . = ALIGN(0x1000);
  }

  .data : {
    . = ALIGN(16);
    *(.sdata .sdata.*) /* do not need to distinguish this from .data */
    . = ALIGN(16);
    *(.data .data.*)
  }

  .bss : {
    . = ALIGN(16);
    *(.sbss .sbss.*) /* do not need to distinguish this from .bss */
    . = ALIGN(16);
    *(.bss .bss.*)
  }

  PROVIDE(end = .);
}
```





# Entry



```assembly
        # qemu -kernel loads the kernel at 0x80000000
        # and causes each hart (i.e. CPU) to jump there.
        # kernel.ld causes the following code to
        # be placed at 0x80000000.
# 定义text section
.section .text
.global _entry # 定义全局可见标签
_entry:
        # set up a stack for C.
        # stack0 is declared in start.c,
        # with a 4096-byte stack per CPU.
        # sp = stack0 + (hartid * 4096)
     
        la sp, stack0
        li a0, 1024*4
        csrr a1, mhartid
        addi a1, a1, 1
        mul a0, a0, a1
        add sp, sp, a0
        # 调用start方法
        # jump to start() in start.c
        call start
spin:
        j spin
```



# start



> 初始化



```c
void
start()
{
  // set M Previous Privilege mode to Supervisor, for mret.
  // 设置MPP为SuperVisor Mode
  unsigned long x = r_mstatus();
  x &= ~MSTATUS_MPP_MASK;
  x |= MSTATUS_MPP_S;
  w_mstatus(x);

  // set M Exception Program Counter to main, for mret.
  // requires gcc -mcmodel=medany
  // 设置M Exception PC为main函数地址
  w_mepc((uint64)main);

  // disable paging for now.
  // 暂时先关闭虚拟地址保护
  w_satp(0);

  // delegate all interrupts and exceptions to supervisor mode.
  // 将Machine Mode委托给Supervisor
  w_medeleg(0xffff);
  w_mideleg(0xffff);
  // 开启Supervisor中断（外部中断、时间中断、软件中断）
  w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);

  // configure Physical Memory Protection to give supervisor mode
  // access to all of physical memory.
  // 设置memory protection地址为0x3fffffffffffffull
  // flag为0xf
  w_pmpaddr0(0x3fffffffffffffull);
  w_pmpcfg0(0xf);

  // ask for clock interrupts.
  timerinit();

  // keep each CPU's hartid in its tp register, for cpuid().
  // 将cpu hartid设置到tp寄存器中，方便后续读取。
  int id = r_mhartid();
  w_tp(id);

  // switch to supervisor mode and jump to main().
  // 退出m mode
  asm volatile("mret");
}
```



## timerinit



> 由于XV6内核最终是跑在Qemu虚拟机里面，又因为使用的Qemu-Virt(参数-machine virt)
>
> 所以需要准确virt的预定，具体可见[qemu hw/riscv/virt.c](https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c):

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240129142905859.png" alt="image-20240129142905859"  />

```C
// Physical memory layout

// qemu -machine virt is set up like this,
// based on qemu's hw/riscv/virt.c:
//
// 00001000 -- boot ROM, provided by qemu
// 02000000 -- CLINT
// 0C000000 -- PLIC
// 10000000 -- uart0 
// 10001000 -- virtio disk 
// 80000000 -- boot ROM jumps here in machine mode
//             -kernel loads the kernel here
// unused RAM after 80000000.

// the kernel uses physical memory thus:
// 80000000 -- entry.S, then kernel text and data
// end -- start of kernel page allocation area
// PHYSTOP -- end RAM used by the kernel
```



```c
void
timerinit()
{
  // each CPU has a separate source of timer interrupts.
  // 获取hartid
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  // 累加mtimecmp
  int interval = 1000000; // cycles; about 1/10th second in qemu.
  *(uint64*)CLINT_MTIMECMP(id) = *(uint64*)CLINT_MTIME + interval;

  // prepare information in scratch[] for timervec.
  // scratch[0..2] : space for timervec to save registers.
  // scratch[3] : address of CLINT MTIMECMP register.
  // scratch[4] : desired interval (in cycles) between timer interrupts.
  // tmp数据 
  // 0..2 为timervec保存寄存器
  // 3    保存保存mtimecmp寄存器地址
  // 4    保存时钟中断的间隔
  uint64 *scratch = &timer_scratch[id][0];
  scratch[3] = CLINT_MTIMECMP(id);
  scratch[4] = interval;
  // 保存到scratch寄存器
  w_mscratch((uint64)scratch);

  // set the machine-mode trap handler.
  // 设置trap handler
  w_mtvec((uint64)timervec);
	
  // enable machine-mode interrupts.
  // 开启mie中断处理
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  // 开启mtie中断处理
  w_mie(r_mie() | MIE_MTIE);
}
```



## timervec

```assembly
.globl timervec
.align 4
timervec:
        # start.c has set up the memory that mscratch points to:
        # scratch[0,8,16] : register save area.
        # scratch[24] : address of CLINT's MTIMECMP register.
        # scratch[32] : desired interval between interrupts.
        csrrw a0, mscratch, a0 # 交换a0，mscratch
        # 将a1，a2，a3保存放入scratch内存中 scratch[0,8,16]
        sd a1, 0(a0)
        sd a2, 8(a0)
        sd a3, 16(a0)

        # schedule the next timer interrupt
        # by adding interval to mtimecmp.
        # *CLINT_MTIMECMP = *CLINT_MTIMECMP + interval
        ld a1, 24(a0) # CLINT_MTIMECMP(hart)
        ld a2, 32(a0) # interval
        ld a3, 0(a1)
        add a3, a3, a2
        sd a3, 0(a1)

        # arrange for a supervisor software interrupt
        # after this handler returns.
        # 设置sip
        li a1, 2
        csrw sip, a1

        # 恢复上下文
        ld a3, 16(a0)
        ld a2, 8(a0)
        ld a1, 0(a0)
        csrrw a0, mscratch, a0

        mret

```





# main



> 还记得start中有设置一行代码吗

```c
void start() {
    //......
    
    w_mepc((uint64)main);
    
    //......
}
```



> 这一行的代码设置了中断返回的地址。

```c
#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

volatile static int started = 0;

// start() jumps here in supervisor mode on all CPUs.
void
main()
{
    // 多CPU下，确保只初始化了一次
  if(cpuid() == 0){
    consoleinit();
    printfinit(); // 初始化printf
    printf("\n");
    printf("xv6 kernel is booting\n"); // 打印字符串
    printf("\n");					   // 打印字符串
    kinit();         // physical page allocator 物理内存分配
    kvminit();       // create kernel page table 穿件内核页面
    kvminithart();   // turn on paging 
    procinit();      // process table 初始化线程PCB
    trapinit();      // trap vectors vector
    trapinithart();  // install kernel trap vector 设置内核的trap handler
    plicinit();      // set up interrupt controller 设置中断管理器
    plicinithart();  // ask PLIC for device interrupts
    binit();         // buffer cache
    iinit();         // inode table
    fileinit();      // file table
    virtio_disk_init(); // emulated hard disk
    userinit();      // first user process 开启第一个进程
    __sync_synchronize();
    started = 1;
  } else {
    while(started == 0)
      ;
    __sync_synchronize();
    printf("hart %d starting\n", cpuid());
    kvminithart();    // turn on paging
    trapinithart();   // install kernel trap vector
    plicinithart();   // ask PLIC for device interrupts
  }

  scheduler();        
}

```



## consoleinit



```c
void
consoleinit(void)
{
    // 初始化全局🔒
  initlock(&cons.lock, "cons");
	//
  uartinit();

  // connect read and write system calls
  // to consoleread and consolewrite.
  // 将read/write syscall连接指定函数
  devsw[CONSOLE].read = consoleread;
  devsw[CONSOLE].write = consolewrite;
}
```



### initlock

> 初始化lock

```c
void
initlock(struct spinlock *lk, char *name)
{
  lk->name = name;
  lk->locked = 0;
  lk->cpu = 0;
}
```



### uartinit

> uartinit

```c
void
uartinit(void)
{
  // disable interrupts.
  WriteReg(IER, 0x00);

  // special mode to set baud rate.
  WriteReg(LCR, LCR_BAUD_LATCH);

  // LSB for baud rate of 38.4K.
  WriteReg(0, 0x03);

  // MSB for baud rate of 38.4K.
  WriteReg(1, 0x00);

  // leave set-baud mode,
  // and set word length to 8 bits, no parity.
  WriteReg(LCR, LCR_EIGHT_BITS);

  // reset and enable FIFOs.
  WriteReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);

  // enable transmit and receive interrupts.
  WriteReg(IER, IER_TX_ENABLE | IER_RX_ENABLE);

  initlock(&uart_tx_lock, "uart");
}
```



> 宏定义

```c
#define Reg(reg) ((volatile unsigned char *)(UART0 + reg))
#define WriteReg(reg, v) (*(Reg(reg)) = (v))

#define IER 1
#define LCR 3
#define FCR 2 

#define LCR_BAUD_LATCH (1<<7)
#define LCR_EIGHT_BITS (3<<0)

#define FCR_FIFO_ENABLE (1<<0)
#define FCR_FIFO_CLEAR (3<<1)

#define IER_TX_ENABLE (1<<1)
#define IER_RX_ENABLE (1<<0)
```







# 参考





[riscv-isa-manual](https://five-embeddev.com/riscv-isa-manual/latest/machine.htm)

[Github博客——RISC-V 特权架构](https://dingfen.github.io/risc-v/2020/08/05/riscv-privileged.html#csr-%E5%AF%84%E5%AD%98%E5%99%A8)

[博客园——Risc-v中断](https://www.cnblogs.com/harrypotterjackson/p/17548837.html)













