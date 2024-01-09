---
title: Xv6 Makefile解析
tags:
  - xv6
  - 操作系统
  - linux
cover: 'https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/xv6.png'
date: 2024-01-09 19:15:09
---




# Xv6 Makefile解析



> XV6构建过程，概览

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/xv6-archives.drawio.png" alt="xv6-archives.drawio" style="zoom:25%;" />



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



## 构建脚本



### $K/kernel

> kernel模块构建任务

这里需要说明下默认情况下会有这么一条task

n.o is made automatically from n.c with a recipe of the form

[GNU Make](https://www.gnu.org/software/make/manual/make.html#Last-Resort)

```makefile
$(CC) $(CPPFLAGS) $(CFLAGS) -c
```



```makefile
# 申明任务kernel/kernel 依赖OBJDS，kernel/kernel.ld文件, $U/initcode人物
$K/kernel: $(OBJS) $K/kernel.ld $U/initcode
	# 第一行指令，链接OBJS文件，指定链接脚本位kernel/kernel.ld，输出文件名称为kernel
	$(LD) $(LDFLAGS) -T $K/kernel.ld -o $K/kernel $(OBJS) 
	# 将生成的kernel/kernel文件反汇编，输出到kernel.asm文件中
	$(OBJDUMP) -S $K/kernel > $K/kernel.asm
	# 导出符号表到kernel.sym
	$(OBJDUMP) -t $K/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $K/kernel.sym
```



### $U/initcode

> user/initcode任务

```makefile
# 依赖user/initcode.S
$U/initcode: $U/initcode.S
	# 编译initcode
	$(CC) $(CFLAGS) -march=rv64g -nostdinc -I. -Ikernel -c $U/initcode.S -o $U/initcode.o
	# 使用ld链接，设置段可读可执行，启动地址为start，代码段其实地址位0
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $U/initcode.out $U/initcode.o
	# 拷贝二进制文件丢弃符号表
	$(OBJCOPY) -S -O binary $U/initcode.out $U/initcode
	# 输出initcode汇编代码
	$(OBJDUMP) -S $U/initcode.o > $U/initcode.asm
```



### tags

> tags任务

> ➜  xv6-riscv make tags
> make: *** No rule to make target '_init', needed by 'tags'.  Stop.

```makefile
# 好像这个使用上，_init task没有定义
tags: $(OBJS) _init
	etags *.S *.c
```



```makefile
ULIB = $U/ulib.o $U/usys.o $U/printf.o $U/umalloc.o

# 设置ulib下的所有可执行文件都是以_开头的
_%: %.o $(ULIB)
	# 使用user.ld链接
	$(LD) $(LDFLAGS) -T $U/user.ld -o $@ $^
	# dump asm文件
	$(OBJDUMP) -S $@ > $*.asm
	# dump 符号表
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

# user/usys.S依赖user/usys.pl
$U/usys.S : $U/usys.pl
	perl $U/usys.pl > $U/usys.S

# user/usys.o依赖user/usys.S
$U/usys.o : $U/usys.S
	$(CC) $(CFLAGS) -c -o $U/usys.o $U/usys.S

# user/_forktest依赖user/forktest.o ulib
$U/_forktest: $U/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $U/_forktest $U/forktest.o $U/ulib.o $U/usys.o
	$(OBJDUMP) -S $U/_forktest > $U/forktest.asm
```



### mkfs/mkfs

> 构建工具

```makefile
mkfs/mkfs: mkfs/mkfs.c $K/fs.h $K/param.h
	gcc -Werror -Wall -I. -o mkfs/mkfs mkfs/mkfs.c
```



> 防止删除中间产物

```makefile
.PRECIOUS: %.o
```



> 用户态程序声明

```makefile
UPROGS=\
	$U/_cat\
	$U/_echo\
	$U/_forktest\
	$U/_grep\
	$U/_init\
	$U/_kill\
	$U/_ln\
	$U/_ls\
	$U/_mkdir\
	$U/_rm\
	$U/_sh\
	$U/_stressfs\
	$U/_usertests\
	$U/_grind\
	$U/_wc\
	$U/_zombie\
```



### fs.img

> 创建镜像
>
> 依赖mkfs任务 & 用户态所有程序

```makefile
fs.img: mkfs/mkfs README $(UPROGS)
	# 通过mkfs工具创建镜像
	mkfs/mkfs fs.img README $(UPROGS)
-include kernel/*.d user/*.d
```



> 其他

```makefile
# try to generate a unique GDB port
# 为用户生成唯一的gdb port
# id -u 的值 % 5000 + 25000
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
# 生成qemu gdb参数
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
	
# 模拟cpu的核心数目（默认3个）
ifndef CPUS
CPUS := 3
endif

# qemu参数
# -machine virt：指定使用 Virt（虚拟）机器模型
# -bios none：指定不使用 BIOS。
# -kernel $K/kernel 指定要加载的内核文件的路径
# -m 128M: 指定模拟器的内存大小为 128MB
# -smp $(CPUS): 指定使用多处理器（多核）模式。
# -nographic: 指定以非图形模式运行 QEMU，即不使用图形用户界面（nographic 意味着无图形）
QEMUOPTS = -machine virt -bios none -kernel $K/kernel -m 128M -smp $(CPUS) -nographic
# 禁用 VirtIO 设备强制使用 legacy 模型，即允许使用 MMIO 模型。
QEMUOPTS += -global virtio-mmio.force-legacy=false
# 这是指定虚拟磁盘镜像文件的选项。
QEMUOPTS += -drive file=fs.img,if=none,format=raw,id=x0
# 用于添加一个 VirtIO 块设备到虚拟机
QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0
```





### qemu

> qemu任务

> 依赖$K/kernel fs.img任务

```makefile
qemu: $K/kernel fs.img
	# 启动虚拟机
	$(QEMU) $(QEMUOPTS)
```



### .gdbinit

> .gdbinit任务
>
> 依赖.gdbinit.tmpl-riscv文件
>
> 将1234端口替换为指定端口

```makefile
.gdbinit: .gdbinit.tmpl-riscv
	sed "s/:1234/:$(GDBPORT)/" < $^ > $@
```



### qemu-gdb

> qemu-gdb任务
>
> 依赖$K/kernel .gdbinit fs.img人物

```makefile
qemu-gdb: $K/kernel .gdbinit fs.img
	@echo "*** Now run 'gdb' in another window." 1>&2
	# 开启qemu gdb调试
	$(QEMU) $(QEMUOPTS) -S $(QEMUGDB)
```





## 其他



有几个比较重要的task需要说明

1.$K/kernel

> 构建内核

2.fs.img

> 构建镜像

3.qemu

> 构建内核 + 构建镜像 + 启动Qemu

4..gdbinit/qemu-gdb

> 调试





















