---
title: Codelocator原理解析
tags:
- tool
- android
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogcodelocator.png
---

# CodeLocator原理解析



## 基础概念



> 什么是CodeLocator

请看[Github](https://github.com/bytedance/CodeLocator)



> 一句话来说——CodeLocator是字节研发的一款用于查看UI层级关系的一款“调试工具”



## 框架组成



![codelocator.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogcodelocator.drawio.png)



- CodeLocator Pluigin

> 此部分为Intelij Idea的插件，用于向App发取指令，呈现具体的UI层级关系。
>
> 如下图所示：
>
> ![image-20231218130429940](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231218130429940.png)

- CodeLocator App

> 此部分用于提供一部分功能
>
> 如：
>
> - Activity跳转
> - 触摸事件抓取
> - 跳转XML文件
> - ......



## 关于本文



主要对CodeLocator App部分的内容进行分析，梳理清实现原理。



# 实现原理



## 写在前面的话



> 最开始的时候，分析了一下CodeLocator.init方法。整个流程分析完了，都没有找到合适的切入点。



>  突然转念一想，我不知道内部是怎么work的，我用Android Profiler抓堆栈不就能找到具体的函数调用关系了吗。
>
> （我真是个天才）



> 抓取了下CodeLocator的基础功能——ViewTree/Activity/。
>
> 抓取结果如下

![image-20231218234331926](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231218234331926.png)



关于具体的分析

1. 展示当前的View视图
2. 展示当前的Activity信息
3. 展示当前所有Fragment的信息
4. 展示自定义的App运行时信息
5. 展示当前应用的文件信息
6. 实时编辑View的状态, 如可见性, 文本内容等
7. 定位当前响应触摸事件的View
8. 获取当前View绑定的数据
9. 获取当前View对应的绘制内容
10. 跳转View的点击事件代码, findViewById, ViewHolder的代码位置
11. 跳转View的xml布局文件
12. 跳转Toast, Dialog的显示代码位置
13. 跳转启动当前Activity的代码位置
14. 展示应用支持的所有Schema信息
15. 向应用发送指定Schema
16. 定位项目内最新的Apk文件
17. apk文件支持右键安装
18. 快速打开显示布局边界, 过渡绘制, 点按操作等
19. 快速连接Charles代理



## View视图抓取



1. Plugin发送广播

2. App接受广播处理

   a. 获取App信息

   b. 获取showInfo相关信息

   c. 获取Activity相关信息

   d. 获取Fragment相关信息

   e. 获取View相关信息

3. 转Json & Base64编码、发送结果



![codelocator-layoutinfo.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogcodelocator-layoutinfo.drawio.png)



> 广播处理分支

```java
@Override
    public void onReceive(Context context, Intent intent) {
        clearAsyncResult();
        if (intent == null || intent.getAction() == null) {
            return;
        }
        isMainThread = (Thread.currentThread() == Looper.getMainLooper().getThread());

        final SmartArgs smartArgs = new SmartArgs(intent);
        final boolean isAsync = smartArgs.getBoolean(KEY_ASYNC, false);
        AsyncBroadcastHelper.setEnableAsyncBroadcast(context, isAsync);

        switch (intent.getAction()) {
            case ACTION_DEBUG_LAYOUT_INFO:
                if (isMainThread) {
                  	// 具体实现
                    processGetLayoutAction(context, smartArgs);
                } else if (isAsync) {
                    CodeLocator.sHandler.post(() -> processGetLayoutAction(context, smartArgs));
                } else {
                    sendResult(context, smartArgs, new ErrorResponse(NOT_UI_THREAD));
                }
                break;
           // ......
        }
    }
```



> 进一步process

```kotlin
private void processGetLayoutAction(Context context, SmartArgs smartArgs) {
        try {
            // ......
            getTopActivityLayoutInfo(context, smartArgs);
        } catch (Throwable t) {
            // ......
        }
    }
```



> 核心方法

```java
private void getTopActivityLayoutInfo(Context context, SmartArgs smartArgs) {
  			// 获取顶层App 
        Activity activity = CodeLocator.getCurrentActivity();
        if (activity != null) {
          	// 获取参数
            long stopAnimTime = smartArgs.getLong(KEY_STOP_ALL_ANIM);
            boolean needColor = smartArgs.getBoolean(KEY_NEED_COLOR);
            boolean isAsync = smartArgs.getBoolean(KEY_ASYNC);
          	// 获取Activity信息
            final WApplication application = ActivityUtils.getActivityDebugInfo(activity, needColor, isMainThread);
            application.setIsMainThread(isMainThread);
            if (isAsync) {
                application.setHClassName(getHClassName());
            }
            if (stopAnimTime != 0) {
                try {
                    Thread.sleep(Long.valueOf(stopAnimTime));
                } catch (Throwable t) {
                    Log.d(CodeLocator.TAG, "CodeLocator stop anim 出现错误 " + Log.getStackTraceString(t));
                }
            }
          	// 发送信息
            sendResult(context, smartArgs, new ApplicationResponse(application));
        } else {
            sendResult(context, smartArgs, new ErrorResponse(NO_CURRENT_ACTIVITY));
        }
    }
```



### 消息抓取



从上面的分析过程中其实可以发现，抓取的消息分为5类

<img src="https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blogimage-20231219224958023.png" alt="image-20231219224958023" style="zoom:50%;" />



#### ApplicationInfo

```java
 private fun buildApplicationInfo(
        wApplication: WApplication,
        activity: Activity
    ) {
        wApplication.grabTime = System.currentTimeMillis() // 当前线程
        wApplication.className = activity.application.javaClass.name // Application名称
        wApplication.isIsDebug = isApkInDebug(activity) // android:debuggable
        wApplication.androidVersion = Build.VERSION.SDK_INT // sdkVersion
        wApplication.deviceInfo =
            Build.MANUFACTURER + "," + Build.PRODUCT + "," + Build.BRAND + "," + Build.MODEL + "," + Build.DEVICE // device name
        wApplication.density = activity.resources.displayMetrics.density // density
        wApplication.densityDpi = activity.resources.displayMetrics.densityDpi // densityDpi
        wApplication.packageName = activity.packageName // 包名
        wApplication.statusBarHeight =
            UIUtils.getStatusBarHeight(activity) // 状态栏高度
        wApplication.navigationBarHeight =
            UIUtils.getNavigationBarHeight(activity) // 底部导航栏高度
        wApplication.sdkVersion = BuildConfig.VERSION_NAME // CodeLocator版本
        wApplication.minPluginVersion = "2.0.0"
        wApplication.orientation = activity.resources.configuration.orientation // app朝向
        wApplication.fetchUrl = CodeLocatorConfigFetcher.getFetchUrl(activity) // 可能是用来下发配置的
        val wm: WindowManager? = activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager?
        if (wm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            val point = Point() // 屏幕宽高
            wm.defaultDisplay.getRealSize(point)
            wApplication.realWidth = point.x
            wApplication.realHeight = point.y
        }

        CodeLocator.sGlobalConfig.codeLocatorProcessors?.let {
            for (processor in it) {
                try { // 再加工数据
                    processor?.processApplication(wApplication, activity)
                } catch (t: Throwable) {
                    Log.d(CodeLocator.TAG, "Process Error " + Log.getStackTraceString(t))
                }
            }
        }
        CodeLocator.sGlobalConfig.appInfoProvider?.providerAllSchema()?.takeIf { it.isNotEmpty() }
            ?.let {
                wApplication.schemaInfos = mutableListOf()
                wApplication.schemaInfos.addAll(it)
            }
    }
```



#### ShowAndAppInfo



> 1. 获取额外的App信息
> 2. 获取color信息

```kotlin
 private fun buildShowAndAppInfo(
        wApplication: WApplication,
        activity: Activity,
        needColor: Boolean
    ) {
        wApplication.showInfos = CodeLocator.getShowInfo()
        wApplication.appInfo = CodeLocator.sGlobalConfig?.appInfoProvider?.providerAppInfo(activity)
        if (needColor) {
            wApplication.colorInfo =
                CodeLocator.sGlobalConfig?.appInfoProvider?.providerColorInfo(activity)
        }
        if (wApplication.appInfo != null) {
            wApplication.appInfo[AppInfoProvider.CODELOCATOR_KEY_DEBUGGABLE] = "" + wApplication.isIsDebug
        } else {
            wApplication.appInfo = HashMap()
            wApplication.appInfo[AppInfoProvider.CODELOCATOR_KEY_DEBUGGABLE] = "" + wApplication.isIsDebug
        }
    }
```







#### ActivityInfo



> 将Activity转为了一个新的数据结构WActivity



```kotlin
private fun buildActivityInfo(
        wApplication: WApplication,
        activity: Activity
    ) {
        val wActivity = WActivity()
        wActivity.memAddr = CodeLocatorUtils.getObjectMemAddr(activity) // 内存地址
        wActivity.startInfo =
            activity.intent.getStringExtra(CodeLocatorConstants.ACTIVITY_START_STACK_INFO) // activity start溯源（代码跳转）
        wActivity.className = activity.javaClass.name // 获取activity名称
        wApplication.activity = wActivity
  			// 附加信息
        CodeLocator.sGlobalConfig.codeLocatorProcessors?.let {
            for (processor in it) {
                try {
                    processor?.processActivity(wActivity, activity)
                } catch (t: Throwable) {
                    Log.d(CodeLocator.TAG, "Process Error " + Log.getStackTraceString(t))
                }
            }
        }
    }
```



#### FragmentInfo



```kotlin
 private fun buildFragmentInfo(
        wApplication: WApplication,
        activity: Activity,
        isMainThread: Boolean
    ) {
        val childFragments = mutableListOf<WFragment>()
        if (activity is FragmentActivity) {
            activity.supportFragmentManager?.let {
                val fragments = it.fragments
                if (!fragments.isNullOrEmpty()) {
                    for (i in 0 until fragments.size) {
                        try {
                            childFragments.add(
                                convertFragmentToWFragment(
                                    fragments[i],
                                    isMainThread
                                )
                            )
                        } catch (t: Throwable) {
                            Log.d(
                                CodeLocator.TAG,
                                "convertFragmentToWFragment error, stackTrace: " + Log.getStackTraceString(
                                    t
                                )
                            )
                        }
                    }
                }
            }
        }
        activity.fragmentManager?.let {
            val fragments = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                it.fragments
            } else {
                try {
                    val classField = ReflectUtils.getClassField(it.javaClass, "mAdded")
                    classField?.get(it) as? List<android.app.Fragment>
                } catch (t: Throwable) {
                    mutableListOf<android.app.Fragment>()
                }
            }
            if (!fragments.isNullOrEmpty()) {
                for (f in fragments) {
                    try {
                        childFragments.add(convertFragmentToWFragment(f, isMainThread))
                    } catch (t: Throwable) {
                        Log.d(
                            CodeLocator.TAG,
                            "convertFragmentToWFragment error, stackTrace: " + Log.getStackTraceString(
                                t
                            )
                        )
                    }
                }
            }
        }
        if (childFragments.isNotEmpty()) {
            wApplication.activity.fragments = childFragments
        }
    }
```



#### ViewInfo







### 消息返回
