---
title: Java反射真的很耗时吗?
date: 2023-04-16 14:39:37
tags:
- java
---



# Reflection



> 自我学习Java起，带领我学习Java的学长都是会提醒我们——Java反射很耗时。

> 所以是真的很耗时吗？

> 不妨来测试一下

```java
package com.example.reflect;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

public class Test {

    public static void main(String[] args) throws NoSuchMethodException, InvocationTargetException, InstantiationException, IllegalAccessException, InterruptedException {

        Class<ReflectionTest> clz = ReflectionTest.class;
        Method a = clz.getDeclaredMethod("a");
        a.setAccessible(true);
        ReflectionTest test = new ReflectionTest();


        long relectionTime = measure(() -> {
            for (int i = 0; i < Integer.MAX_VALUE; i++) {
                try {
                    a.invoke(test);
                } catch (IllegalAccessException e) {
                    throw new RuntimeException(e);
                } catch (InvocationTargetException e) {
                    throw new RuntimeException(e);
                }
            }
        });

        System.out.println("反射耗时：");
        System.out.println("总耗时：" + relectionTime);
        System.out.println("单次耗时：" + relectionTime * 1.0 / Integer.MAX_VALUE);

        long invoke = measure(() -> {
            for (int i = 0; i < Integer.MAX_VALUE; i++) {
                try {
                    a.invoke(test);
                } catch (IllegalAccessException e) {
                    throw new RuntimeException(e);
                } catch (InvocationTargetException e) {
                    throw new RuntimeException(e);
                }
            }
        });

        System.out.println("直接调用");
        System.out.println("总耗时：" + invoke);
        System.out.println("单次耗时：" + invoke * 1.0 / Integer.MAX_VALUE);


        Thread.sleep(Long.MAX_VALUE);


    }

    public static long measure(Runnable r) {
        long begin = System.currentTimeMillis();
        r.run();
        return System.currentTimeMillis() - begin;
    }

}


class ReflectionTest {
    private void a() {
        int b = 1 + 1;
    }

    public void b() {
        int a = 1 + 1;
    }

}
```



> 执行结果

> 反射耗时：
> 总耗时：9613
> 单次耗时：4.476401956973785E-6
>
> 直接调用
> 总耗时：9731
> 单次耗时：4.531349988901685E-6

> 多次测试可以发现，反射和直接调用的耗时很接近。



## 原因分析



> 为什么反射调用没有那么耗时？这点得从invoke开始看起

```java
public Object invoke(Object obj, Object... args)
    throws IllegalAccessException, IllegalArgumentException,
       InvocationTargetException
{
    if (!override) {
        Class<?> caller = Reflection.getCallerClass();
        checkAccess(caller, clazz,
                    Modifier.isStatic(modifiers) ? null : obj.getClass(),
                    modifiers);
    }
    MethodAccessor ma = methodAccessor;             // read volatile
    if (ma == null) {
        // 获取访问器
        ma = acquireMethodAccessor();
    }
    return ma.invoke(obj, args);
}
```



### acquireMethodAccessor

> invoke内部使用了代理，先生成一个Accessor代理对象，然后调用代理对象执行代码

```java
private MethodAccessor acquireMethodAccessor() {
    // First check to see if one has been created yet, and take it
    // if so
    MethodAccessor tmp = null;
    if (root != null) tmp = root.getMethodAccessor();
    if (tmp != null) {
        methodAccessor = tmp;
    } else {
        // 创建accessor
        tmp = reflectionFactory.newMethodAccessor(this);
        setMethodAccessor(tmp);
    }

    return tmp;
}
```



### newMethodAccessor

```java
public MethodAccessor newMethodAccessor(Method method) {
    checkInitted();

    if (Reflection.isCallerSensitive(method)) {
        Method altMethod = findMethodForReflection(method);
        if (altMethod != null) {
            method = altMethod;
        }
    }

    // use the root Method that will not cache caller class
    Method root = langReflectAccess.getRoot(method);
    if (root != null) {
        method = root;
    }

    // 如果不使用反射，则通过asm生成accessor
    if (noInflation && !ReflectUtil.isVMAnonymousClass(method.getDeclaringClass())) {
        return new MethodAccessorGenerator().
            generateMethod(method.getDeclaringClass(),
                           method.getName(),
                           method.getParameterTypes(),
                           method.getReturnType(),
                           method.getExceptionTypes(),
                           method.getModifiers());
    } else {
        // 如果使用反射则生成两个代理对象，依此对invoke进行代理
        // DelegatingMethodAccessorImpl -> NativeMethodAccessorImpl
        NativeMethodAccessorImpl acc =
            new NativeMethodAccessorImpl(method);
        DelegatingMethodAccessorImpl res =
            new DelegatingMethodAccessorImpl(acc);
        acc.setParent(res);
        return res;
    }
}
```



### DelegatingMethodAccessorImpl

> 使用代理模式直接代理

```java
class DelegatingMethodAccessorImpl extends MethodAccessorImpl {
    private MethodAccessorImpl delegate;

    DelegatingMethodAccessorImpl(MethodAccessorImpl delegate) {
        setDelegate(delegate);
    }

    public Object invoke(Object obj, Object[] args)
        throws IllegalArgumentException, InvocationTargetException
    {
        return delegate.invoke(obj, args);
    }

    void setDelegate(MethodAccessorImpl delegate) {
        this.delegate = delegate;
    }
}
```





### NativeMethodAccessorImpl

```java
class NativeMethodAccessorImpl extends MethodAccessorImpl {
    private final Method method;
    private DelegatingMethodAccessorImpl parent;
    private int numInvocations;

    NativeMethodAccessorImpl(Method method) {
        this.method = method;
    }

    public Object invoke(Object obj, Object[] args)
        throws IllegalArgumentException, InvocationTargetException
    {
        // 判断invoke次数，如果超过了上限 （15次）
        if (++numInvocations > ReflectionFactory.inflationThreshold()
                && !ReflectUtil.isVMAnonymousClass(method.getDeclaringClass())) {
            // 通过ASM生成class文件
            MethodAccessorImpl acc = (MethodAccessorImpl)
                new MethodAccessorGenerator().
                    generateMethod(method.getDeclaringClass(),
                                   method.getName(),
                                   method.getParameterTypes(),
                                   method.getReturnType(),
                                   method.getExceptionTypes(),
                                   method.getModifiers());
            // 替换代理
            parent.setDelegate(acc);
        }
			// 通过jni访问class文件
        return invoke0(method, obj, args);
    }

    void setParent(DelegatingMethodAccessorImpl parent) {
        this.parent = parent;
    }

    private static native Object invoke0(Method m, Object obj, Object[] args);
}
```



### generate



> 生成class字节码并定义

```java
private MagicAccessorImpl generate(final Class<?> declaringClass,
                                   String name,
                                   Class<?>[] parameterTypes,
                                   Class<?>   returnType,
                                   Class<?>[] checkedExceptions,
                                   int modifiers,
                                   boolean isConstructor,
                                   boolean forSerialization,
                                   Class<?> serializationTargetClass)
{
    ByteVector vec = ByteVectorFactory.create();
    asm = new ClassFileAssembler(vec);
    this.declaringClass = declaringClass;
    this.parameterTypes = parameterTypes;
    this.returnType = returnType;
    this.modifiers = modifiers;
    this.isConstructor = isConstructor;
    this.forSerialization = forSerialization;

    asm.emitMagicAndVersion();

    // Constant pool entries:
    // ( * = Boxing information: optional)
    // (+  = Shared entries provided by AccessorGenerator)
    // (^  = Only present if generating SerializationConstructorAccessor)
    //     [UTF-8] [This class's name]
    //     [CONSTANT_Class_info] for above
    //     [UTF-8] "jdk/internal/reflect/{MethodAccessorImpl,ConstructorAccessorImpl,SerializationConstructorAccessorImpl}"
    //     [CONSTANT_Class_info] for above
    //     [UTF-8] [Target class's name]
    //     [CONSTANT_Class_info] for above
    // ^   [UTF-8] [Serialization: Class's name in which to invoke constructor]
    // ^   [CONSTANT_Class_info] for above
    //     [UTF-8] target method or constructor name
    //     [UTF-8] target method or constructor signature
    //     [CONSTANT_NameAndType_info] for above
    //     [CONSTANT_Methodref_info or CONSTANT_InterfaceMethodref_info] for target method
    //     [UTF-8] "invoke" or "newInstance"
    //     [UTF-8] invoke or newInstance descriptor
    //     [UTF-8] descriptor for type of non-primitive parameter 1
    //     [CONSTANT_Class_info] for type of non-primitive parameter 1
    //     ...
    //     [UTF-8] descriptor for type of non-primitive parameter n
    //     [CONSTANT_Class_info] for type of non-primitive parameter n
    // +   [UTF-8] "java/lang/Exception"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "java/lang/ClassCastException"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "java/lang/NullPointerException"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "java/lang/IllegalArgumentException"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "java/lang/InvocationTargetException"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "<init>"
    // +   [UTF-8] "()V"
    // +   [CONSTANT_NameAndType_info] for above
    // +   [CONSTANT_Methodref_info] for NullPointerException's constructor
    // +   [CONSTANT_Methodref_info] for IllegalArgumentException's constructor
    // +   [UTF-8] "(Ljava/lang/String;)V"
    // +   [CONSTANT_NameAndType_info] for "<init>(Ljava/lang/String;)V"
    // +   [CONSTANT_Methodref_info] for IllegalArgumentException's constructor taking a String
    // +   [UTF-8] "(Ljava/lang/Throwable;)V"
    // +   [CONSTANT_NameAndType_info] for "<init>(Ljava/lang/Throwable;)V"
    // +   [CONSTANT_Methodref_info] for InvocationTargetException's constructor
    // +   [CONSTANT_Methodref_info] for "super()"
    // +   [UTF-8] "java/lang/Object"
    // +   [CONSTANT_Class_info] for above
    // +   [UTF-8] "toString"
    // +   [UTF-8] "()Ljava/lang/String;"
    // +   [CONSTANT_NameAndType_info] for "toString()Ljava/lang/String;"
    // +   [CONSTANT_Methodref_info] for Object's toString method
    // +   [UTF-8] "Code"
    // +   [UTF-8] "Exceptions"
    //  *  [UTF-8] "java/lang/Boolean"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(Z)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "booleanValue"
    //  *  [UTF-8] "()Z"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Byte"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(B)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "byteValue"
    //  *  [UTF-8] "()B"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Character"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(C)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "charValue"
    //  *  [UTF-8] "()C"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Double"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(D)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "doubleValue"
    //  *  [UTF-8] "()D"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Float"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(F)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "floatValue"
    //  *  [UTF-8] "()F"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Integer"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(I)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "intValue"
    //  *  [UTF-8] "()I"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Long"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(J)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "longValue"
    //  *  [UTF-8] "()J"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "java/lang/Short"
    //  *  [CONSTANT_Class_info] for above
    //  *  [UTF-8] "(S)V"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above
    //  *  [UTF-8] "shortValue"
    //  *  [UTF-8] "()S"
    //  *  [CONSTANT_NameAndType_info] for above
    //  *  [CONSTANT_Methodref_info] for above

    short numCPEntries = NUM_BASE_CPOOL_ENTRIES + NUM_COMMON_CPOOL_ENTRIES;
    boolean usesPrimitives = usesPrimitiveTypes();
    if (usesPrimitives) {
        numCPEntries += NUM_BOXING_CPOOL_ENTRIES;
    }
    if (forSerialization) {
        numCPEntries += NUM_SERIALIZATION_CPOOL_ENTRIES;
    }

    // Add in variable-length number of entries to be able to describe
    // non-primitive parameter types and checked exceptions.
    numCPEntries += (short) (2 * numNonPrimitiveParameterTypes());

    asm.emitShort(add(numCPEntries, S1));

    final String generatedName = generateName(isConstructor, forSerialization);
    asm.emitConstantPoolUTF8(generatedName);
    asm.emitConstantPoolClass(asm.cpi());
    thisClass = asm.cpi();
    if (isConstructor) {
        if (forSerialization) {
            asm.emitConstantPoolUTF8
                ("jdk/internal/reflect/SerializationConstructorAccessorImpl");
        } else {
            asm.emitConstantPoolUTF8("jdk/internal/reflect/ConstructorAccessorImpl");
        }
    } else {
        asm.emitConstantPoolUTF8("jdk/internal/reflect/MethodAccessorImpl");
    }
    asm.emitConstantPoolClass(asm.cpi());
    superClass = asm.cpi();
    asm.emitConstantPoolUTF8(getClassName(declaringClass, false));
    asm.emitConstantPoolClass(asm.cpi());
    targetClass = asm.cpi();
    short serializationTargetClassIdx = (short) 0;
    if (forSerialization) {
        asm.emitConstantPoolUTF8(getClassName(serializationTargetClass, false));
        asm.emitConstantPoolClass(asm.cpi());
        serializationTargetClassIdx = asm.cpi();
    }
    asm.emitConstantPoolUTF8(name);
    asm.emitConstantPoolUTF8(buildInternalSignature());
    asm.emitConstantPoolNameAndType(sub(asm.cpi(), S1), asm.cpi());
    if (isInterface()) {
        asm.emitConstantPoolInterfaceMethodref(targetClass, asm.cpi());
    } else {
        if (forSerialization) {
            asm.emitConstantPoolMethodref(serializationTargetClassIdx, asm.cpi());
        } else {
            asm.emitConstantPoolMethodref(targetClass, asm.cpi());
        }
    }
    targetMethodRef = asm.cpi();
    if (isConstructor) {
        asm.emitConstantPoolUTF8("newInstance");
    } else {
        asm.emitConstantPoolUTF8("invoke");
    }
    invokeIdx = asm.cpi();
    if (isConstructor) {
        asm.emitConstantPoolUTF8("([Ljava/lang/Object;)Ljava/lang/Object;");
    } else {
        asm.emitConstantPoolUTF8
            ("(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;");
    }
    invokeDescriptorIdx = asm.cpi();

    // Output class information for non-primitive parameter types
    nonPrimitiveParametersBaseIdx = add(asm.cpi(), S2);
    for (int i = 0; i < parameterTypes.length; i++) {
        Class<?> c = parameterTypes[i];
        if (!isPrimitive(c)) {
            asm.emitConstantPoolUTF8(getClassName(c, false));
            asm.emitConstantPoolClass(asm.cpi());
        }
    }

    // Entries common to FieldAccessor, MethodAccessor and ConstructorAccessor
    emitCommonConstantPoolEntries();

    // Boxing entries
    if (usesPrimitives) {
        emitBoxingContantPoolEntries();
    }

    if (asm.cpi() != numCPEntries) {
        throw new InternalError("Adjust this code (cpi = " + asm.cpi() +
                                ", numCPEntries = " + numCPEntries + ")");
    }

    // Access flags
    asm.emitShort(ACC_PUBLIC);

    // This class
    asm.emitShort(thisClass);

    // Superclass
    asm.emitShort(superClass);

    // Interfaces count and interfaces
    asm.emitShort(S0);

    // Fields count and fields
    asm.emitShort(S0);

    // Methods count and methods
    asm.emitShort(NUM_METHODS);

    emitConstructor();
    emitInvoke();

    // Additional attributes (none)
    asm.emitShort(S0);

    // Load class
    vec.trim();
    final byte[] bytes = vec.getData();
    // Note: the class loader is the only thing that really matters
    // here -- it's important to get the generated code into the
    // same namespace as the target class. Since the generated code
    // is privileged anyway, the protection domain probably doesn't
    // matter.
    return AccessController.doPrivileged(
        new PrivilegedAction<MagicAccessorImpl>() {
            @SuppressWarnings("deprecation") // Class.newInstance
            public MagicAccessorImpl run() {
                    try {
                    return (MagicAccessorImpl)
                    ClassDefiner.defineClass
                            (generatedName,
                             bytes,
                             0,
                             bytes.length,
                             declaringClass.getClassLoader()).newInstance();
                    } catch (InstantiationException | IllegalAccessException e) {
                        throw new InternalError(e);
                    }
                }
            });
}
```



### 小结



> 反射不是每次都会通过jni进行invoke，当调用到达一定上限（15次）的时候会进行asm字节码生成，从而提升执行效率。



## 字节码



> 分析到了会通过asm生成字节码，生成的字节码长什么样子呢？

> 接着使用Alibaba的[Arthas](https://arthas.aliyun.com/doc/)框架[dump](https://arthas.aliyun.com/doc/dump.html)字节码查看class信息





> 如下是生成class字节码的名称

```java
private static synchronized String generateName(boolean isConstructor,
                                                boolean forSerialization)
{
    // 对构造方法进行代理
    if (isConstructor) {
        // 序列化
        if (forSerialization) {
            int num = ++serializationConstructorSymnum;
            return "jdk/internal/reflect/GeneratedSerializationConstructorAccessor" + num;
        } else {
            int num = ++constructorSymnum;
            return "jdk/internal/reflect/GeneratedConstructorAccessor" + num;
        }
    } else {
        // 常规方法
        int num = ++methodSymnum;
        return "jdk/internal/reflect/GeneratedMethodAccessor" + num;
    }
}
```





- 查看需要进行attach的进程

![image-20230416151251359](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230416151251359.png)

- 使用arthas进行attach

> 对于jdk 9.0以上由于没有tools.jar需要ignore-tools

![image-20230416151331463](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230416151331463.png)

> attach成功

![image-20230416151429660](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230416151429660.png)



- dump字节码



![image-20230416151530432](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230416151530432.png)



- 得到字节码

> 可以发现生成的字节码忽视了private修饰，直接调用a方法

```java
//
// Source code recreated from a .class file by IntelliJ IDEA
// (powered by FernFlower decompiler)
//

package jdk.internal.reflect;

import com.example.reflect.ReflectionTest;
import java.lang.reflect.InvocationTargetException;

public class GeneratedMethodAccessor1 extends MethodAccessorImpl {
    public Object invoke(Object var1, Object[] var2) throws InvocationTargetException {
        if (var1 == null) {
            throw new NullPointerException();
        } else {
            ReflectionTest var10000;
            try {
                var10000 = (ReflectionTest)var1;
                if (var2 != null && var2.length != 0) {
                    throw new IllegalArgumentException();
                }
            } catch (NullPointerException | ClassCastException var4) {
                throw new IllegalArgumentException(var4.toString());
            }

            try {
                var10000.a();
                return null;
            } catch (Throwable var3) {
                throw new InvocationTargetException(var3);
            }
        }
    }

    public GeneratedMethodAccessor1() {
    }
}
```



## 最后



- Java反射确实是耗时的，但是指的是反射的准备过程耗时，即获取constructor，setAccessible耗时
- invoke0确实也耗费时间，但是由于jdk内部有通过asm生成字节码，所以在频繁调用的情况下并不耗时。
