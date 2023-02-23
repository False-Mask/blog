---
title: Docker Compose
date: 2023-02-06 11:00:58
tags:
- devops
categories:
- devops
- docker compose
---



# [Docker Compose](https://docs.docker.com/compose/) 

> Compose是一个用于管理多容器的工具，仅用一个yaml文件，一条指令即可创建，开启,停止所有的服务



## [Docker Compose 文件语法](https://docs.docker.com/compose/compose-file/#compose-file)



> Compose 文件是一个yaml格式的文件。文件内容包含version，services，networks,volumns,configs,secrets



### yaml



#### 多行缩进

> 一种描述数据的标记语言，类似于xml,json等。

数据结构可以用类似大纲的缩排方式呈现，结构通过缩进来表示，连续的项目通过减号“-”来表示，map结构里面的key/value对用冒号“:”来分隔。样例如下：

```yaml
house:
  family:
    name: Doe
    parents:
      - John
      - Jane
    children:
      - Paul
      - Mark
      - Simone
  address:
    number: 34
    street: Main Street
    city: Nowheretown
    zipcode: 12345
```



> 等同于如下Java语法描述的数据

```java
class House {
    Family f;
    Address a;
    public House(Family f,Address a) {
        //...
    }
}
class Family {
    String name;
    List<String> parents;
    List<String> children;
    public Family(String name,List<String> parents,List<String> children){
        //...
    }
}
class Address {
    int number;
    String street;
    String city;
    int zipcode;
    public Address(int number,String street,String city,int zipcode) {
        //...
    }
}
```

```java
new House(
    new Family("Doe",List.of("John","Jane"),List.of("Paul","Mark","Simone")),
    new Address(34,"Main Street","Nowheretown",1234)
)
```



Notes:

1. 字串不一定要用双引号标识；
2. 在缩排中空白字符的数目并不是非常重要，只要相同阶层的元素左侧**对齐**就可以了（**不过不能使用TAB字符**）
3. 允许在文件中加入选择性的空行，以增加可读性；
4. 在一个档案中，可同时包含多个文件，并用“——”分隔；
5. 选择性的符号“...”可以用来表示档案结尾（在利用串流的通讯中，这非常有用，可以在不关闭串流的情况下，发送结束讯号）。



#### 单行缩进

> 描述的同一结构的不同写法,个人感觉简洁是简洁，但是可读性是真的不太邢。docker compose官网实例基本是采用的多行缩进。

```yaml
house:
  family: { name: Doe, parents: [John, Jane], children: [Paul, Mark, Simone] }
  address: { number: 34, street: Main Street, city: Nowheretown, zipcode: 12345 }
```



### versions

```yaml
versions: 
```

确认compose的版本号(官方不推荐我们写,此处为了向后兼容)

> A Compose implementation SHOULD NOT use this version to select an exact schema to validate the Compose file, but prefer the most recent schema at the time it has been designed.





### services

> A Service is an abstract definition of a computing resource within an application which can be scaled/replaced independently from other components. Services are backed by a set of containers, run by the platform according to replication requirements and placement constraints. Being backed by containers, Services are defined by a Docker image and set of runtime arguments. All containers within a service are identically created with these arguments.
>
> Service是执行资源的抽象定义，services的背后是container的集合，运行的container是其实就是由docker image和运行时环境变量组成的services定义的。



#### build

> container需要镜像才能创建，镜像可以是远端的，也可以是自己构建的，build参数可以用以声明自定义的镜像。



#### [blkio_config](https://docs.docker.com/compose/compose-file/#blkio_config)

blocking io configuration。用于配置io，使用或许较少。



#### [configs](https://docs.docker.com/compose/compose-file/#configs)

> `configs` grant access to configs on a per-service basis using the per-service `configs` configuration
>
> 表示允许访问指定的configs，每一个service都使用自己的configs，来区分不同的配置。
>
> 值得注意的是，使用configs之前得定义configs



> configs有两中格式，shorts syntax，long syntax



- short syntax

> The short syntax variant only specifies the config name. This grants the container access to the config and mounts it at `/<config_name>` within the container. The source name and destination mount point are both set to the config name
>
> short syntax的写法只需要声明config的名称，之后该config文件就会被mount在container的**/<config_name>** 路径下。

> 声明了两个configs：
>
> - my_config
> - my_config
>
> 其中redis（service名称，随意定义）服务可以使用my_config



```yaml
services:
  redis:
    image: redis:latest
    configs:
      - my_config
configs:
  my_config:
    file: ./my_config.txt
  my_other_config:
    external: true

```



调用docker compose up以后，生成了如下的一个集群。这个集群里面包含一个redis container

![image-20230206125858471](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206125858471.png)



进入容器查看内容

![image-20230206130317942](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206130317942.png)



由于没有创建config文件，自动创建了一个文件夹。**是文件夹**！！

![image-20230206130546271](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206130546271.png)



而且还与本地路径的my_config做了挂载（docker compose up创建容器之后new的文件）

![image-20230206130714732](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206130714732.png)

容器内也有对应的文件

![image-20230206130833120](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206130833120.png)



在docker compose up之前创建了文件，会把这个文件映射到docker容器内。

![image-20230206131035221](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206131035221.png)



![image-20230206131219023](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206131219023.png)



文件内容的修改也会同步到compose的文件中





- #### Long syntax

> short syntax 虽然简单，但是不能精确得控制配置文件的属性，细粒度不够。long syntax 通过如下属性控制配置文件
>
> - `source`: 选用哪个配置
> - `target`: 文件挂载到container的哪个位置，如果不指定就默认挂载到/<source> 
> - `uid` and `gid`: config文件的所属uid和gid，用处不大。
> - `mode`: unix文件权限号。



选用my_config,挂载在/redis_config， owner uid 为103，gid为103，只有owner和group有读权限。

```yaml
services:
  redis:
    image: redis:latest
    configs:
      - source: my_config
        target: /redis_config
        uid: "103"
        gid: "103"
        mode: 0440
configs:
  my_config:
    external: true
  my_other_config:
    external: true

```



![image-20230206132933367](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206132933367.png)



![image-20230206132911472](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206132911472.png)







#### container_name

> 用于指定container的名称



#### depends_on

> 指定容器的依赖关系，微服务开启和关闭。
>
> 开启服务和关闭服务采用拓扑排序。



#### hostname

> 定义一个自定义主机名



```yaml
services:
  nginx:
    hostname: ng
    image: nginx 
  test:
    image: nginx
```



生成两个容器

![image-20230206142204093](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206142204093.png)



在test容器内使用hostname为一串杂凑值

![image-20230206143720523](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206143720523.png)



ng容器的hostname为ng

![image-20230206143841598](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230206143841598.png)



#### links

> 定义和其他service的网络连接，定义方式有两种：
>
> - <serviceName> 
> - <serviceName>:<alias>

```yaml
web:
  links:
    - db
    - db:database
    - redis
```



#### networks

> 定义service加入的网络，network的定义需要在顶层声明networks，然后进行配置。

如下some-service，加入了some-network和other-network。

```yaml
services:
  some-service:
    networks:
      - some-network
      - other-network
```



#### ports

> 端口映射，将容器端口和宿主机端口进行绑定。

语法格式分为两类

- Short Syntax

> 是一个以冒号分隔的字符串语法如下
>
> [host:]contianer[/protocol]
>
> - host  指 [ip:]\(port | range)
> - container 指 port | range
> - protocol 指协议大多是tcp udp

```yaml
ports:
  - "3000"
  - "3000-3005"
  - "8000:8000"
  - "9090-9091:8080-8081"
  - "49100:22"
  - "127.0.0.1:8001:8001"
  - "127.0.0.1:5000-5010:5000-5010"
  - "6060:6060/udp"

```

- Long Syntax

> 相比于short syntax，有更加精细的粒度
>
> - `target`: 容器端口
> - `published`: container暴露的duan'kduank偶.
> - `host_ip`: 主机进行映射的接口，如果不设置默认为全部接口i(`0.0.0.0`)
> - `protocol`: 端口采用xie'yxieyi  (`tcp` or `udp`), 不声明默认是所有协议
> - `mode`: `host` 用于与宿主机做映射, or `ingress` 用于做负载均衡.



#### restart

> container终止后处理策略
>
> - `no`: 什么都不做 	
> - `always`:  如果container没有被移除尝试重启.
> - `on-failure`: 如果是因为出错而终止，进行重启.
> - `unless-stopped`: 如果container被stop了或者remove了不重启，此外进行重启。



#### secrets

> 准许service访问敏感文件，语法分为两类

- #### Short syntax

> 只需要声明secret的名称，container只有read权限，并且文件将被mount在contianer 的/run/secrets/<secret_name>路径下



文件将被挂载在/run/secrets/server-certificate

```yaml
services:
  frontend:
    image: awesome/webapp
    secrets:
      - server-certificate
secrets:
  server-certificate:
    file: ./server.cert

```



- #### Long syntax
> 
  - `source`:  secrets项
  - `target`:  挂载在`/run/secrets`路径的文件的名称
  - `uid` and `gid`: secret 文件的owner和所属组id
  - `mode`:  unix文件权限

  ```yaml
  services:
    frontend:
      image: awesome/webapp
      secrets:
        - source: server-certificate
          target: server.cert
          uid: "103"
          gid: "103"
          mode: 0440
  secrets:
    server-certificate:
      external: true
  ```





#### volumes

> 定义宿主机和container容器的映射关系。语法格式分为长短两种。
>
> 如果该数据卷只能由一个service使用，那么这个属性作为service的一部分，不需要额外声明顶层的volumes。

- Short Syntax

>  以分号为间隔，分为两种语法。
>
> - volume: container_path
> - volume: container_path: access_mode\
>
> volume: 宿主机的路径或者卷的名称
>
> container_path:  卷挂载在宿主机的路径
>
> access_mode: 以逗号分隔的选项，可以是rw，ro，z，Z，读写，只读，不同容器共享，不同容器不共享。

- Long Syntax

> - `type`: 挂载类型 `volume`, `bind`, `tmpfs` or `npipe`
>
> - `source`: 挂载源头, 要么是宿主机的路径, 或者是[`top-level `volumes` key](https://docs.docker.com/compose/compose-file/#volumes-top-level-element). Not applicable for a tmpfs mount.
>
> - `target`: 卷挂载在container的位置
>
> - `read_only`:  暗示卷制度
>
>   : configure additional bind options
>
>   - `propagation`: the propagation mode used for the bind
>  - `create_host_path`: create a directory at the source path on host if there is nothing present. Do nothing if there is something present at the path. This is automatically implied by short syntax for backward compatibility with docker-compose legacy.
>   - `selinux`: the SELinux re-labeling option `z` (shared) or `Z` (private)
> 
> - `volume`: configure additional volume options
>
>   - `nocopy`: flag to disable copying of data from a container when a volume is created
>
> - `tmpfs`
>
>   : configure additional tmpfs options
>
>   - `size`: the size for the tmpfs mount in bytes (either numeric or as bytes unit)
>  - `mode`: the filemode for the tmpfs mount as Unix permission bits as an octal number
> 
>- `consistency`: the consistency requirements of the mount. Available values are platform specific



#### working_dir 

> 覆写container中由image(Dockerfile workdir)指定的工作路径



### networks

> 用与不同容器间的互相连通



#### name

> 设置网络名称



#### external

> 设置为true表示不归compose管辖





#### volumes

> volumes是用于存储的持久化卷



#### name

> 指定volume的名称



### configs

The top-level `configs` declaration defines or references configuration data that can be granted to the services in this application. The source of the config is either `file` or `external`.

> `configs`声明声明该数据授权给service的，其来源要么是文件，要么是以及存在的config。

- `file`:  文件路径
- `external`: true表明config以及被创建了（可能类似于c语言的external关键字）
- `name`: 配置名称。 





### secrets

> 同configs，只是说，configs挂载的文件权限是读写，secrets是只读。
