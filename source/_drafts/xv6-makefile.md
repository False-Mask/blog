---
title: Xv6 Makefile解析
tags:
- xv6
- 操作系统
- linux
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/xv6.png'
---



# Xv6 Makefile解析



## 写在前面的话



> 本文主要是对xv6-riscv的Makefile进行分析
>
> ***"只有读懂了Makefile才能更好理解项目的结构"***



> Makefile可以理解为是make的配置文件，类似的有docker的Dockerfile



## 分析



> 严格按照文件从上到下分析



## 变量声明



> 模块声明
>
> 声明了两个路径，kernel & user路径
>
> 推测这两个路径分别对应的是——“系统内核和用户程序”

```makefile
K=kernel
U=user
```



> 输出文件定义，乍一看全是kernel模块的文件
>
> （可能会疑惑为啥叫OBJS呢，因为.c文件的编译文件就是.o即object）

```makefile
OBJS = \
  $K/entry.o \
  $K/start.o \
  $K/console.o \
  $K/printf.o \
  $K/uart.o \
  $K/kalloc.o \
  $K/spinlock.o \
  $K/string.o \
  $K/main.o \
  $K/vm.o \
  $K/proc.o \
  $K/swtch.o \
  $K/trampoline.o \
  $K/trap.o \
  $K/syscall.o \
  $K/sysproc.o \
  $K/bio.o \
  $K/fs.o \
  $K/log.o \
  $K/sleeplock.o \
  $K/file.o \
  $K/pipe.o \
  $K/exec.o \
  $K/sysfile.o \
  $K/kernelvec.o \
  $K/plic.o \
  $K/virtio_disk.o
```



> 工具链寻找

```makefile
# riscv64-unknown-elf- or riscv64-linux-gnu-
# perhaps in /opt/riscv/bin
# 这里默认是注销掉了的，我自己定义了一个，把他他们重定向到具体的工具链
TOOLPREFIX = /opt/riscv/bin/rename/

# Try to infer the correct TOOLPREFIX if not set
# 如果没有定义TOOLPREFIX，会自动寻找工具链
ifndef TOOLPREFIX
# 尝试寻找riscv64-unknown-elf-objdump & riscv64-linux-gnu-objdump & riscv64-unknown-linux-gnu-objdump
# 只要上述有能用的，那就自动加载工具链的prefix
TOOLPREFIX := $(shell if riscv64-unknown-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-elf-'; \
	elif riscv64-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-linux-gnu-'; \
	elif riscv64-unknown-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-linux-gnu-'; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find a riscv64 version of GCC/binutils." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif
```



> 拼接工具路径

```makefile
# qemu模拟器，用来模拟riscv环境
QEMU = qemu-system-riscv64

# 拼接后续需要用到的gcc，gas，ld，objcopy，objdump
CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
```



> 拼接gcc编译参数 & ld链接参数

```makefile
# 启用警告信息的显示，将所有的警告视为错误，开启优化，禁用省略栈指针
# 生成适用于gdb的调试信息，使用dwarf版本2的格式信息
CFLAGS = -Wall -Werror -O -fno-omit-frame-pointer -ggdb -gdwarf-2
# 生成依赖关系文件
CFLAGS += -MD
# 中等内存模型
CFLAGS += -mcmodel=medany
# 生成嵌入式程序
# 禁止将未初始化的全局变量放置在共享内存块（不同文件相同全局变量不共享）
# 不使用标准库（glibc）
#  禁止使用汇编语言中的 "relaxation"（确保生成的汇编代码与源代码完全一致）
CFLAGS += -ffreestanding -fno-common -nostdlib -mno-relax
# 将当前路径加入头文件的寻找路径
CFLAGS += -I.
# 禁用栈保护
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)

# Disable PIE when possible (for Ubuntu 16.10 toolchain)
# 如果gcc支持禁用pie，则禁用
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
end
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

# 设置最大页表位4096字节
LDFLAGS = -z max-page-size=4096
```











































