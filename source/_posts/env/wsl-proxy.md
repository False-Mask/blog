---
title: WSL Mirrored NetworkMode
tags:
  - wsl
cover: >-
  https://upload.wikimedia.org/wikipedia/commons/thumb/3/35/Tux.svg/150px-Tux.svg.png
date: 2023-12-28 14:22:56
---




# WSL镜像网络



## 背景



> 在做一个安全试验的过程中：
>
> 需要将本机作为一个服务器与外部网络进行交互。



> WSL默认是NAT的模式，无法实现于外网交互的逻辑。



> Vmware作为虚拟机可以配置网络的状态为bridge，作为虚拟机的WSL是否也可以呢？



## 配置



1. 修改.wslconfig文件

```plaintText
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
```

2. 关闭wsl

```shell
wsl --shutdown
```

3. 重新进入wsl



# 参考链接



[知乎](https://zhuanlan.zhihu.com/p/659074950)

[WSL官网](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#main-wsl-settings)
