---
title: ASM基础使用
date: 2023-07-20 23:44:34
tags:
- asm
- aop
- java
---



# ASM



##  Core Api





### ClassVisitor



```
visit

[visitSource]

[visitModule]

[visitNestHost]

[visitOuterClass]

(visitAnnotation|visitTypeAnnotation|visitAttribute)*

(visitNestMember|[*visitPermittedSubclass]|visitInnerClass|visitRecordComponent|visitField|visitMethod)*

visitEnd
```





#### visit



> 标记ClassVisitor开始

```kotlin
override fun visit(
    version: Int, // 字节码版本号
    access: Int, // 访问修饰符
    name: String, // 类名称
    signature: String?, // 泛型签名
    superName: String, // 父类
    interfaces: Array<out String> // 实现的接口
) 
```





#### visitSource



> 访问类的源代码相关的属性

```java
override fun visitSource(source: String, // 源代码 
                         debug: String? // debug信息) 
```



#### visitModule







#### visitNestHost



> 访问外部host。
>
> 每个类文件有一个host，除host外的类都是嵌套类。
>
> visitNestHost所做的也就是访问嵌套类的host



> 如下：
>
> A为host，B、C、D为嵌套类（所以B、C、D、E、Runnable匿名类的visitHost的结果为A的全类名）

```java
public class A {

    public static class B {

        public static class C {

            public static class D {

                public static void d() {
                    class E {

                    }

                    new Runnable() {
                        @Override
                        public void run() {
                            System.out.println("Hello world");
                        }
                    }.run();
                }

            }
        }

    }
}
```



```kotlin
val a = A::class.java.name
val b = A.B::class.java.name
val c = A.B.C::class.java.name
val d = A.B.C.D::class.java.name
val an = "com.example.asm.clz.A\$B\$C\$D\$1"
val tempClass = "com.example.asm.clz.A\$B\$C\$D\$1E"


val cr = ClassReader(a)
cr.accept(cv, 0)
```



#### visitOuterClass

> 访问匿名类和局部内部类的外部类



```kotlin
override fun visitOuterClass(
    owner: String,  // 外部类引用
    name: String,  // 外部方法名
    descriptor: String // 方法签名
)
```



```kotlin
fun testVisitOuterClass() {

    withVisitor {
        val an = "com.example.asm.clz.A\$B\$C\$D\$1"
        val tempClass = "com.example.asm.clz.A\$B\$C\$D\$1E"
        tempClass
    }

}
```





#### visitAnnotation



> 访问类的注解

```kotlin
override fun visitAnnotation(
    descriptor: String,  // annotation Class的描述符
    visible: Boolean // 是否在运行时可见
): AnnotationVisitor // 用于对注解进行访问的visitor（asm会调用返回的对象对所在注解进行访问）
```



#### visitTypeAnnotation



> 访问类的类类型注解

```kotlin
override fun visitTypeAnnotation(
    typeRef: Int, // 当前类型注解的类型（对应TypeReference内的静态成员）
    typePath: TypePath?, // 当前注解的路径
    descriptor: String?, // 当前注解的描述符
    visible: Boolean // 当前注解是否可见
): AnnotationVisitor 
```



#### visitAttribute



> 我得到的结论是标准的属性没法触发，也就是说用于扩展性的visit自定义的属性，



> 另外谁会闲的没事去使用visitAttribute。这么难用，当然是使用visitXXX api会更好

```kotlin
override fun visitAttribute(attribute: Attribute) 
```



####  visitNestMember



> 用于访问一个类的内部类（匿名，局部也包含在内)



```kotlin
override fun visitNestMember(nestMember: String) {
    super.visitNestMember(nestMember)
    withLog("visitNestMember") {

        println("nestMember:$nestMember")

    }
}
```



```kotlin
fun visitNestMember() {

    withVisitor {

        VisitNestMemberTest::class.java.name

    }

}


public class VisitNestMemberTest {

    class A {
        class C {

        }
    }

    static class B {
        class D {

        }

        static class E {

            void main() {
                class F {

                }
            }

        }
    }

}

```





#### visitPermittedSubclass



> 这个方法是用于适配Jdk 17的一个新特性——[sealed class](https://openjdk.org/jeps/409)



> 用于拜访所有sealed class的permitted class

> 如果ClassVisitor的对象是VisitPermittedSubClassTest则会对TestA, TestB, TestC进行访问

```java
public sealed class VisitPermittedSubClassTest permits TestA, TestB, TestC {
}

public final class TestA extends VisitPermittedSubClassTest{

}

public final class TestB extends VisitPermittedSubClassTest {

}

public final class TestC extends VisitPermittedSubClassTest {

}
```



```kotlin
override fun visitPermittedSubclass(
    permittedSubclass: String? // permitted class 类名
)
```



#### visitInnerClass



> 访问内部类的信息

```kotlin
fun visitInnerClass() {

    withVisitor {

        VisitInnerClassTest::class.java.name

    }

}
```



> VisitInnerClassTest的内部类
>
> VisitInnerClassTest$A , VisitInnerClassTest$A$B , VisitInnerClassTest$B , VisitInnerClassTest$B$A
>
> 将被访问

```java
public class VisitInnerClassTest {

    public class A {

        public class B {

        }

    }

    public class B {
        public class A {

        }
    }

}
```



```kotlin
override fun visitInnerClass(
    name: String?, // 内部类的全类名
    outerName: String?, // 外部类的全类名
    innerName: String?, // 内部类的名称
    access: Int // 访问修饰符
)
```



#### visitRecordComponent



> 访问record class的成员



```java
public record VisitRecordComponentTest(
        int id, String name, int age
) {

}
```



```kotlin
override fun visitRecordComponent(
    name: String?, // component名称
    descriptor: String?, // component修饰符
    signature: String? // component签名（如果泛型的话）
): RecordComponentVisitor? // 用于继续访问component
```



> name:id
> descriptor:I
> signature:null
>
> 
>
> name:name
> descriptor:Ljava/lang/String;
> signature:null
>
> 
>
> name:age
> descriptor:I
> signature:null



#### visitField

> 访问类属性



```kotlin
override fun visitField(
    access: Int, // 访问修饰符
    name: String?, // 属性名
    descriptor: String?, // 属性描述符
    signature: String?, // 签名
    value: Any? // 默认值（static final常量值）
): FieldVisitor? // 用于进一步访问属性
```



#### visitMethod

> 访问方法



```kotlin
override fun visitMethod(
    access: Int, // 方法修饰符
    name: String?, // 方法名
    descriptor: String?, // 描述符
    signature: String?, // 签名
    exceptions: Array<out String>? // 异常抛出
): MethodVisitor?  // 进一步visit方法
```





#### visitEnd



> 对于类的访问结束标记

```kotlin
override fun visitEnd()
```



### ModuleVisitor





### AnnotationVisitor





### RecordComponentVisitor



### FieldVisitor

> 访问顺序
>
> ( visitAnnotation | visitTypeAnnotation | visitAttribute )* visitEnd.



#### visitAnnotation

同[ClassVisitor.visitAnnotation](#visitAnnotation)



#### visitTypeAnnotation



同[ClassVisitor.visitTypeAnnotation](#visitTypeAnnotation)





#### visitAttribute

 同[ClassVisitor.visitAtribute](#visitAttribute)



#### visitEnd

> 标记FieldVisitor的结束







### MethodVisitor



> 访问顺序



> ( visitParameter )* 
>
> [ visitAnnotationDefault ] 
>
> ( visitAnnotation | visitAnnotableParameterCount | visitParameterAnnotation | visitTypeAnnotation | visitAttribute )* 
>
> [ visitCode 
>
> ( visitFrame | visit<i>X</i>Insn | visitLabel | visitInsnAnnotation | visitTryCatchBlock | visitTryCatchAnnotation | visitLocalVariable | visitLocalVariableAnnotation | visitLineNumber )*
>
> visitMaxs ] 
> visitEnd



#### visitParameter



> 用于访问方法的参数信息
>
> Note：由于这个方法是visit的debug信息段，需要在编译的时候加入-parameters参数
>
> 对于gradle进行如下配置
>
> ```groovy
> tasks.compileJava {
>     options.compilerArgs += "-parameters"
> }
> ```



```kotlin
override fun visitParameter(name: String?, // 参数名 
                            access: Int // 访问修饰符)
```



对于如下方法会依此返回

> name:a
> access:0
>
> name:b
> access:0
>
> name:c
> access:0

```java
public void a(int a, String b, List<String> c,long d) {}
```



#### visitAnnotationDefault



> 访问注解类中方法的default值

```kotlin
override fun visitAnnotationDefault(): AnnotationVisitor // 用于进一步访问注解
```



如下注解

> 在调用visitAnnotationDefault后会调用AnnotationVisitor的visit方法

> name:null
> value:1
>
> name:null
> value:Default

```java
public @interface VisitDefaultMethod {

    int a() default 1;

    String b() default "Default";

}
```







#### visitAnnotation



同[ClassVisitor.visitAnnotation](#visitAnnotation)



#### visitTypeAnnotation



同[ClassVisitor.visitTypeAnnotation](#visitTypeAnnotation)



#### visitAnnotableParameterCount



> 访问方法参数被注解标记的次数
>
> 如：
>
> ```java
> @Retention(RetentionPolicy.RUNTIME)
> @Target({ElementType.PARAMETER})
> public @interface TypeCountAnno {
> }
> ```
>
> ```java
> public void t1(@TypeCountAnno String a) {
> 
> }
> ```



> 虽然我也不不知道他存在的意义是什么。
>
> 标记了注解才能被访问，而且只是给可能会被标记的参数个数。
>
> 感觉比较鸡肋的。



```kotlin
override fun visitAnnotableParameterCount(
	parameterCount: Int, // 可能会被注解标注的类的个数 
	visible: Boolean // 注解的可见性
)
```







#### visitParameterAnnotation



> 访问所有被标记的方法参数的注解

```kotlin
override fun visitParameterAnnotation(
    parameter: Int, // 参数在参数列表中的位置
    descriptor: String?, // 参数的描述符
    visible: Boolean // 注解是否运行时可见
): AnnotationVisitor?  // 进一步visit注解
```

如

```java
public class VisitParamAnnTest {

    public void visitAnno(@ParamAnn1 boolean a, @ParamAnn2 byte b,@ParamAnn3 short c) {

    }

}
```



会依此调用visitParameterAnnotation

> parameter:0
> descriptor:Lcom/example/asm/annotation/anno/ParamAnn1;
> visible:true
>
> parameter:1
> descriptor:Lcom/example/asm/annotation/anno/ParamAnn2;
> visible:true
>
> parameter:2
> descriptor:Lcom/example/asm/annotation/anno/ParamAnn3;
> visible:true



#### visitAttribute



同[ClassVisitor.visitAttribute](#visitAttribute)





#### visitCode



> 表明开始对code进行处理操作

```kotlin
override fun visitCode()
```



#### visitFrame ToDo



> 用来访问局部变量表和栈的



//TODO



#### visitInsn



> 访问java中的单操作指令字节码

```
NOP, // 空指令

ACONST_NULL, ICONST_M1, ICONST_0, ICONST_1, ICONST_2, ICONST_3, ICONST_4, ICONST_5,

LCONST_0, LCONST_1, FCONST_0, FCONST_1, FCONST_2, DCONST_0, DCONST_1, // 将常量虚拟机栈，



IALOAD, LALOAD,FALOAD, DALOAD, AALOAD, BALOAD, CALOAD, SALOAD, IASTORE, LASTORE, FASTORE, DASTORE,
AASTORE, BASTORE, CASTORE, SASTORE,  // 对数组进行get/set

POP, POP2, DUP, DUP_X1, DUP_X2, DUP2, DUP2_X1, DUP2_X2,SWAP // 操作数栈操作指令


IADD, LADD, FADD, DADD, ISUB, LSUB, FSUB, DSUB, IMUL, LMUL, FMUL, DMUL, IDIV, LDIV,
FDIV, DDIV, IREM, LREM, FREM, DREM, INEG, LNEG, FNEG, DNEG, ISHL, LSHL, ISHR, LSHR, IUSHR,
LUSHR, IAND, LAND, IOR, LOR, IXOR, LXOR,  // 操作数栈运算指令

I2L, I2F, I2D, L2I, L2F, L2D, F2I, F2L, F2D, D2I,D2L, D2F, I2B, I2C, I2S,  // 转换指令

LCMP, FCMPL, FCMPG, DCMPL, DCMPG,  // 比较指令

IRETURN, LRETURN, FRETURN,DRETURN, ARETURN, RETURN,  // return指令

ARRAYLENGTH,  // 获取arr的长度

ATHROW,  // 异常抛出

MONITORENTER, or MONITOREXIT. // synchronized指令
```



> 当上方指令被调用的时候就会调用如下方法

```kotlin
override fun visitInsn(
    opcode: Int // 指令码
) 
```



#### visitIntsn

> 访问单操作数指令

```
BIPUSH, // 入栈一个byte
SIPUSH, // 入栈一个short
NEWARRAY // new一个数组，这里需要一个int类型的type表明new的是什么
```



```kotlin
public void visitIntInsn(
    final int opcode,  // 操作数指令
    final int operand // 操作数
)
```





#### visitVarInsn



> 拜访局部指令（即load store指令）

```
ILOAD, LLOAD, FLOAD, DLOAD, ALOAD
ISTORE, LSTORE, FSTORE, DSTORE, ASTORE
RET
```



```kotlin
override fun visitVarInsn(
    opcode: Int,  // 具体指令
    varIndex: Int // 局部变量表位置
)
```



#### visitTypeInsn



> 访问“类型指令”

```plainText
NEW,
ANEWARRAY, // 创建数组
CHECKCAST, // 类型强转
INSTANCEOF // 访问instance指令
```



```kotlin
override fun visitTypeInsn(
    opcode: Int, // 类型指令
    type: String? // 类型指令所操作的类型是什么。
)
```



#### visitFieldInsn

> 访问“属性相关指令”

```
// 获取&设置 static属性
GETSTATIC, 
PUTSTATIC, 
// 获取&设置成员属性
GETFIELD,
PUTFIELD
```



```kotlin
override fun visitFieldInsn(
    opcode: Int, // 指令 
    owner: String?, // field对应class的internal name
    name: String?,  // field名称
    descriptor: String? // field描述符
)
```



#### visitMethodInsn

> 同上，访问”Method相关指令“

```plainText
INVOKEVIRTUAL, 
INVOKESPECIAL, 
INVOKESTATIC,
INVOKEINTERFACE
```



```kotlin
override fun visitMethodInsn(
    opcode: Int, // 指令
    owner: String?, // method对应
    name: String?, // 方法名
    descriptor: String?, // 方法描述符
    isInterface: Boolean // 是否是接口
)
```



#### visitInvokeDynamicInsn

> 访问invokeDynamic指令

```kotlin
override fun visitInvokeDynamicInsn(
    name: String?, // 方法名称
    descriptor: String?, // 方法描述符
    bootstrapMethodHandle: Handle?, // 方法handle
    vararg bootstrapMethodArguments: Any? // 方法名称
)
```



#### visitJumpInsn

> 访问和跳转相关的指令

```plaintText
IFEQ, IFNE, IFLT, IFGE, IFGT, IFLE, // 栈顶元素和0对比，满足则跳转
IF_ICMPEQ, IF_ICMPNE, IF_ICMPLT, IF_ICMPGE, IF_ICMPGT,IF_ICMPLE, // 比较栈顶两个元素，
IF_ACMPEQ, IF_ACMPNE, // 判断引用是否相等
GOTO, // 无条件跳转
JSR,  // 
IFNULL or IFNONNULL // 判断实例是否是null
```

```kotlin
override fun visitJumpInsn(
    opcode: Int, // 跳转指令 
    label: Label? // 跳转位置对应指令
)
```



#### visitLabel

访问Label

```kotlin
override fun visitLabel(label: Label?)
```





#### visitLdcInsn

> 访问LDC指令

```kotlin
override fun visitLdcInsn(
    value: Any? // 具体的常量值
)
```



#### visitIincInsn



> 访问累加iinc指令即 i += 2这类。

```kotlin
override fun visitIincInsn(
    varIndex: Int, // 操作局部变量的index下标 
	increment: Int // 累计次数
)
```



#### visitTableSwitchInsn

> 访问tableswitch指令

```kotlin
override fun visitTableSwitchInsn(
    min: Int,  // switch key最小值
    max: Int,  // switch key最大值
    dflt: Label?, // default label
    vararg labels: Label? // 所有分支的label
)
```



#### visitLookupSwitchInsn

> 访问lookupswitch指令

```kotlin
override fun visitLookupSwitchInsn(
    dflt: Label?,  // default分支label
    keys: IntArray?,  // key列表
    labels: Array<out Label>? // 其他分支label
)
```



#### visitMultiANewArrayInsn

> 访问多维数组指令MULTIANEWARRAY指令

```kotlin
override fun visitMultiANewArrayInsn(
    descriptor: String?, // 描述符
    numDimensions: Int   // 维度数
)
```



#### visitInsnAnnotation

> 访问annotation指令

> 如下

```java
VisitInsnAnnotationTest i = new @AnnotationTest VisitInsnAnnotationTest();
```

```kotlin
override fun visitInsnAnnotation(
    typeRef: Int, // 类型引用
    typePath: TypePath?, // 类型路径
    descriptor: String?, // 描述符
    visible: Boolean // 是否可见
): AnnotationVisitor?
```



#### visitTryCatchBlock

> 访问try catch代码块

```kotlin
override fun visitTryCatchBlock(
    start: Label?, // 开始位置
    end: Label?,  // 结束位置
    handler: Label?, // handler位置
    type: String? // catch类型
) 
```



#### visitTryCatchAnnotation

> 访问handler对应exception类型的annotation

> 如下

```java
public class VisitTryCatchAnnotationTest {

    public static void a() {
        try {
            int a = 1/0;
        } catch (@AnnotationTest Exception e) {

        }
    }

}
```

```kotlin
override fun visitTryCatchAnnotation(
    typeRef: Int, // type引用
    typePath: TypePath?, // type路径
    descriptor: String?, // annotation描述符
    visible: Boolean // 是否可见
): AnnotationVisitor?
```



#### visitLocalVariable

> 访问局部变量

```kotlin
override fun visitLocalVariable(
    name: String?, // 变量名
    descriptor: String?, // 变量描述符
    signature: String?, // 变量签名,泛型签名
    start: Label?, // 开始位置
    end: Label?, // 结束位置
    index: Int // 局部变量表索引
) 
```



#### visitLocalVariableAnnotation

> 访问局部变量的注解

```java
public class VisitLocalVariableAnnotationTest {

    public void a() {
        @AnnotationTest
        int a  = 0;
    }

}
```

```kotlin
override fun visitLocalVariableAnnotation(
    typeRef: Int,
    typePath: TypePath?,
    start: Array<out Label>?,
    end: Array<out Label>?,
    index: IntArray?,
    descriptor: String?,
    visible: Boolean
): AnnotationVisitor?
```



#### visitLineNumber

> 访问代码行数

```kotlin
override fun visitLineNumber(
    line: Int, // 源代码行数 
    start: Label? // 开始label
)
```

#### visitMaxs

> 访问栈的最大内存&本地变量表的最大容量

```kotlin
override fun visitMaxs(
    maxStack: Int,  // 最大栈大小
    maxLocals: Int // 最大本地变量表内容
)
```

#### visitEnd

> 方法访问结束



## Tree Api















