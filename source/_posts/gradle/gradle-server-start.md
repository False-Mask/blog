---
title: Gradle Daemon启动分析
tags:
  - gradle
cover: https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gradle-dark-green-primary.png
date: 2024-04-09 17:17:40
---


# Gradle Server Start



> Server的启动主要是进行初始化和环境的准备

主要可以分为如下几个过程

1. Bootstrap：启动进程，设置ClassLoader
2. Init：初始化成员，初始化Socket
3. Wait：进程keep-alive，防止main线程死亡，休眠等待。



# Bootstrap



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



# Init



## Daemon



> 初始化监听 & 初始化服务器连接

```java
public void start() {
    LOGGER.info("start() called on daemon - {}", daemonContext);
    lifecycleLock.lock();
    try {
        if (stateCoordinator != null) {
            throw new IllegalStateException("cannot start daemon as it is already running");
        }

        // Generate an authentication token, which must be provided by the client in any requests it makes
        SecureRandom secureRandom = new SecureRandom();
        byte[] token = new byte[16];
        secureRandom.nextBytes(token);

        registryUpdater = new DaemonRegistryUpdater(daemonRegistry, daemonContext, token);

        ShutdownHooks.addShutdownHook(new Runnable() {
            @Override
            public void run() {
                try {
                    daemonRegistry.remove(connectorAddress);
                } catch (Exception e) {
                    LOGGER.debug("VM shutdown hook was unable to remove the daemon address from the registry. It will be cleaned up later.", e);
                }
            }
        });

        Runnable onStartCommand = new Runnable() {
            @Override
            public void run() {
                registryUpdater.onStartActivity();
            }
        };

        Runnable onFinishCommand = new Runnable() {
            @Override
            public void run() {
                registryUpdater.onCompleteActivity();
            }
        };

        Runnable onCancelCommand = new Runnable() {
            @Override
            public void run() {
                registryUpdater.onCancel();
            }
        };

        // Start the pipeline in reverse order:
        // 1. mark daemon as running
        // 2. start handling incoming commands
        // 3. start accepting incoming connections
        // 4. advertise presence in registry

        stateCoordinator = new DaemonStateCoordinator(executorFactory, onStartCommand, onFinishCommand, onCancelCommand);
        connectionHandler = new DefaultIncomingConnectionHandler(commandExecuter, daemonContext, stateCoordinator, executorFactory, token);
        Runnable connectionErrorHandler = new Runnable() {
            @Override
            public void run() {
                stateCoordinator.stop();
            }
        };
        connectorAddress = connector.start(connectionHandler, connectionErrorHandler);
        LOGGER.debug("Daemon starting at: {}, with address: {}", new Date(), connectorAddress);
        registryUpdater.onStart(connectorAddress);
    } finally {
        lifecycleLock.unlock();
    }

    LOGGER.lifecycle(DaemonMessages.PROCESS_STARTED);
}
```



## Connector



> 注册了一个connect监听

```java
public class DaemonTcpServerConnector implements DaemonServerConnector {
    // ......
     public Address start(final IncomingConnectionHandler handler, final Runnable connectionErrorHandler) {
        lifecycleLock.lock();
        try {
            if (stopped) {
                throw ......
            }
            if (started) {
                throw ......
            }

            // Hold the lock until we actually start accepting connections for the case when stop is called from another
            // thread while we are in the middle here.

            Action<ConnectCompletion> connectEvent = new Action<ConnectCompletion>() {
                @Override
                public void execute(ConnectCompletion completion) {
                    RemoteConnection<Message> remoteConnection;
                    try {
                        remoteConnection = completion.create(Serializers.stateful(serializer));
                    } catch (UncheckedIOException e) {
                        connectionErrorHandler.run();
                        throw e;
                    }
                    handler.handle(new SynchronizedDispatchConnection<Message>(remoteConnection));
                }
            };

            acceptor = incomingConnector.accept(connectEvent, false);
            started = true;
            return acceptor.getAddress();
        } finally {
            lifecycleLock.unlock();
        }
    }
}
```



## TcpIncomingConnector



> 1. 创建socket channel
> 2. 将accept操作存入线程池，不阻塞主线程

```java
public class TcpIncomingConnector implements IncomingConnector {
 	// ......
     public ConnectionAcceptor accept(Action<ConnectCompletion> action, boolean allowRemote) {
        final ServerSocketChannel serverSocket;
        int localPort;
        try {
            serverSocket = ServerSocketChannel.open();
            serverSocket.socket().bind(new InetSocketAddress(addressFactory.getLocalBindingAddress(), 0));
            localPort = serverSocket.socket().getLocalPort();
        } catch (Exception e) {
            throw UncheckedException.throwAsUncheckedException(e);
        }

        UUID id = idGenerator.generateId();
        List<InetAddress> addresses = Collections.singletonList(addressFactory.getLocalBindingAddress());
        final Address address = new MultiChoiceAddress(id, localPort, addresses);
        LOGGER.debug("Listening on {}.", address);

        final ManagedExecutor executor = executorFactory.create("Incoming " + (allowRemote ? "remote" : "local")+ " TCP Connector on port " + localPort);
        executor.execute(new Receiver(serverSocket, action, allowRemote));

        return new ConnectionAcceptor() {
            @Override
            public Address getAddress() {
                return address;
            }

            @Override
            public void requestStop() {
                CompositeStoppable.stoppable(serverSocket).stop();
            }

            @Override
            public void stop() {
                requestStop();
                executor.stop();
            }
        };
    }
    
}
```





> 如下是具体的Accept操作

```java
   private class Receiver implements Runnable {

     	// ......

        @Override
        public void run() {
            try {
                try {
                    while (true) {
                        final SocketChannel socket = serverSocket.accept();
                        InetSocketAddress remoteSocketAddress = (InetSocketAddress) socket.socket().getRemoteSocketAddress();
                        InetAddress remoteInetAddress = remoteSocketAddress.getAddress();
                        if (!allowRemote && !addressFactory.isCommunicationAddress(remoteInetAddress)) {
                            LOGGER.error("Cannot accept connection from remote address {}.", remoteInetAddress);
                            socket.close();
                            continue;
                        }
                        LOGGER.debug("Accepted connection from {} to {}.", socket.socket().getRemoteSocketAddress(), socket.socket().getLocalSocketAddress());
                        try {
                            action.execute(new SocketConnectCompletion(socket));
                        } catch (Throwable t) {
                            socket.close();
                            throw t;
                        }
                    }
                }// catch ......
            } finally {
                CompositeStoppable.stoppable(serverSocket).stop();
            }
        }

    }
```



> 经过几次中转以后会调用到handle方法，触发后续的构建流程.
>
> 这里是后续构建过程的内容了。（暂不分析）

```java
public class DefaultIncomingConnectionHandler implements IncomingConnectionHandler, Stoppable {
 	   
    @Override
    public void handle(SynchronizedDispatchConnection<Message> connection) {
        // Mark the connection has being handled
        onStartHandling(connection);

        //we're spinning a thread to do work to avoid blocking the connection
        //This means that the Daemon potentially can do multiple things but we only allows a single build at a time

        workers.execute(new ConnectionWorker(connection));
    }
    
}
```



# Wait



> 这是Daemon启动的最后一步。
>
> 当所有的初始化操作都完成以后，为了保证Daemon进程不要退出，Daemon:main线程会死循环等待。

```java
 daemon.stopOnExpiration(expirationStrategy, parameters.getPeriodicCheckIntervalMs());

public void stopOnExpiration(DaemonExpirationStrategy expirationStrategy, int checkIntervalMills) {
        LOGGER.debug("stopOnExpiration() called on daemon");
        scheduleExpirationChecks(expirationStrategy, checkIntervalMills);
        awaitExpiration();
}

private void awaitExpiration() {
    LOGGER.debug("awaitExpiration() called on daemon");

    DaemonStateCoordinator stateCoordinator;
    lifecycleLock.lock();
    try {
        if (this.stateCoordinator == null) {
            throw new IllegalStateException("cannot await stop on daemon as it has not been started.");
        }
        stateCoordinator = this.stateCoordinator;
    } finally {
        lifecycleLock.unlock();
    }

    stateCoordinator.awaitStop();
}
```



> 反正就是不会退出（一旦退出则表示，进程需要终结了）

```java
boolean awaitStop() {
        lock.lock();
        try {
            while (true) {
                try {
                    switch (state) {
                        case Idle:
                        case Busy:
                            LOGGER.debug("daemon is running. Sleeping until state changes.");
                            condition.await();
                            break;
                        case Canceled:
                            LOGGER.debug("cancel requested.");
                            cancelNow();
                            break;
                        case Broken:
                            throw new IllegalStateException("This daemon is in a broken state.");
                        case StopRequested:
                            LOGGER.debug("daemon stop has been requested. Sleeping until state changes.");
                            condition.await();
                            break;
                        case Stopped:
                            LOGGER.debug("daemon has stopped.");
                            return true;
                    }
                } catch (InterruptedException e) {
                    throw UncheckedException.throwAsUncheckedException(e);
                }
            }
        } finally {
            lock.unlock();
        }
}
```



# 总结



Daemon的启动主要是进行一些配置的初始化操作，不会触发很多逻辑

过程可以分为如下三步：

1. Bootstrap：启动Daemon进程，设置Classloader，初始化最基本的参数
2. Init：初始化必要的类对象，初始化服务，通过SocketChannel等待Client链接
3. Wait：所有的初始化完毕了，为了保证Daemon进程alive，main线程死循环等待。
