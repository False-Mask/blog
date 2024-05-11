---
title: BCC工具原理解析
tags:
cover:
---



# BCC工具原理分析





# filetop

## Py工具部分

> 参数配置部分（没什么看的。哈~）就解析cmdline args

```python
parser = argparse.ArgumentParser(
    description="File reads and writes by process",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-a", "--all-files", action="store_true",
    help="include non-regular file types (sockets, FIFOs, etc)")
parser.add_argument("-C", "--noclear", action="store_true",
    help="don't clear the screen")
parser.add_argument("-r", "--maxrows", default=20,
    help="maximum rows to print, default 20")
parser.add_argument("-s", "--sort", default="all",
    choices=["all", "reads", "writes", "rbytes", "wbytes"],
    help="sort column, default all")
parser.add_argument("-p", "--pid", type=int, metavar="PID", dest="tgid",
    help="trace this PID only")
parser.add_argument("interval", nargs="?", default=1,
    help="output interval, in seconds")
parser.add_argument("count", nargs="?", default=99999999,
    help="number of outputs")
parser.add_argument("--ebpf", action="store_true",
    help=argparse.SUPPRESS)

args = parser.parse_args()
interval = int(args.interval)
countdown = int(args.count)
maxrows = int(args.maxrows)
clear = not int(args.noclear)
debug = 0
```



> 初始化BPF程序
>
> 对vfs_read以及vfs_write进行trace，每次调用方法时都会调用trace_read_entry、trace_write_entry

```python
b = BPF(text=bpf_text)
b.attach_kprobe(event="vfs_read", fn_name="trace_read_entry")
b.attach_kprobe(event="vfs_write", fn_name="trace_write_entry")
```



> 结果输出
>
> 1. 休眠指定的时间段。（默认1s）
>
> 2. 打印头节点，默认调用clear刷新终端输入，
> 3. 打印/proc/loadavg信息。
> 4. 获取maps数据结构并逐行打印结果。

```python
# output
exiting = 0
while 1:
    try:
        sleep(interval) # 休眠执行时间，默认为1s
    except KeyboardInterrupt:
        exiting = 1

    # header
    if clear:
        call("clear") # 必要时候清空输出结果
    else:
        print()
    with open(loadavg) as stats: # 打印loadavg信息
        print("%-8s loadavg: %s" % (strftime("%H:%M:%S"), stats.read()))
    print("%-7s %-16s %-6s %-6s %-7s %-7s %1s %s" % ("TID", "COMM",
        "READS", "WRITES", "R_Kb", "W_Kb", "T", "FILE"))

    # by-TID output
    counts = b.get_table("counts")
    line = 0
    # counts是一个hashtab，其中以pid + comm构成的复合结构作为key。
    # 以reads、writes、rbytes、wbytes、type作为value
    for k, v in reversed(sorted(counts.items(),
                                key=sort_fn)):
        name = k.name.decode('utf-8', 'replace')
        if k.name_len > DNAME_INLINE_LEN:
            name = name[:-3] + "..."

        # print line
        print("%-7d %-16s %-6d %-6d %-7d %-7d %1s %s" % (k.pid,
            k.comm.decode('utf-8', 'replace'), v.reads, v.writes,
            v.rbytes / 1024, v.wbytes / 1024,
            k.type.decode('utf-8', 'replace'), name))

        line += 1
        # 默认只输出前20行结果。
        if line >= maxrows:
            break
    counts.clear()

    countdown -= 1
    if exiting or countdown == 0:
        print("Detaching...")
        exit()

```



## Bpf Text



> 整体内容比较长，所以依然是才用分片的方式介绍。



> 文件头

```c
#include <uapi/linux/ptrace.h>
#include <linux/blkdev.h>
```







```c
#include <uapi/linux/ptrace.h>
#include <linux/blkdev.h>

// the key for the output summary
struct info_t {
    unsigned long inode;
    dev_t dev;
    dev_t rdev;
    u32 pid;
    u32 name_len;
    char comm[TASK_COMM_LEN];
    // de->d_name.name may point to de->d_iname so limit len accordingly
    char name[DNAME_INLINE_LEN];
    char type;
};

// the value of the output summary
struct val_t {
    u64 reads;
    u64 writes;
    u64 rbytes;
    u64 wbytes;
};

BPF_HASH(counts, struct info_t, struct val_t);

static int do_entry(struct pt_regs *ctx, struct file *file,
    char __user *buf, size_t count, int is_read)
{
    u32 tgid = bpf_get_current_pid_tgid() >> 32;
    if (TGID_FILTER)
        return 0;

    u32 pid = bpf_get_current_pid_tgid();

    // skip I/O lacking a filename
    struct dentry *de = file->f_path.dentry;
    int mode = file->f_inode->i_mode;
    struct qstr d_name = de->d_name;
    if (d_name.len == 0 || TYPE_FILTER)
        return 0;

    // store counts and sizes by pid & file
    struct info_t info = {
        .pid = pid,
        .inode = file->f_inode->i_ino,
        .dev = file->f_inode->i_sb->s_dev,
        .rdev = file->f_inode->i_rdev,
    };
    bpf_get_current_comm(&info.comm, sizeof(info.comm));
    info.name_len = d_name.len;
    bpf_probe_read_kernel(&info.name, sizeof(info.name), d_name.name);
    if (S_ISREG(mode)) {
        info.type = 'R';
    } else if (S_ISSOCK(mode)) {
        info.type = 'S';
    } else {
        info.type = 'O';
    }

    struct val_t *valp, zero = {};
    valp = counts.lookup_or_try_init(&info, &zero);
    if (valp) {
        if (is_read) {
            valp->reads++;
            valp->rbytes += count;
        } else {
            valp->writes++;
            valp->wbytes += count;
        }
    }

    return 0;
}

int trace_read_entry(struct pt_regs *ctx, struct file *file,
    char __user *buf, size_t count)
{
    return do_entry(ctx, file, buf, count, 1);
}

int trace_write_entry(struct pt_regs *ctx, struct file *file,
    char __user *buf, size_t count)
{
    return do_entry(ctx, file, buf, count, 0);
}
```



