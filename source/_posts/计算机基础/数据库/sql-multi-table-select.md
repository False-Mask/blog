---
title: 数据库多表查询
tags:
  - sql
  - 数据库
date: 2023-10-05 09:57:20
---




# 多表查询



## 连接



> 既然是多表查询不可避免就会用到多个表的数据。



1. From连接多表

> 如下连接了AB两个表

```sql
select ......
from A, B
where A.XX = B.XX
```

2. 自连接

3. 内连接 inner join

4. 外连接

   - left join

   ```sql
   select ......
   from A
   left join B
   on XXXX
   ```

   - right join

   ```sql
   select ......
   from A
   right join B
   on XXXXX
   ```

   - full join

   ```sql
   select .....
   from A
   full join B
   on XXXXXX
   ```

   





## 嵌套子查询



> 及查询过程中内嵌一个查询



- in

>  如果A的过滤条件需要用到另外一张表的数据。

```sql
select *
from A
where XX in (
	select XX from B
    where condition
)
```

- exists

> 上方in等价，个人觉得适用于多过滤条件的情况

```sql
select *
from A
where exists (
	select * from B
    where conditon1
    and condition2
    # ......
    and conditionN
)
```



## Others



### 别名



> 简化查询过程（如果表名称比较长）

如

```sql
select * 
from AAAAAA a,BBBBBBBB b
where a.XX = b.XX
and other condition...
```









