---
title: SSH基础
date: 2023-0‎2‎-0‎4‎ ‏‎12:04:40
tags:
- an
---



# SSH证书



## 通过ssh-keygen生成证书

```shell
 ssh-keygen -t rsa -b 4096
```

note：

- -t 表述加密方式(dsa | ecdsa | ecdsa-sk | ed25519 | ed25519-sk | rsa)

- -b表示输出的密钥的长度



接着会弹出对话框

> Enter file in which to save the key (/root/.ssh/id_rsa): ssh-test （输入key文件的名称）



密码（这里不设置）

> Enter passphrase (empty for no passphrase):
> Enter same passphrase again:



当前路径即刻生成了rsa的公钥以及私钥

> total 8.0K
> -rw------- 1 root root 3.4K Feb  3 19:05 ssh-test
> -rw-r--r-- 1 root root  741 Feb  3 19:05 ssh-test.pub



## 配置ssh



```shell
vim ~/.ssh/config
```



```
Host 别名
	HostName ip
	User 用户名
	IdentityFile ssh私钥文件
```



