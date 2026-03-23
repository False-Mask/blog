---
title: aosp-binder-ipc
tags:
cover:
---

# Service Manager



## ServiceManager.getService


```java
public final class ServiceManager {
	/**  
	 * Returns a reference to a service with the given name. * 
	 * @param name the name of the service to get  
	 * @return a reference to the service, or <code>null</code> if the service doesn't exist  
	 * @hide  
	 */  
	@UnsupportedAppUsage  
	@android.ravenwood.annotation.RavenwoodReplace  
	public static IBinder getService(String name) {  
	    try {  
	        // 优先从缓存中获取Binder对象 
	        IBinder service = sCache.get(name);  
	        if (service != null) {  
	            return service;  
	        } else {  
	            return Binder.allowBlocking(rawGetService(name));  
	        }  
	    } catch (RemoteException e) {  
	        Log.e(TAG, "error in getService", e);  
	    }  
	    return null;  
	}

}
```


###  ServiceManager.rawGetService


```java
// ServiceManager.java

private static IBinder rawGetService(String name) throws RemoteException {
        final long start = sStatLogger.getTime();
		// 先获取ServiceManager的binder对象，调用getService通过IPC获取Binder对象。
        final IBinder binder = getIServiceManager().getService(name);

        // ......
        return binder;
}
```


### getIServiceManager

```java
// ServiceManager.java

@UnsupportedAppUsage
private static IServiceManager getIServiceManager() {
	if (sServiceManager != null) {
		return sServiceManager;
	}

	// Find the service manager
	sServiceManager = ServiceManagerNative
			.asInterface(Binder.allowBlocking(BinderInternal.getContextObject()));
	return sServiceManager;
}
```



- BinderInternal.getContextObject
```c++
static jobject android_os_BinderInternal_getContextObject(JNIEnv* env, jobject clazz)
{
    sp<IBinder> b = ProcessState::self()->getContextObject(NULL);
    return javaObjectForIBinder(env, b);
}

sp<ProcessState> ProcessState::self()
{
    return init(kDefaultDriver, false /*requireDefault*/);
}

sp<ProcessState> ProcessState::init(const char* driver, bool requireDefault) {
    if (driver == nullptr) {
        std::lock_guard<std::mutex> l(gProcessMutex);
        if (gProcess) {
            verifyNotForked(gProcess->mForked);
        }
        return gProcess;
    }

    [[clang::no_destroy]] static std::once_flag gProcessOnce;
    std::call_once(gProcessOnce, [&](){
        if (access(driver, R_OK) == -1) {
            ALOGE("Binder driver %s is unavailable. Using /dev/binder instead.", driver);
            driver = "/dev/binder";
        }

        if (0 == strcmp(driver, "/dev/vndbinder") && !isVndservicemanagerEnabled()) {
            ALOGE("vndservicemanager is not started on this device, you can save resources/threads "
                  "by not initializing ProcessState with /dev/vndbinder.");
        }

        // we must install these before instantiating the gProcess object,
        // otherwise this would race with creating it, and there could be the
        // possibility of an invalid gProcess object forked by another thread
        // before these are installed
        int ret = pthread_atfork(ProcessState::onFork, ProcessState::parentPostFork,
                                 ProcessState::childPostFork);
        LOG_ALWAYS_FATAL_IF(ret != 0, "pthread_atfork error %s", strerror(ret));

        std::lock_guard<std::mutex> l(gProcessMutex);
        gProcess = sp<ProcessState>::make(driver);
    });

    if (requireDefault) {
        // Detect if we are trying to initialize with a different driver, and
        // consider that an error. ProcessState will only be initialized once above.
        LOG_ALWAYS_FATAL_IF(gProcess->getDriverName() != driver,
                            "ProcessState was already initialized with %s,"
                            " can't initialize with %s.",
                            gProcess->getDriverName().c_str(), driver);
    }

    verifyNotForked(gProcess->mForked);
    return gProcess;
}
```



# Binder 驱动逻辑


## binder_init


## binder_ioctl


```c++
/**
* filp：文件描述符指针，即binder设备文件/dev/binder
* cmd：ioctl命令
* arg：数据指针，指向命令对应的参数，该指针是用户空间地址
**/
static long binder_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)

```

binder ioctl指令
```c++
#define BINDER_WRITE_READ		_IOWR('b', 1, struct binder_write_read)
#define BINDER_SET_IDLE_TIMEOUT		_IOW('b', 3, __s64)
#define BINDER_SET_MAX_THREADS		_IOW('b', 5, __u32)
#define BINDER_SET_IDLE_PRIORITY	_IOW('b', 6, __s32)
#define BINDER_SET_CONTEXT_MGR		_IOW('b', 7, __s32)
#define BINDER_THREAD_EXIT		_IOW('b', 8, __s32)
#define BINDER_VERSION			_IOWR('b', 9, struct binder_version)
#define BINDER_GET_NODE_DEBUG_INFO	_IOWR('b', 11, struct binder_node_debug_info)
#define BINDER_GET_NODE_INFO_FOR_REF	_IOWR('b', 12, struct binder_node_info_for_ref)
#define BINDER_SET_CONTEXT_MGR_EXT	_IOW('b', 13, struct flat_binder_object)
#define BINDER_FREEZE			_IOW('b', 14, struct binder_freeze_info)
#define BINDER_GET_FROZEN_INFO		_IOWR('b', 15, struct binder_frozen_status_info)
#define BINDER_ENABLE_ONEWAY_SPAM_DETECTION	_IOW('b', 16, __u32)
```


| 指令                                  | 含义                                                        |
| ----------------------------------- | --------------------------------------------------------- |
| BINDER_WRITE_READ                   | Binder 的核心命令，用于在用户空间和内核驱动之间传输数据，支持**同步/异步请求**和**双向数据传输**。 |
| BINDER_SET_IDLE_TIMEOUT             | 设置 Binder 线程池中空闲线程的超时时间（单位：纳秒）。                           |
| BINDER_SET_MAX_THREADS              | 设置 Binder 线程池的最大线程数。                                      |
| BINDER_SET_IDLE_PRIORITY            | 设置空闲线程的调度优先级（Linux 优先级值）。                                 |
| BINDER_SET_CONTEXT_MGR              | 将当前进程注册为 **Service Manager**（SMgr）。                       |
| BINDER_THREAD_EXIT                  | 通知驱动当前线程退出，释放相关资源。                                        |
| BINDER_VERSION                      | 获取 Binder 驱动的版本信息。                                        |
| BINDER_GET_NODE_DEBUG_INFO          | 获取 Binder 节点的调试信息（如引用计数、所属进程等）。                           |
| BINDER_GET_NODE_INFO_FOR_REF        | 根据 Binder 引用号获取关联的 Binder 实体信息。                           |
| BINDER_SET_CONTEXT_MGR_EXT          | 扩展版的 `BINDER_SET_CONTEXT_MGR`，支持额外参数（如安全上下文）。             |
| BINDER_FREEZE                       | 冻结 Binder 线程池，暂停处理新请求。                                    |
| BINDER_GET_FROZEN_INFO              | 获取 Binder 线程池的冻结状态信息。                                     |
| BINDER_ENABLE_ONEWAY_SPAM_DETECTION | 启用单向 Binder 调用的防滥用检测。                                     |


```c++
static long binder_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	int ret;
	// 核心逻辑一、binder重定义了open方法，在open的时候为每个进程创建binder_proc结构体
	struct binder_proc *proc = filp->private_data;
	struct binder_thread *thread;
	unsigned int size = _IOC_SIZE(cmd);
	void __user *ubuf = (void __user *)arg;

	/*pr_info("binder_ioctl: %d:%d %x %lx\n",
			proc->pid, current->pid, cmd, arg);*/

	binder_selftest_alloc(&proc->alloc);

	trace_binder_ioctl(cmd, arg);

	ret = wait_event_interruptible(binder_user_error_wait, binder_stop_on_user_error < 2);
	if (ret)
		goto err_unlocked;
	// 核心逻辑二、获取或创建与当前线程相关的binder_thread结构体
	thread = binder_get_thread(proc);
	if (thread == NULL) {
		ret = -ENOMEM;
		goto err;
	}

	switch (cmd) {
	case BINDER_WRITE_READ:
		ret = binder_ioctl_write_read(filp, cmd, arg, thread);
		if (ret)
			goto err;
		break;
	// ......
	}
	ret = 0;
err:
	if (thread)
		thread->looper_need_return = false;
	wait_event_interruptible(binder_user_error_wait, binder_stop_on_user_error < 2);
	if (ret && ret != -EINTR)
		pr_info("%d:%d ioctl %x %lx returned %d\n", proc->pid, current->pid, cmd, arg, ret);
err_unlocked:
	trace_binder_ioctl_done(ret);
	return ret;
}
```



### binder_proc
#### **作用**

- **进程资源管理**：每个打开 `/dev/binder`的进程都会创建一个 `binder_proc`，用于存储该进程的 Binder 相关资源，如线程池、Binder 实体、内存映射等。
    
- **全局标识**：通过全局哈希表 `binder_procs`管理所有参与 Binder 通信的进程。
    
- **生命周期**：从进程打开 `/dev/binder`开始，到进程关闭或退出时销毁。
    

#### **关键字段**

|字段|作用|
|---|---|
|`pid`|进程 ID，标识所属进程|
|`threads`|红黑树，存储该进程的所有 `binder_thread`（线程池）|
|`nodes`|红黑树，存储该进程创建的 Binder 实体（`binder_node`）|
|`refs_by_desc`|红黑树，以 Binder 引用号（handle）为键，管理外部对该进程 Binder 实体的引用|
|`buffer`|内核缓冲区的起始地址，用于进程间数据传输|
|`todo`|任务队列，存储待处理的 Binder 事务（如 `BINDER_WORK_TRANSACTION`）|
|`max_threads`|进程允许的最大 Binder 线程数|

#### **典型场景**

- **进程初始化**：当进程调用 `open("/dev/binder")`时，驱动创建 `binder_proc`并初始化其字段。
    
- **资源清理**：进程退出时，驱动遍历 `binder_proc`的 `nodes`和 `refs`，释放所有 Binder 实体和引用。

### binder_thread

#### **作用**

- **线程状态管理**：记录线程的运行状态（如空闲、忙碌、等待），控制线程的生命周期。
    
- **任务队列**：通过 `todo`链表存储待处理的 Binder 事务，线程从队列中取出任务执行。
    
- **线程同步**：通过 `wait`队列实现线程阻塞和唤醒。
    

#### **关键字段**

|字段|作用|
|---|---|
|`proc`|所属进程的 `binder_proc`指针|
|`pid`|线程 ID|
|`looper`|线程状态标志（如 `BINDER_LOOPER_STATE_NEED_RETURN`表示需要返回结果）|
|`transaction_stack`|当前正在处理的事务栈（用于嵌套事务）|
|`todo`|待处理的任务队列（如用户空间通过 `ioctl`发送的请求）|
|`wait`|等待队列，线程空闲时在此休眠|

#### **典型场景**

- **事务处理**：当线程调用 `ioctl(BINDER_WRITE_READ)`发送请求时，驱动将事务加入当前线程的 `todo`队列。
    
- **线程池管理**：当进程需要更多线程处理请求时，驱动通过 `BINDER_SET_MAX_THREADS`设置上限，并动态创建 `binder_thread`。


# Binder驱动


## binder初始化


通过调用misc_register创建/dev/binder文件

Note：如下代码运行在内核中，内核在初始化的时候会逐一调用执行install 函数。

除此之外需要注意的是在注册驱动文件的时候，binder已经将文件操作重写了，具体可见
binder_poll
binder_ioctl
compat_ptr_ioctl 
binder_mmap
binder_open
binder_flush
binder_release
```c++
// drivers/android/binder.c

const struct file_operations binder_fops = {
	.owner = THIS_MODULE,
	.poll = binder_poll,
	.unlocked_ioctl = binder_ioctl,
	.compat_ioctl = compat_ptr_ioctl,
	.mmap = binder_mmap,
	.open = binder_open,
	.flush = binder_flush,
	.release = binder_release,
};

static int __init init_binder_device(const char *name)
{
	int ret;
	struct binder_device *binder_device;

	binder_device = kzalloc(sizeof(*binder_device), GFP_KERNEL);
	if (!binder_device)
		return -ENOMEM;
	// 设置binder块设备的file operations 
	binder_device->miscdev.fops = &binder_fops;
	binder_device->miscdev.minor = MISC_DYNAMIC_MINOR;
	binder_device->miscdev.name = name;

	refcount_set(&binder_device->ref, 1);
	binder_device->context.binder_context_mgr_uid = INVALID_UID;
	binder_device->context.name = name;
	mutex_init(&binder_device->context.context_mgr_node_lock);

	ret = misc_register(&binder_device->miscdev);
	if (ret < 0) {
		kfree(binder_device);
		return ret;
	}

	hlist_add_head(&binder_device->hlist, &binder_devices);

	return ret;
}

// 向内核注册安装device文件，其中binder_init为device初始化逻辑位置
device_initcall(binder_init);
```


## 应用进程交互 



### binder_open

将binder驱动文件
```c++
static int binder_open(struct inode *nodp, struct file *filp)
{
	struct binder_proc_wrap *proc_wrap;
	struct binder_proc *proc, *itr;
	struct binder_device *binder_dev;
	struct binderfs_info *info;
	struct dentry *binder_binderfs_dir_entry_proc = NULL;
	bool existing_pid = false;

	// ......
	
	// 分配结构体内存
	proc_wrap = kzalloc(sizeof(*proc_wrap), GFP_KERNEL);
	if (proc_wrap == NULL)
		return -ENOMEM;
	proc = &proc_wrap->proc;
	// 初始化自旋锁
	spin_lock_init(&proc->inner_lock);
	spin_lock_init(&proc->outer_lock);
	// 获取
	get_task_struct(current->group_leader);
	proc->tsk = current->group_leader;
	proc->cred = get_cred(filp->f_cred);
	INIT_LIST_HEAD(&proc->todo);
	init_waitqueue_head(&proc->freeze_wait);
	if (binder_supported_policy(current->policy)) {
		proc->default_priority.sched_policy = current->policy;
		proc->default_priority.prio = current->normal_prio;
	} else {
		proc->default_priority.sched_policy = SCHED_NORMAL;
		proc->default_priority.prio = NICE_TO_PRIO(0);
	}

	/* binderfs stashes devices in i_private */
	if (is_binderfs_device(nodp)) {
		binder_dev = nodp->i_private;
		info = nodp->i_sb->s_fs_info;
		binder_binderfs_dir_entry_proc = info->proc_log_dir;
	} else {
		binder_dev = container_of(filp->private_data,
					  struct binder_device, miscdev);
	}
	refcount_inc(&binder_dev->ref);
	proc->context = &binder_dev->context;
	binder_alloc_init(&proc->alloc);

	binder_stats_created(BINDER_STAT_PROC);
	proc->pid = current->group_leader->pid;
	INIT_LIST_HEAD(&proc->delivered_death);
	INIT_LIST_HEAD(&proc->waiting_threads);
	
	// 将binder_proc结构体设置到file结构体中的private_data
	filp->private_data = proc;
	
	// 将proc_node添加到binder_procs列表中
	// 添加binder_procs锁
	mutex_lock(&binder_procs_lock);
	// 遍历所有的binder_procs
	hlist_for_each_entry(itr, &binder_procs, proc_node) {
		if (itr->pid == proc->pid) {
			existing_pid = true;
			break;
		}
	}
	hlist_add_head(&proc->proc_node, &binder_procs);
	mutex_unlock(&binder_procs_lock);
	
	// 调试信息创建
	trace_android_vh_binder_preset(&binder_procs, &binder_procs_lock);
	if (binder_debugfs_dir_entry_proc && !existing_pid) {
		char strbuf[11];

		snprintf(strbuf, sizeof(strbuf), "%u", proc->pid);
		/*
		 * proc debug entries are shared between contexts.
		 * Only create for the first PID to avoid debugfs log spamming
		 * The printing code will anyway print all contexts for a given
		 * PID so this is not a problem.
		 */
		proc->debugfs_entry = debugfs_create_file(strbuf, 0444,
			binder_debugfs_dir_entry_proc,
			(void *)(unsigned long)proc->pid,
			&proc_fops);
	}

	if (binder_binderfs_dir_entry_proc && !existing_pid) {
		char strbuf[11];
		struct dentry *binderfs_entry;

		snprintf(strbuf, sizeof(strbuf), "%u", proc->pid);
		/*
		 * Similar to debugfs, the process specific log file is shared
		 * between contexts. Only create for the first PID.
		 * This is ok since same as debugfs, the log file will contain
		 * information on all contexts of a given PID.
		 */
		binderfs_entry = binderfs_create_file(binder_binderfs_dir_entry_proc,
			strbuf, &proc_fops, (void *)(unsigned long)proc->pid);
		if (!IS_ERR(binderfs_entry)) {
			proc->binderfs_entry = binderfs_entry;
		} else {
			int error;

			error = PTR_ERR(binderfs_entry);
			pr_warn("Unable to create file %s in binderfs (error %d)\n",
				strbuf, error);
		}
	}

	return 0;
}
```

### binder_mmap




### 其他


2.用户空间与内核共享内存
通过`mmap`将**发送方用户空间**与**接收方内核空间**映射到同一块物理内存，数据仅需从**发送方用户空间→内核共享内存**一次拷贝，接收方直接读取共享内存，无需二次拷贝。
```c++
static int binder_mmap(struct file *filp, struct vm_area_struct *vma)
{
	struct binder_proc *proc = filp->private_data;
    // 合法性检查
	if (proc->tsk != current->group_leader)
		return -EINVAL;
   
	binder_debug(BINDER_DEBUG_OPEN_CLOSE,
		     "%s: %d %lx-%lx (%ld K) vma %lx pagep %lx\n",
		     __func__, proc->pid, vma->vm_start, vma->vm_end,
		     (vma->vm_end - vma->vm_start) / SZ_1K, vma->vm_flags,
		     (unsigned long)pgprot_val(vma->vm_page_prot));
    
	if (vma->vm_flags & FORBIDDEN_MMAP_FLAGS) {
		pr_err("%s: %d %lx-%lx %s failed %d\n", __func__,
		       proc->pid, vma->vm_start, vma->vm_end, "bad vm_flags", -EPERM);
		return -EPERM;
	}
	vma->vm_flags |= VM_DONTCOPY | VM_MIXEDMAP;
	vma->vm_flags &= ~VM_MAYWRITE;

	vma->vm_ops = &binder_vm_ops;
	vma->vm_private_data = proc;

	return binder_alloc_mmap_handler(&proc->alloc, vma);
}

```

- binder_alloc_mmap_handler
```c++
/**
 * binder_alloc_mmap_handler() - map virtual address space for proc
 * @alloc:	alloc structure for this proc
 * @vma:	vma passed to mmap()
 *
 * Called by binder_mmap() to initialize the space specified in
 * vma for allocating binder buffers
 *
 * Return:
 *      0 = success
 *      -EBUSY = address space already mapped
 *      -ENOMEM = failed to map memory to given address space
 */
int binder_alloc_mmap_handler(struct binder_alloc *alloc,
			      struct vm_area_struct *vma)
{
	struct binder_buffer *buffer;
	const char *failure_string;
	int ret, i;

	mutex_lock(&binder_alloc_mmap_lock);
	if (alloc->buffer_size) {
		ret = -EBUSY;
		failure_string = "already mapped";
		goto err_already_mapped;
	}
	alloc->buffer_size = min_t(unsigned long, vma->vm_end - vma->vm_start,
				   SZ_4M);
	mutex_unlock(&binder_alloc_mmap_lock);

	alloc->buffer = (void __user *)vma->vm_start;

	alloc->pages = kcalloc(alloc->buffer_size / PAGE_SIZE,
			       sizeof(alloc->pages[0]),
			       GFP_KERNEL);
	if (alloc->pages == NULL) {
		ret = -ENOMEM;
		failure_string = "alloc page array";
		goto err_alloc_pages_failed;
	}

	for (i = 0; i < alloc->buffer_size / PAGE_SIZE; i++) {
		alloc->pages[i].alloc = alloc;
		INIT_LIST_HEAD(&alloc->pages[i].lru);
	}

	buffer = kzalloc(sizeof(*buffer), GFP_KERNEL);
	if (!buffer) {
		ret = -ENOMEM;
		failure_string = "alloc buffer struct";
		goto err_alloc_buf_struct_failed;
	}

	buffer->user_data = alloc->buffer;
	list_add(&buffer->entry, &alloc->buffers);
	buffer->free = 1;
	binder_insert_free_buffer(alloc, buffer);
	alloc->free_async_space = alloc->buffer_size / 2;
	binder_alloc_set_vma(alloc, vma);
	mmgrab(alloc->vma_vm_mm);

	return 0;

err_alloc_buf_struct_failed:
	kfree(alloc->pages);
	alloc->pages = NULL;
err_alloc_pages_failed:
	alloc->buffer = 0;
	mutex_lock(&binder_alloc_mmap_lock);
	alloc->buffer_size = 0;
err_already_mapped:
	mutex_unlock(&binder_alloc_mmap_lock);
	binder_alloc_debug(BINDER_DEBUG_USER_ERROR,
			   "%s: %d %lx-%lx %s failed %d\n", __func__,
			   alloc->pid, vma->vm_start, vma->vm_end,
			   failure_string, ret);
	return ret;
}
```

# ServiceManager



## 服务注册


##  服务获取  




# 其他

- 驱动初始化
注册字符设备
- 进程与内存映射
open/mmap
创建binder_proc、内存映射(mmap)减少数据拷贝
- 服务注册
Server调用ioctl(BINDER_SET_CONTEXT_MGR) -> 启动创建binder_node
将服务名与binder_node关联，存入SM的svcinfo链表中
- 请求处理
1. 发起请求​
    
    - Client调用`transact()`→ 封装`binder_transaction_data`→ 发送`BC_TRANSACTION`命令
        
    - 驱动解析命令 → 查找目标`binder_node`→ 转发至Server进程
        
    
2. 线程调度​
    
    - **线程池管理**：Server默认16线程，动态扩展（`BINDER_SET_MAX_THREADS`）
        
    - **任务分配**：空闲线程从`todo`队列取任务执行
        
    
3. 响应返回​
    
    - Server处理完成后发送`BC_REPLY`→ 驱动唤醒Client线程 → 数据回传
        
4. 死亡通知与资源回收

- **`BC_REQUEST_DEATH_NOTIFICATION`**：注册死亡监听
    
- **`BR_DEAD_BINDER`**：通知客户端Binder对象已销毁




# 附录


[知乎-ServiceManager](https://zhuanlan.zhihu.com/p/691374002)

[binder之驱动函数ioctl](https://juejin.cn/post/7477632067414097983?searchId=20260317002934632545442A8DDAF69625)





