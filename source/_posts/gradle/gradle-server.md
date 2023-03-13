---
title: Gradle之Daemon启动流程
date: 2023-03-13 11:16:35
tags:
- gradle
categories:
- gradle
---



# Gradle Daemon

> 先会尝试连接daemon，如果没有daemon可用尝试通过connector.startDaemon开启新的daemon

```java
public BuildActionResult execute(BuildAction action, BuildActionParameters parameters, BuildRequestContext requestContext) {
    UUID buildId = idGenerator.generateId();
    List<DaemonInitialConnectException> accumulatedExceptions = Lists.newArrayList();

    // Attempt to connect to an existing idle and compatible daemon
    int saneNumberOfAttempts = 100; //is it sane enough?
    for (int i = 1; i < saneNumberOfAttempts; i++) {
        final DaemonClientConnection connection = connector.connect(compatibilitySpec);
        // No existing, compatible daemon is available to try
        if (connection == null) {
            break;
        }
        // Compatible daemon was found, try it
        try {
            Build build = new Build(buildId, connection.getDaemon().getToken(), action, requestContext.getClient(), requestContext.getStartTime(), requestContext.isInteractive(), parameters);
            return executeBuild(build, connection, requestContext.getCancellationToken(), requestContext.getEventConsumer());
        } catch (DaemonInitialConnectException e) {
            // this exception means that we want to try again.
            LOGGER.debug("{}, Trying a different daemon...", e.getMessage());
            accumulatedExceptions.add(e);
        } finally {
            connection.stop();
        }
    }

    // No existing daemon was usable, so start a new one and try it once
    final DaemonClientConnection connection = connector.startDaemon(compatibilitySpec);
    try {
        Build build = new Build(buildId, connection.getDaemon().getToken(), action, requestContext.getClient(), requestContext.getStartTime(), requestContext.isInteractive(), parameters);
        return executeBuild(build, connection, requestContext.getCancellationToken(), requestContext.getEventConsumer());
    } catch (DaemonInitialConnectException e) {
        //......
    } finally {
        connection.stop();
    }
}
```





## 创建Process

`DefaultDaemonConnector.java`

```java
public DaemonClientConnection startDaemon(ExplainingSpec<DaemonContext> constraint) {
    return doStartDaemon(constraint, false);
}
```



```java
private DaemonClientConnection doStartDaemon(ExplainingSpec<DaemonContext> constraint, boolean singleRun) {
    ProgressLogger progressLogger = progressLoggerFactory.newOperation(DefaultDaemonConnector.class)
        .start("Starting Gradle Daemon", "Starting Daemon");
    final DaemonStartupInfo startupInfo = daemonStarter.startDaemon(singleRun);
    LOGGER.debug("Started Gradle daemon {}", startupInfo);
    // 计时
    CountdownTimer timer = Time.startCountdownTimer(connectTimeout);
    try {
        do {
            DaemonClientConnection daemonConnection = connectToDaemonWithId(startupInfo, constraint);
            if (daemonConnection != null) {
                startListener.daemonStarted(daemonConnection.getDaemon());
                return daemonConnection;
            }
            try {
                sleep(200L);
            } catch (InterruptedException e) {
                throw UncheckedException.throwAsUncheckedException(e);
            }
        } while (!timer.hasExpired());
    } finally {
        progressLogger.completed();
    }

    throw new DaemonConnectionException("Timeout waiting to connect to the Gradle daemon.\n" + startupInfo.describe());
}
```



## 写入参数

`DefaultDaemonStarter.java`

```java
public DaemonStartupInfo startDaemon(boolean singleUse) {
    String daemonUid = UUID.randomUUID().toString();
	
    // 获取必要的参数信息
    GradleInstallation gradleInstallation = CurrentGradleInstallation.get();
    ModuleRegistry registry = new DefaultModuleRegistry(gradleInstallation);
    ClassPath classpath;
    List<File> searchClassPath;
    if (gradleInstallation == null) {
        // When not running from a Gradle distro, need runtime impl for launcher plus the search path to look for other modules
        classpath = registry.getModule("gradle-launcher").getAllRequiredModulesClasspath();
        searchClassPath = registry.getAdditionalClassPath().getAsFiles();
    } else {
        // When running from a Gradle distro, only need launcher jar. The daemon can find everything from there.
        classpath = registry.getModule("gradle-launcher").getImplementationClasspath();
        searchClassPath = Collections.emptyList();
    }
    if (classpath.isEmpty()) {
        throw new IllegalStateException("Unable to construct a bootstrap classpath when starting the daemon");
    }

    versionValidator.validate(daemonParameters);
	// 拼接参数
    List<String> daemonArgs = new ArrayList<String>();
    daemonArgs.addAll(getPriorityArgs(daemonParameters.getPriority()));
    daemonArgs.add(daemonParameters.getEffectiveJvm().getJavaExecutable().getAbsolutePath());

    List<String> daemonOpts = daemonParameters.getEffectiveJvmArgs();
    daemonArgs.addAll(daemonOpts);
    daemonArgs.add("-cp");
    daemonArgs.add(CollectionUtils.join(File.pathSeparator, classpath.getAsFiles()));

    if (Boolean.getBoolean("org.gradle.daemon.debug")) {
        daemonArgs.add("-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5005");
    }
    LOGGER.debug("Using daemon args: {}", daemonArgs);

    daemonArgs.add(GradleDaemon.class.getName());
    // Version isn't used, except by a human looking at the output of jps.
    daemonArgs.add(GradleVersion.current().getVersion());

    // Serialize configuration to daemon via the process' stdin
    // 包装成流
    StreamByteBuffer buffer = new StreamByteBuffer();
    FlushableEncoder encoder = new KryoBackedEncoder(new EncodedStream.EncodedOutput(buffer.getOutputStream()));
    try {
        // 将参数通过std流传给开辟的process
        encoder.writeString(daemonParameters.getGradleUserHomeDir().getAbsolutePath());
        encoder.writeString(daemonDir.getBaseDir().getAbsolutePath());
        encoder.writeSmallInt(daemonParameters.getIdleTimeout());
        encoder.writeSmallInt(daemonParameters.getPeriodicCheckInterval());
        encoder.writeBoolean(singleUse);
        encoder.writeString(daemonUid);
        encoder.writeSmallInt(daemonParameters.getPriority().ordinal());
        encoder.writeSmallInt(daemonOpts.size());
        for (String daemonOpt : daemonOpts) {
            encoder.writeString(daemonOpt);
        }
        encoder.writeSmallInt(searchClassPath.size());
        for (File file : searchClassPath) {
            encoder.writeString(file.getAbsolutePath());
        }
        encoder.flush();
    } catch (IOException e) {
        throw new UncheckedIOException(e);
    }
    InputStream stdInput = buffer.getInputStream();
	// 开启进程
    return startProcess(
        daemonArgs,
        daemonDir.getVersionedDir(),
        daemonParameters.getGradleUserHomeDir().getAbsoluteFile(),
        stdInput
    );
}
```



## 创建ExecHandle并启动



```java
private DaemonStartupInfo startProcess(List<String> args, File workingDir, File gradleUserHome, InputStream stdInput) {
    LOGGER.debug("Starting daemon process: workingDir = {}, daemonArgs: {}", workingDir, args);
    Timer clock = Time.startTimer();
    try {
        // 创建工作路径
        GFileUtils.mkdirs(workingDir);
		// daemon output 消费者，用于读取daemon的输出
        DaemonOutputConsumer outputConsumer = new DaemonOutputConsumer();

        // This factory should be injected but leaves non-daemon threads running when used from the tooling API client
        @SuppressWarnings("deprecation")
        DefaultExecActionFactory execActionFactory = DefaultExecActionFactory.root(gradleUserHome);
        try {
            // 配置启动参数
            ExecHandle handle = new DaemonExecHandleBuilder().build(args, workingDir, outputConsumer, stdInput, execActionFactory.newExec());
			// 执行
            handle.start();
            LOGGER.debug("Gradle daemon process is starting. Waiting for the daemon to detach...");
            // 等待结束
            handle.waitForFinish();
            LOGGER.debug("Gradle daemon process is now detached.");
        } finally {
            CompositeStoppable.stoppable(execActionFactory).stop();
        }
		// 解析启动结果
        return daemonGreeter.parseDaemonOutput(outputConsumer.getProcessOutput(), args);
    } catch (GradleException e) {
        throw e;
    } catch (Exception e) {
        throw new GradleException("Could not start Gradle daemon.", e);
    } finally {
        LOGGER.info("An attempt to start the daemon took {}.", clock.getElapsed());
    }
}
```



`ExecHandlerRunner.java`

```java
public void run() {
    try {
        // 开启进程
        startProcess();
		
        execHandle.started();

        LOGGER.debug("waiting until streams are handled...");
        // 连接stream
        streamsHandler.start();

        if (execHandle.isDaemon()) {
            streamsHandler.stop();
            detached();
        } else {
            int exitValue = process.waitFor();
            streamsHandler.stop();
            completed(exitValue);
        }
    } catch (Throwable t) {
        execHandle.failed(t);
    }
}
```



> 通过processBuilder开启进程

```java
private void startProcess() {
    lock.lock();
    try {
        if (aborted) {
            throw new IllegalStateException("Process has already been aborted");
        }
        ProcessBuilder processBuilder = processBuilderFactory.createProcessBuilder(execHandle);
        Process process = processLauncher.start(processBuilder);
        // 连接stream（process的in/out流）
        streamsHandler.connectStreams(process, execHandle.getDisplayName(), executor);
        this.process = process;
    } finally {
        lock.unlock();
    }
}
```



## Command

ProcessBuilder

- command

```text
0 = "D:\Users\Fool\.jdks\corretto-11.0.18\bin\java.exe"
1 = "--add-opens=java.base/java.util=ALL-UNNAMED"
2 = "--add-opens=java.base/java.lang=ALL-UNNAMED"
3 = "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED"
4 = "--add-opens=java.prefs/java.util.prefs=ALL-UNNAMED"
5 = "--add-opens=java.base/java.nio.charset=ALL-UNNAMED"
6 = "--add-opens=java.base/java.net=ALL-UNNAMED"
7 = "--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED"
8 = "-XX:MaxMetaspaceSize=256m"
9 = "-XX:+HeapDumpOnOutOfMemoryError"
10 = "-Xms256m"
11 = "-Xmx512m"
12 = "-Dfile.encoding=GBK"
13 = "-Duser.country=CN"
14 = "-Duser.language=zh"
15 = "-Duser.variant"
16 = "-cp"
17 = "D:\Compiler\wrapper\dists\gradle-7.6-all\9f832ih6bniajn45pbmqhk2cw\gradle-7.6\lib\gradle-launcher-7.6.jar"
18 = "org.gradle.launcher.daemon.bootstrap.GradleDaemon"
19 = "7.6"
```

- workDirectory

```text
D:\Compiler\daemon\7.6
```

- env

```text
"USERDOMAIN_ROAMINGPROFILE" -> "FOOLISH-PC"
"PROCESSOR_LEVEL" -> "6"
"SESSIONNAME" -> "Console"
"ALLUSERSPROFILE" -> "C:\ProgramData"
"PROCESSOR_ARCHITECTURE" -> "AMD64"
"PSModulePath" -> "C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules"
"__INTELLIJ_COMMAND_HISTFILE__" -> "C:\Users\fool\AppData\Local\JetBrains\IntelliJIdea2022.3\terminal\history\gradle-history"
"SystemDrive" -> "C:"
"DIRNAME" -> "D:\Code\2023\demo\gradle\"
"USERNAME" -> "fool"
"ProgramFiles(x86)" -> "C:\Program Files (x86)"
"FPS_BROWSER_USER_PROFILE_STRING" -> "Default"
"APP_HOME" -> "D:\Code\2023\demo\gradle\"
"DEFAULT_JVM_OPTS" -> ""-Xmx64m" "-Xms64m" "-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005""
"PATHEXT" -> ".COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC"
"DriverData" -> "C:\Windows\System32\Drivers\DriverData"
"OneDriveConsumer" -> "C:\Users\fool\OneDrive"
"ORIGINAL_XDG_CURRENT_DESKTOP" -> "undefined"
"ProgramData" -> "C:\ProgramData"
"ProgramW6432" -> "C:\Program Files"
"HOMEPATH" -> "\Users\fool"
"TERM_SESSION_ID" -> "7beb2ed0-eaf7-48fa-8abf-007bbf366998"
"PROCESSOR_IDENTIFIER" -> "Intel64 Family 6 Model 142 Stepping 12, GenuineIntel"
"PUBLIC" -> "C:\Users\Public"
"ProgramFiles" -> "C:\Program Files"
"windir" -> "C:\WINDOWS"
"=::" -> "::\"
"ZES_ENABLE_SYSMAN" -> "1"
"LOCALAPPDATA" -> "C:\Users\fool\AppData\Local"
"USERDOMAIN" -> "FOOLISH-PC"
"FPS_BROWSER_APP_PROFILE_STRING" -> "Internet Explorer"
"LOGONSERVER" -> "\\FOOLISH-PC"
"PROMPT" -> "$P$G"
"JAVA_HOME" -> "D:\Users\Fool\.jdks\corretto-11.0.18"
"OneDrive" -> "C:\Users\fool\OneDrive"
"GRADLE_USER_HOME" -> "D:\Compiler"
"APPDATA" -> "C:\Users\fool\AppData\Roaming"
"JAVA_EXE" -> "D:\Users\Fool\.jdks\corretto-11.0.18/bin/java.exe"
"Path" -> "C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Windows\System32\OpenSSH\;C:\Program Files (x86)\NVIDIA Corporation\PhysX\Common;C:\Program Files\NVIDIA Corporation\NVIDIA NvDLISR;C:\Program Files\Bandizip\;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;C:\WINDOWS\System32\OpenSSH\;D:\Program Files\nodejs\;D:\Program Files\Git\bin;D:\Compiler\sdk\platform-tools;$JAVA_HOME\bin;;C:\Program Files\Docker\Docker\resources\bin;C:\Users\fool\AppData\Local\Microsoft\WindowsApps;C:\Users\fool\AppData\Local\JetBrains\Toolbox\scripts;;C:\Users\fool\AppData\Local\Microsoft\WindowsApps;C:\Users\fool\AppData\Roaming\npm;D:\Users\fool\AppData\Local\Programs\Microsoft VS Code\bin"
"CommonProgramFiles" -> "C:\Program Files\Common Files"
"OS" -> "Windows_NT"
"COMPUTERNAME" -> "FOOLISH-PC"
"PROCESSOR_REVISION" -> "8e0c"
"CLASSPATH" -> "D:\Code\2023\demo\gradle\\gradle\wrapper\gradle-wrapper.jar"
"CommonProgramW6432" -> "C:\Program Files\Common Files"
"ComSpec" -> "C:\WINDOWS\system32\cmd.exe"
"APP_BASE_NAME" -> "gradlew"
"TERMINAL_EMULATOR" -> "JetBrains-JediTerm"
"SystemRoot" -> "C:\WINDOWS"
"TEMP" -> "C:\Users\fool\AppData\Local\Temp"
"=D:" -> "D:\Code\2023\demo\gradle"
"USERPROFILE" -> "C:\Users\fool"
"HOMEDRIVE" -> "C:"
"TMP" -> "C:\Users\fool\AppData\Local\Temp"
"CommonProgramFiles(x86)" -> "C:\Program Files (x86)\Common Files"
"NUMBER_OF_PROCESSORS" -> "8"
"IDEA_INITIAL_DIRECTORY" -> "C:\Users\fool\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\JetBrains Toolbox"
```



## 总结



用一句话概括既是（不完全准确，省略了jvm参数配置等）

```shell
java -cp 
D:\Compiler\wrapper\dists\gradle-7.6-all\9f832ih6bniajn45pbmqhk2cw\gradle-7.6\lib\gradle-launcher-7.6.jar 

org.gradle.launcher.daemon.bootstrap.GradleDaemon
```

