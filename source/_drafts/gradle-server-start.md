---
title: gradle-server-start
date: 2023-03-31 22:13:35
tags:
- gradle
categories:
- gradle
---



# Gradle Server Start



> 前面分析到了Gradle会通过ProcessBuilder开启一个Deamon进程

并调用shell

```shell
java -cp *gradle-launcher-7.6.jar 
org.gradle.launcher.daemon.bootstrap.GradleDaemon
```



## BootStrap

> 和Client启动类似

```java
public class GradleDaemon {
    public static void main(String[] args) {
        ProcessBootstrap.run("org.gradle.launcher.daemon.bootstrap.DaemonMain", args);
    }
}
```



> 设置ClassLoader

```java
public static void run(String mainClassName, String[] args) {
        try {
            runNoExit(mainClassName, args);
            System.exit(0);
        } catch (Throwable throwable) {
            throwable.printStackTrace();
            System.exit(1);
        }
    }

    private static void runNoExit(String mainClassName, String[] args) throws Exception { /* 配置ClassLoader */
        ClassPathRegistry classPathRegistry = new DefaultClassPathRegistry(new DefaultClassPathProvider(new DefaultModuleRegistry(CurrentGradleInstallation.get())));
        ClassLoaderFactory classLoaderFactory = new DefaultClassLoaderFactory();
        ClassPath antClasspath = classPathRegistry.getClassPath("ANT");
        ClassPath runtimeClasspath = classPathRegistry.getClassPath("GRADLE_RUNTIME");
        ClassLoader antClassLoader = classLoaderFactory.createIsolatedClassLoader("ant-loader", antClasspath);
        ClassLoader runtimeClassLoader = new VisitableURLClassLoader("ant-and-gradle-loader", antClassLoader, runtimeClasspath);

        ClassLoader oldClassLoader = Thread.currentThread().getContextClassLoader();
        Thread.currentThread().setContextClassLoader(runtimeClassLoader);

        try {
            Class<?> mainClass = runtimeClassLoader.loadClass(mainClassName);
            Object entryPoint = mainClass.getConstructor().newInstance();
            Method mainMethod = mainClass.getMethod("run", String[].class);
            mainMethod.invoke(entryPoint, new Object[]{args});
        } finally {
            Thread.currentThread().setContextClassLoader(oldClassLoader);

            ClassLoaderUtils.tryClose(runtimeClassLoader);
            ClassLoaderUtils.tryClose(antClassLoader);
        }
    }
```



## DaemonMain



```java
 protected void doAction(String[] args, ExecutionListener listener) {
        // check,判断args
        if (args.length != 1) {
            invalidArgs("Following arguments are required: <gradle-version>");
        }

        // 从stdin读取
        List<String> startupOpts;
        File gradleHomeDir;
        File daemonBaseDir;
        int idleTimeoutMs;
        int periodicCheckIntervalMs;
        boolean singleUse;
        String daemonUid;
        DaemonParameters.Priority priority;
        List<File> additionalClassPath;
		// 读取配置参数
        KryoBackedDecoder decoder = new KryoBackedDecoder(new EncodedStream.EncodedInput(System.in));
        try {
            gradleHomeDir = new File(decoder.readString());
            daemonBaseDir = new File(decoder.readString());
            idleTimeoutMs = decoder.readSmallInt();
            periodicCheckIntervalMs = decoder.readSmallInt();
            singleUse = decoder.readBoolean();
            daemonUid = decoder.readString();
            priority = DaemonParameters.Priority.values()[decoder.readSmallInt()];
            int argCount = decoder.readSmallInt();
            startupOpts = new ArrayList<String>(argCount);
            for (int i = 0; i < argCount; i++) {
                startupOpts.add(decoder.readString());
            }
            int additionalClassPathLength = decoder.readSmallInt();
            additionalClassPath = new ArrayList<File>(additionalClassPathLength);
            for (int i = 0; i < additionalClassPathLength; i++) {
                additionalClassPath.add(new File(decoder.readString()));
            }
        } catch (EOFException e) {
            throw new UncheckedIOException(e);
        }
		// 初始化service
        NativeServices.initializeOnDaemon(gradleHomeDir);
        DaemonServerConfiguration parameters = new DefaultDaemonServerConfiguration(daemonUid, daemonBaseDir, idleTimeoutMs, periodicCheckIntervalMs, singleUse, priority, startupOpts);
        LoggingServiceRegistry loggingRegistry = LoggingServiceRegistry.newCommandLineProcessLogging();
        LoggingManagerInternal loggingManager = loggingRegistry.newInstance(LoggingManagerInternal.class);

        DaemonServices daemonServices = new DaemonServices(parameters, loggingRegistry, loggingManager, DefaultClassPath.of(additionalClassPath));
        File daemonLog = daemonServices.getDaemonLogFile();

        // Any logging prior to this point will not end up in the daemon log file.
        initialiseLogging(loggingManager, daemonLog);

        // Detach the process from the parent terminal/console
        ProcessEnvironment processEnvironment = daemonServices.get(ProcessEnvironment.class);
        processEnvironment.maybeDetachProcess();

        LOGGER.debug("Assuming the daemon was started with following jvm opts: {}", startupOpts);
		// 开启后台daemon线程
        Daemon daemon = daemonServices.get(Daemon.class);
        daemon.start();

        try {
            DaemonContext daemonContext = daemonServices.get(DaemonContext.class);
            Long pid = daemonContext.getPid();
            daemonStarted(pid, daemon.getUid(), daemon.getAddress(), daemonLog);
            DaemonExpirationStrategy expirationStrategy = daemonServices.get(MasterExpirationStrategy.class);
            daemon.stopOnExpiration(expirationStrategy, parameters.getPeriodicCheckIntervalMs());
        } finally {
            daemon.stop();
            // TODO: Stop all daemon services
            CompositeStoppable.stoppable(daemonServices.get(GradleUserHomeScopeServiceRegistry.class)).stop();
        }
    }
```



## Daemon



