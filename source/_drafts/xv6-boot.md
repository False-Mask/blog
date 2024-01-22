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



# Start



