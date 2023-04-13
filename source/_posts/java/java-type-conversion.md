---
title: 记一次Java类型强转
date: 2023-04-13 11:54:09
tags:
- error
- java
---



# 背景



> 在刷一道Leetcode题

> [剑指 Offer 19. 正则表达式匹配](https://leetcode.cn/problems/zheng-ze-biao-da-shi-pi-pei-lcof/description/)

> 对照了答案，使用了DP对此题进行求解，由于没有完全抄题解的，所以有部分内容不完全一致。
>
> 但是就逻辑上和题解完全一致。可就是无法通过OJ



![image-20230413120622286](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230413120622286.png)



# 源代码

> [官方题解](https://leetcode.cn/problems/zheng-ze-biao-da-shi-pi-pei-lcof/solutions/521347/zheng-ze-biao-da-shi-pi-pei-by-leetcode-s3jgn/)

```java
class Solution {
    public boolean isMatch(String s, String p) {
        int m = s.length();
        int n = p.length();
        boolean[][] dp = new boolean[m + 1][n + 1];
        dp[0][0] = true;
        for(int i = 0;i <= m; i++) {
            for(int j = 1;j <= n; j++) {
                if(p.charAt(j - 1) == '*') {
                    if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 2))) {
                        dp[i][j] = dp[i - 1][j] || dp[i][j - 2];
                    } else {
                        dp[i][j] = dp[i][j - 2];
                    }
                } else {
                    if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 1))) {
                        dp[i][j] = dp[i - 1][j - 1];
                    }
                }
            }
        }
        return dp[m][n];
    }

    public boolean matches(char a,char b) {
        if(a == -1) {
            return false;
        }
        if(b == '.') {
            return true;
        } else {
            return a == b;
        }
    }
}
```



# 解决思路



- 由于是dp题，所以核心其实也就是状态转移方程

![image-20230413120403261](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230413120403261.png)



```java
if(p.charAt(j - 1) == '*') {
   if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 2))) {
       dp[i][j] = dp[i - 1][j] || dp[i][j - 2];
   } else {
       dp[i][j] = dp[i][j - 2];
   }
} else {
    if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 1))) {
        dp[i][j] = dp[i - 1][j - 1];
    }
}
```

> 很容易得出结论，问题可能不是在状态转移方程上





- 那么唯一的出错点只有可能是match函数了

> 然而match函数就这么短，逻辑基本上就等同于没有，我还能写错？

> 所以正是因为这可怜的自信，这问题差不多花了我10来分钟。

```java
public boolean matches(char a,char b) {
    if(a == -1) {
        return false;
    }
    if(b == '.') {
        return true;
    } else {
        return a == b;
    }
}
```



> 问题出现在char的类型转换

> match函数在代码中有两次调用

```java
matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 2));
matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 1));
```



> 按理i == 0时 char 即为 (char) -1

> 依据如下代码段，所以match函数应该返回false

```java
if(a == -1) {
   return false;
}
```



>可是并不会，因为**(char) -1 != -1**

```java
System.out.println(-1 == (char)-1); // false
System.out.println((char) -1); // 65535
```



> char的大小为2个字节，即16位二进制

> -1所对应的原码为
>
> 1 1 1 1   1 1 1 1  1 1 1 1  1 1 1 1

> 不难想到将(char) -1 转为int的值即为65535了，这很明显不会与(int)-1相同。

```java
public class Test {

    public static void main(String[] args) {
        System.out.println((long) ((short) -1)); // -1
        System.out.println((long) ((byte) -1)); // -1
        System.out.println((long) ((int) -1)); // -1
        System.out.println((long) ((float) -1)); // -1
        System.out.println((long) ((double) -1)); // -1
        System.out.println((int) ((char) -1)); // 65535
    }

}

```



> 最后修改了matches方法，OJ通过了

> 时间: 2 ms
>
> 击败: 40.72%

```java
class Solution {
    public boolean isMatch(String s, String p) {
        int m = s.length();
        int n = p.length();
        boolean[][] dp = new boolean[m + 1][n + 1];
        dp[0][0] = true;
        for(int i = 0;i <= m; i++) {
            for(int j = 1;j <= n; j++) {
                if(p.charAt(j - 1) == '*') {
                    if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 2))) {
                        dp[i][j] = dp[i - 1][j] || dp[i][j - 2];
                    } else {
                        dp[i][j] = dp[i][j - 2];
                    }
                } else {
                    if(matches(i == 0 ? (char)-1 : s.charAt(i - 1),p.charAt(j - 1))) {
                        dp[i][j] = dp[i - 1][j - 1];
                    }
                }
            }
        }
        return dp[m][n];
    }

    public boolean matches(char a,char b) {
        //System.out.println(a+":"+b);
        //System.out.println(a == (char)-1);
        if(a == (char)-1) {
            return false;
        }
        if(b == '.') {
            return true;
        } else {
            return a == b;
        }
    }
}
```



> 代码优化

> 时间: 1 ms
>
> 击败: 100%

```java
class Solution {
    public boolean isMatch(String s, String p) {
        int m = s.length();
        int n = p.length();
        boolean[][] dp = new boolean[m + 1][n + 1];
        dp[0][0] = true;
        // 将 i=1部分抽离
        for(int j = 1;j <= n; j++) {
            if(p.charAt(j - 1) == '*') {
                dp[0][j] = dp[0][j - 2];
            }
        }
        // 其余部分的状态偏移
        for(int i = 1;i <= m; i++) {
            for(int j = 1;j <= n; j++) {
                if(p.charAt(j - 1) == '*') {
                    if(matches(s.charAt(i - 1),p.charAt(j - 2))) {
                        dp[i][j] = dp[i - 1][j] || dp[i][j - 2];
                    } else {
                        dp[i][j] = dp[i][j - 2];
                    }
                } else {
                    if(matches(s.charAt(i - 1),p.charAt(j - 1))) {
                        dp[i][j] = dp[i - 1][j - 1];
                    }
                }
            }
        }
        return dp[m][n];
    }

    public boolean matches(char a,char b) {
        if(b == '.') {
            return true;
        } else {
            return a == b;
        }
    }
}
```



# 复盘



> 很多东西不是我们**认为**他是他们他就是怎样的，一切都要以**实际结果**为主。

> 即使你认为再**理所当然**的东西，脱离了实际都将不复存在。



