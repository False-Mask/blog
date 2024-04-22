---
title: Gradle构建流程
tags:
  - gradle
cover: >-
  https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gradle-dark-green-primary.png
date: 2024-04-22 16:42:56
---


# Gradle构建流程



> 前面我们分析了Gradle的Daemon启动。后续我们需要对Gradle的构建流程进行分析（粗略分析）





# 缘起



> 前面分析到，Gradle的Daemon启动源于Client Connector连接。
>
> 由于Client连接了Server，Server在没有启动的时候才会进行Fork启动。
>
> 启动后的Server并不会构建，因为Server也不知道Client要干嘛，因为Server还没有Client的构建信息。



> 所以接下来会介绍Gradle构建的触发。
>
> （其实上部分Daemon启动的解析中有提到——也就是Connect accept过程会触发构建流程）



```java
public class DaemonTcpServerConnector implements DaemonServerConnector {
 	// ......
    
    @Override
    public Address start(final IncomingConnectionHandler handler, final Runnable connectionErrorHandler) {
        lifecycleLock.lock();
        try {
            // ...... 

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
			// 服务端，开启子现场accept等待client连接。
            acceptor = incomingConnector.accept(connectEvent, false);
            started = true;
            return acceptor.getAddress();
        } finally {
            lifecycleLock.unlock();
        }
    }
    
}
```



> 每当有客户端连接的时候就会调用 到handle方法

```java
 @Override
    public ConnectionAcceptor accept(Action<ConnectCompletion> action, boolean allowRemote) {
        final ServerSocketChannel serverSocket;
        int localPort;
        try {
            serverSocket = ServerSocketChannel.open();
            serverSocket.socket().bind(new InetSocketAddress(addressFactory.getLocalBindingAddress(), 0));
            localPort = serverSocket.socket().getLocalPort();
        } catch (Exception e) {
           // ......
        }

        UUID id = idGenerator.generateId();
        List<InetAddress> addresses = Collections.singletonList(addressFactory.getLocalBindingAddress());
        final Address address = new MultiChoiceAddress(id, localPort, addresses);
       
        final ManagedExecutor executor = executorFactory.create("Incoming " + (allowRemote ? "remote" : "local")+ " TCP Connector on port " + localPort);
        executor.execute(new Receiver(serverSocket, action, allowRemote));

        // ......
    }


// Receiver.java
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
                // ......
                try {
                    action.execute(new SocketConnectCompletion(socket));
                } catch (Throwable t) {
                    socket.close();
                    throw t;
                }
            }
        } // ......
    } // ......
    }






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
```



> handle方法很实在
>
> 1. 将connect加入队列中
> 2. 使用workers线程池执行构建

```c
@Override
    public void handle(SynchronizedDispatchConnection<Message> connection) {
        // Mark the connection has being handled
        onStartHandling(connection);

        //we're spinning a thread to do work to avoid blocking the connection
        //This means that the Daemon potentially can do multiple things but we only allows a single build at a time

        workers.execute(new ConnectionWorker(connection));
}
```



# 缘中



> 也就是构建过程

> 逻辑如下
>
> 1. 接收command信息
> 2. 处理执行

```java
private class ConnectionWorker implements Runnable {
 	 @Override
        public void run() {
            try {
                receiveAndHandleCommand();
            } finally {
                onFinishHandling(connection);
            }
        }
    
    
    private void receiveAndHandleCommand() {
            try {
                DefaultDaemonConnection daemonConnection = new DefaultDaemonConnection(connection, executorFactory);
                try {
                    // 接收command信息。
                    Command command = receiveCommand(daemonConnection);
                    if (command != null) {
                        // 处理/执行
                        handleCommand(command, daemonConnection);
                    }
                } finally {
                    daemonConnection.stop();
                }
            } finally {
                connection.stop();
	}
        
        
    private void handleCommand(Command command, DaemonConnection daemonConnection) {
        
        try {
            if (!Arrays.equals(command.getToken(), token)) {
                // ......
            }
            commandExecuter.executeCommand(daemonConnection, command, daemonContext, daemonStateControl);
        } catch (Throwable e) {
            // ......
            daemonConnection.completed(new Failure(e));
        } // ......

        Object finished = daemonConnection.receive(60, TimeUnit.SECONDS);
    }
    
}
```



后面的构建过程极大的使用了责任链的设计模式，步骤如下

1. 环境准备

   a. Command Actions

   b. Build Executors

   c. Action Executors

   d. Build Tree Action Executors

2. 构建生命周期

​	a. Configure Settings Projects

​	b. Configure Tasks

​	c. Run Tasks





# 环境准备



![build-env.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/build-env.drawio.png)

## Command Actions

> executor执行模式才用了责任链。

```java
public class DaemonCommandExecuter {

    public void executeCommand(
        DaemonConnection connection, 
        Command command, 
        DaemonContext daemonContext, 
        DaemonStateControl daemonStateControl
    ) {
            new DaemonCommandExecution(
                configuration,
                connection,
                command,
                daemonContext,
                daemonStateControl,
                actions
            ).proceed();
        }
    
    // actions
    ImmutableList.of(
            new HandleStop(get(ListenerManager.class)),
            new HandleInvalidateVirtualFileSystem(get(GradleUserHomeScopeServiceRegistry.class)),
            new HandleCancel(),
            new HandleReportStatus(),
            new ReturnResult(),
            new StartBuildOrRespondWithBusy(daemonDiagnostics), // from this point down, the daemon is 'busy'
            new EstablishBuildEnvironment(processEnvironment),
            new LogToClient(loggingManager, daemonDiagnostics), // from this point down, logging is sent back to the client
            new LogAndCheckHealth(healthStats, healthCheck),
            new ForwardClientInput(),
            new RequestStopIfSingleUsedDaemon(),
            new ResetDeprecationLogger(),
            new WatchForDisconnection(),
            new ExecuteBuild(buildActionExecuter, runningStats)
        );
    
    
}
```



> 然后就是一系列的递归调用

![image-20240410173506290](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240410173506290.png)



> 最后这个ExecuteBuild doBuild 触发了后续的构建流程。

```java
public class ExecuteBuild extends BuildCommandOnly {
 	   
     @Override
    protected void doBuild(final DaemonCommandExecution execution, Build build) {
        // ......
        runningStats.buildStarted();
        DaemonConnectionBackedEventConsumer buildEventConsumer = new DaemonConnectionBackedEventConsumer(execution);
        try {
            BuildCancellationToken cancellationToken = execution.getDaemonStateControl().getCancellationToken();
            BuildRequestContext buildRequestContext = new DefaultBuildRequestContext(build.getBuildRequestMetaData(), cancellationToken, buildEventConsumer);
            if (!build.getAction().getStartParameter().isContinuous()) {
                buildRequestContext.getCancellationToken().addCallback(new Runnable() {
                    @Override
                    public void run() {
                        LOGGER.info(DaemonMessages.CANCELED_BUILD);
                    }
                });
            }
            // 继续执行，获取执行结果
            BuildActionResult result = actionExecuter.execute(build.getAction(), build.getParameters(), buildRequestContext);
            execution.setResult(result);
        } finally {
            buildEventConsumer.waitForFinish();
            runningStats.buildFinished();
            LOGGER.debug(DaemonMessages.FINISHED_BUILD);
        }

        execution.proceed();
    }
    
}
```



## Build Executors

> 这里actionExecutor也是一个责任链

```java
new SetupLoggingActionExecuter(loggingManager,
                new SessionFailureReportingActionExecuter(buildLoggerFactory,
                new StartParamsValidatingActionExecuter(
                new BuildSessionLifecycleBuildActionExecuter(userHomeServiceRegistry, globalServices
                ))));
```

> 经过四层调用最后会调用到`BuildSessionLifecycleBuildActionExecuter`中进行后续构建

![image-20240411111639925](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240411111639925.png)



## Build Session Action Executors

> 紧接着就是BuildActionExecutor的执行

```java
return new SubscribableBuildActionExecutor(
                listenerManager,
                buildOperationListenerManager,
                listenerFactory, eventConsumer,
                new ContinuousBuildActionExecutor(
                    workListeners,
                    fileChangeListeners,
                    styledTextOutputFactory,
                    executorFactory,
                    requestMetaData,
                    cancellationToken,
                    deploymentRegistry,
                    listenerManager,
                    buildStartedTime,
                    clock,
                    fileSystem,
                    caseSensitivity,
                    fileSystemWatchingInformation,
                    new RunAsWorkerThreadBuildActionExecutor(
                        workerLeaseService,
                        new RunAsBuildOperationBuildActionExecutor(
                            new BuildTreeLifecycleBuildActionExecutor(buildModelServices, buildLayoutValidator),
                            buildOperationExecutor,
                            loggingBuildOperationProgressBroadcaster,
                            buildOperationNotificationValve))));
```

> 如下是整体的调用栈

![image-20240414134935130](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240414134935130.png)



## Build Tree Action Executors



> Tree Action Executors和他的Actions。

```java
return new RootBuildLifecycleBuildActionExecutor(
                buildStateRegistry,
                new BuildCompletionNotifyingBuildActionRunner(
                    new FileSystemWatchingBuildActionRunner(
                        eventEmitter,
                        virtualFileSystem,
                        deploymentRegistry,
                        statStatisticsCollector,
                        fileHasherStatisticsCollector,
                        directorySnapshotterStatisticsCollector,
                        buildOperationRunner,
                        new BuildOutcomeReportingBuildActionRunner(
                            styledTextOutputFactory,
                            listenerManager,
                            new ProblemReportingBuildActionRunner(
                                new ChainingBuildActionRunner(buildActionRunners),
                                exceptionAnalyser,
                                buildLayout,
                                problemReporters
                            ),
                            buildStartedTime,
                            buildRequestMetaData,
                            buildLoggerFactory)),
                    gradleEnterprisePluginManager));
```



> 函数调用栈。

![image-20240415125116251](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240415125116251.png)



> 需要注意的是，到目前为止，Build还没有开始。还是处于准备的阶段



# 构建生命周期



![build-lifecycle.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/build-lifecycle.drawio.png)



> Gradle的整个构建过程有很明显的状态机驱动。
>
> 其中有几个比较重要的状态机

1. DefaultBuildTreeLifecycleController 

   > 用于控制整个构建状态的流转

2. DefaultBuildLifecycleController

   > 用于控制整个构建3周期的流转（ Configure Setttings Projects 、Configure Tasks、Run Tasks）

3. VintageBuildModelController

   > 控制Settings、Projects脚本的运行

4. ProjectLifecycleController

   > 单独控制Projects的脚本的执行



## Build Tree State Controller



即`public class DefaultBuildTreeLifecycleController implements BuildTreeLifecycleController`

这个Controller有两个State

> 这个过程所做的即将
>
> State从NotStarted转化到Complete

```java
private enum State implements StateTransitionController.State {
        NotStarted, Complete
}
```



> 执行doScheduleAndRunTasks(selector)实现状态的偏移

```java
public class DefaultBuildTreeLifecycleController implements BuildTreeLifecycleController {
    
    @Override
    public void scheduleAndRunTasks(EntryTaskSelector selector) {
        runBuild(() -> doScheduleAndRunTasks(selector));
    }
    
    private <T> T runBuild(Supplier<ExecutionResult<? extends T>> action) {
        return state.transition(State.NotStarted, State.Complete, () -> {
            ExecutionResult<? extends T> result;
            try {
                result = action.get();
            } catch (Throwable t) {
                result = ExecutionResult.failed(t);
            }

            RuntimeException finalReportableFailure = finishExecutor.finishBuildTree(result.getFailures());
            if (finalReportableFailure != null) {
                throw finalReportableFailure;
            }

            return result.getValue();
        });
    }
    
}
```



> scheduleAndRuntask
>
> 1.prepare task graph
>
> 2.执行task

```java
 private ExecutionResult<Void> doScheduleAndRunTasks(@Nullable EntryTaskSelector taskSelector) {
        return taskGraph.withNewWorkGraph(graph -> {
            BuildTreeWorkGraph.FinalizedGraph finalizedGraph = workPreparer.scheduleRequestedTasks(graph, taskSelector);
            return workExecutor.execute(finalizedGraph);
        });
    }
```







## configure





### Build Lifecycle



> Build Lifecycle也是一个状态机

```java
private enum State implements StateTransitionController.State {
        // Configuring the build, can access build model
        Configure,
        // Scheduling tasks for execution
        TaskSchedule,
        ReadyToRun,
        // build has finished and should do no further work
        Finished
    }
```



> Configure -> TaskSchedule

```java
@Override
public void prepareToScheduleTasks() {
    state.maybeTransition(State.Configure, State.TaskSchedule, () -> {
        hasTasks = true;
        modelController.prepareToScheduleTasks();
    });
}
```



### Build Model Lifecycle



> Build Model Lifecycle只有三个

```java
 private enum Stage implements StateTransitionController.State {
        Created, SettingsLoaded, Configured
}
```



> modelController.prepareToScheduleTasks();
>
> 直接就走完了他短暂的生命

```java
@Override
public void prepareToScheduleTasks() {
    prepareSettings();
    prepareProjects();
}

private void prepareSettings() {
    state.transitionIfNotPreviously(Stage.Created, Stage.SettingsLoaded, () -> settingsPreparer.prepareSettings(gradle));
}

private void prepareProjects() {
    state.transitionIfNotPreviously(Stage.SettingsLoaded, Stage.Configured, () -> projectsPreparer.prepareProjects(gradle));
}
```



#### prepareSettings



> Created -> SettingsLoaded



```java
public class BuildOperationFiringProjectsPreparer implements ProjectsPreparer {

    @Override
    public void prepareSettings(GradleInternal gradle) {
        buildOperationExecutor.run(new LoadBuild(gradle));
    }
    
}
```



> LoadBuild可以认为是一个runnable.
>
> 触发Build执行

```java
 private class LoadBuild implements RunnableBuildOperation {

        @Override
        public void run(BuildOperationContext context) {
            doLoadBuild();
            context.setResult(RESULT);
        }

        void doLoadBuild() {
            delegate.prepareSettings(gradle);
        }   
 }

```



> SettingsPreparer用于配置settings.gradle(.kts)并将配置好的settings实例存入gradle实例中

```java
public class DefaultSettingsPreparer implements SettingsPreparer {
    // ......

    @Override
    public void prepareSettings(GradleInternal gradle) {
        // 创建loader
        SettingsLoader settingsLoader = 
            gradle.isRootBuild() ? settingsLoaderFactory.forTopLevelBuild() : settingsLoaderFactory.forNestedBuild();
        // 执行loader
        settingsLoader.findAndLoadSettings(gradle);
    }
}

```

>  Loader

```java
public SettingsLoader forTopLevelBuild() {
        return new GradlePropertiesHandlingSettingsLoader(
            new InitScriptHandlingSettingsLoader(
                new CompositeBuildSettingsLoader(
                    new ChildBuildRegisteringSettingsLoader(
                        new CommandLineIncludedBuildSettingsLoader(
                            defaultSettingsLoader()
                        ),
                        buildRegistry,
                        buildIncluder),
                    buildRegistry),
                initScriptHandler),
            buildLayoutFactory,
            gradlePropertiesController
        );
    }
```



> 然后在最后一个Loader内，调用了Process去创建Settings实例

```java
private SettingsInternal findSettingsAndLoadIfAppropriate(
    GradleInternal gradle,
    StartParameter startParameter,
    SettingsLocation settingsLocation,
    ClassLoaderScope classLoaderScope
) {
    SettingsInternal settings = settingsProcessor.process(gradle, settingsLocation, classLoaderScope, startParameter);
    validate(settings);
    return settings;
}
```



>  Processor呢也是一个责任链，目的内在于去创建一个settings实例

```java
protected SettingsProcessor createSettingsProcessor(
        ScriptPluginFactory scriptPluginFactory,
        ScriptHandlerFactory scriptHandlerFactory,
        Instantiator instantiator,
        ServiceRegistryFactory serviceRegistryFactory,
        GradleProperties gradleProperties,
        BuildOperationExecutor buildOperationExecutor,
        TextFileResourceLoader textFileResourceLoader
    ) {
        return new BuildOperationSettingsProcessor(
            new RootBuildCacheControllerSettingsProcessor(
                new SettingsEvaluatedCallbackFiringSettingsProcessor(
                    new ScriptEvaluatingSettingsProcessor(
                        scriptPluginFactory,
                        new SettingsFactory(
                            instantiator,
                            serviceRegistryFactory,
                            scriptHandlerFactory
                        ),
                        gradleProperties,
                        textFileResourceLoader
                    )
                )
            ),
            buildOperationExecutor
        );
    }
```



> 会在ScriptEvaluatingSettingsProcessor中通过factory创建一个settings实例

```java
 @Override
    public SettingsInternal process(
        GradleInternal gradle,
        SettingsLocation settingsLocation,
        ClassLoaderScope baseClassLoaderScope,
        StartParameter startParameter
    ) {
        Timer settingsProcessingClock = Time.startTimer();
        TextResourceScriptSource settingsScript = new TextResourceScriptSource(textFileResourceLoader.loadFile("settings file", settingsLocation.getSettingsFile()));
        // 创建settings实例
        SettingsInternal settings = settingsFactory.createSettings(gradle, settingsLocation.getSettingsDir(), settingsScript, gradleProperties, startParameter, baseClassLoaderScope);

        gradle.getBuildListenerBroadcaster().beforeSettings(settings);
        // 执行script
        applySettingsScript(settingsScript, settings);
        LOGGER.debug("Timing: Processing settings took: {}", settingsProcessingClock.getElapsed());
        return settings;
    }
```





##### script执行



> script的执行分为两步
>
> 1.编译
>
> 2.运行



```java
private void applySettingsScript(TextResourceScriptSource settingsScript, final SettingsInternal settings) {
    // 编译
    ScriptPlugin configurer = configurerFactory.create(settingsScript, settings.getBuildscript(), settings.getClassLoaderScope(), settings.getBaseClassLoaderScope(), true);
    // 运行
    configurer.apply(settings);
}
```



> 编译过程暂且跳过。执行过程可以讲讲。
>
> 我们的settings.gradle.kts会被编译成一个jar包，然后被层层包裹（settings.gradle也类似，可能类名不一样）

![script.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/script.drawio.png)



> configure.apply会层层剥开回调，最后调用到jar方法进行gradle的配置。（具体怎么配置的留在后面讲）

![image-20240417204251599](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240417204251599.png)



#### prepareProjects



> SettingsLoaded -> Configured



> build prepare过程是由preparer完成的，但不知一个preparer。
>
> 其中以后使用了责任链的设计模式

```java
 protected ProjectsPreparer createBuildConfigurer(
        ProjectConfigurer projectConfigurer,
        BuildSourceBuilder buildSourceBuilder,
        BuildStateRegistry buildStateRegistry,
        BuildInclusionCoordinator inclusionCoordinator,
        BuildLoader buildLoader,
        ListenerManager listenerManager,
        BuildOperationExecutor buildOperationExecutor,
        BuildModelParameters buildModelParameters
    ) {
        ModelConfigurationListener modelConfigurationListener = listenerManager.getBroadcaster(ModelConfigurationListener.class);
        return new BuildOperationFiringProjectsPreparer(
            new BuildTreePreparingProjectsPreparer(
                new DefaultProjectsPreparer(
                    projectConfigurer,
                    buildModelParameters,
                    modelConfigurationListener,
                    buildOperationExecutor,
                    buildStateRegistry),
                buildLoader,
                inclusionCoordinator,
                buildSourceBuilder),
            buildOperationExecutor);
    }
```



- FiringProjectsPreparer
- BuildTreePreparer
- DefaultPreparer

> 过程比prepareSettings要长一点、  tygh nhbjbjbjbjbjbjbjbjbjbjbjbjbjbjbjbjbjbj
>
> 1.设置classloader
>
> 2.attach root project实例
>
> 3.使用include build做依赖替换
>
> 4.构建buildSrc并将依赖导入到root project的classpath下

```java
public class BuildTreePreparingProjectsPreparer implements ProjectsPreparer {
	@Override
    public void prepareProjects(GradleInternal gradle) {
        // Setup classloader for root project, all other projects will be derived from this.
        SettingsInternal settings = gradle.getSettings();
        ClassLoaderScope settingsClassLoaderScope = settings.getClassLoaderScope();
        ClassLoaderScope buildSrcClassLoaderScope = settingsClassLoaderScope.createChild("buildSrc[" + gradle.getIdentityPath() + "]");
        gradle.setBaseProjectClassLoaderScope(buildSrcClassLoaderScope);
        generateDependenciesAccessorsAndAssignPluginVersions(gradle.getServices(), settings, buildSrcClassLoaderScope);
        // attaches root project
        buildLoader.load(gradle.getSettings(), gradle);
        // Makes included build substitutions available
        if (gradle.isRootBuild()) {
            coordinator.registerGlobalLibrarySubstitutions();
        }
        // Build buildSrc and export classpath to root project
        buildBuildSrcAndLockClassloader(gradle, buildSrcClassLoaderScope);

        delegate.prepareProjects(gradle);
    }

}
```



##### 设置classloader

```java
 // Setup classloader for root project, all other projects will be derived from this.
        SettingsInternal settings = gradle.getSettings();
        ClassLoaderScope settingsClassLoaderScope = settings.getClassLoaderScope();
        ClassLoaderScope buildSrcClassLoaderScope = 
            settingsClassLoaderScope.createChild("buildSrc[" + gradle.getIdentityPath() + "]");
        gradle.setBaseProjectClassLoaderScope(buildSrcClassLoaderScope);
// 生成accessor
        generateDependenciesAccessorsAndAssignPluginVersions(gradle.getServices(), settings, buildSrcClassLoaderScope);
```





##### attach root project



> buildLoader 

```java

    protected BuildLoader createBuildLoader(
        GradleProperties gradleProperties,
        BuildOperationExecutor buildOperationExecutor,
        ListenerManager listenerManager
    ) {
        return new NotifyingBuildLoader(
            new ProjectPropertySettingBuildLoader(
                gradleProperties,
                new InstantiatingBuildLoader(),
                listenerManager.getBroadcaster(FileResourceListener.class)
            ),
            buildOperationExecutor
        );
    }
```

> 触发位置

```java
 // attaches root project
buildLoader.load(gradle.getSettings(), gradle);
```



> 具体的load逻辑

```java
public class InstantiatingBuildLoader implements BuildLoader {
    
    @Override
    public void load(SettingsInternal settings, GradleInternal gradle) {
        // 创建project
        createProjects(gradle, settings.getProjectRegistry().getRootProject());
        // attach project
        attachDefaultProject(gradle, settings.getDefaultProject());
    }
    
}
```





##### 使用include build做依赖替换



```java
if (gradle.isRootBuild()) {
	coordinator.registerGlobalLibrarySubstitutions();
}

public void registerGlobalLibrarySubstitutions() {
    for (IncludedBuildState includedBuild : libraryBuilds) {
        buildStateRegistry.registerSubstitutionsFor(includedBuild);
    }
}
```





##### 打包buildsrc并把其加载到classpath

```java
buildBuildSrcAndLockClassloader(gradle, buildSrcClassLoaderScope);

 private void buildBuildSrcAndLockClassloader(GradleInternal gradle, ClassLoaderScope baseProjectClassLoaderScope) {
        ClassPath buildSrcClassPath = buildSourceBuilder.buildAndGetClassPath(gradle);
        baseProjectClassLoaderScope.export(buildSrcClassPath).lock();
}
```





#### delegate



> delegate.prepareProjects (即DefaultProjectsPreparer)

```java
delegate.prepareProjects(gradle);

@Override
public void prepareProjects(GradleInternal gradle) {
    // prepare child projects
    if (!buildModelParameters.isConfigureOnDemand() || !gradle.isRootBuild()) {
        projectConfigurer.configureHierarchy(gradle.getRootProject());
        new ProjectsEvaluatedNotifier(buildOperationExecutor).notify(gradle);
    }

    if (gradle.isRootBuild()) {
        // Make root build substitutions available
        buildStateRegistry.afterConfigureRootBuild();
    }

    modelConfigurationListener.onConfigure(gradle);
}

```



> 后续的流程由projectConfigurer.configureHierarchy(gradle.getRootProject());触发
>
> 他会触发当前project和当前project的子project的configure操作

```java
@Override
public void configureHierarchy(ProjectInternal project) {
    configure(project);
    for (Project sub : project.getSubprojects()) {
        configure((ProjectInternal) sub);
    }
}
```





##### project lifecycle

> project 的configure操作又会触发另外一个lifecycle的执行——即ProjectLifecycleController

> project lifecycle有三个状态，实例化以后状态就处于NotCreated，调用了create以后就进入了Created状态

```java
  public void createMutableModel(
        DefaultProjectDescriptor descriptor,
        BuildState build,
        ProjectState owner,
        ClassLoaderScope selfClassLoaderScope,
        ClassLoaderScope baseClassLoaderScope,
        IProjectFactory projectFactory
    ) {
        controller.transition(State.NotCreated, State.Created, () -> {
            ProjectState parent = owner.getBuildParent();
            ProjectInternal parentModel = parent == null ? null : parent.getMutableModel();
            project = projectFactory.createProject(build.getMutableModel(), descriptor, owner, parentModel, selfClassLoaderScope, baseClassLoaderScope);
        });
    }
```



> 状态迁移又会触发ProjectInternal的evaluate方法

```java
public void ensureSelfConfigured() {
    controller.maybeTransitionIfNotCurrentlyTransitioning(State.Created, State.Configured, () -> project.evaluate());
}
```



> 接着会通过ConfigureActionsProjectEvaluator触发build.gradle dsl的执行

```kotlin
fun createProjectEvaluator(
            buildOperationExecutor: BuildOperationExecutor,
            cachingServiceLocator: CachingServiceLocator,
            scriptPluginFactory: ScriptPluginFactory,
            cancellationToken: BuildCancellationToken
        ): ProjectEvaluator {
            val withActionsEvaluator = ConfigureActionsProjectEvaluator(
                PluginsProjectConfigureActions.from(cachingServiceLocator),
                BuildScriptProcessor(scriptPluginFactory),
                DelayedConfigurationActions()
            )
            return LifecycleProjectEvaluator(buildOperationExecutor, withActionsEvaluator, cancellationToken)
}
```

```java
 public void evaluate(ProjectInternal project, ProjectStateInternal state) {
        for (ProjectConfigureAction configureAction : configureActions) {
            configureAction.execute(project);
        }
}
```



### script执行

![image-20240420121352248](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240420121352248.png)

> dsl的执行是由ConfigureActionsProjectEvaluator中BuildScriptProcessor完成的



> 其中BuildScriptProcessor包含一个ScriptPluginFactory，
>
> 1. execute的过程中会通过ScriptPluginFactory编译指定的build.gradle文件。
>
> 2. 加载到指定的classloader中去。
> 3. 调用apply方法执行build.gradle脚本。

```java
public class BuildScriptProcessor implements ProjectConfigureAction {
    private static final Logger LOGGER = LoggerFactory.getLogger(BuildScriptProcessor.class);
    private final ScriptPluginFactory configurerFactory;

    public BuildScriptProcessor(ScriptPluginFactory configurerFactory) {
        this.configurerFactory = configurerFactory;
    }

    @Override
    public void execute(final ProjectInternal project) {
        // ......
        final Timer clock = Time.startTimer();
        try {
            final ScriptPlugin configurer = 
                configurerFactory.create(project.getBuildScriptSource(), 
                                         project.getBuildscript(), 
                                         project.getClassLoaderScope(), 
                                         project.getBaseClassLoaderScope(), 
                                         true);
            project.getOwner().applyToMutableState(configurer::apply);
        }
        // ......
    }
}
```



> KotlinScriptPlugin会把执行委托给script代码快

```kotlin
class KotlinScriptPlugin(
    private val scriptSource: ScriptSource,
    private val script: (Any) -> Unit
) : ScriptPlugin {

    override fun getSource() =
        scriptSource

    override fun apply(target: Any) {
        logger.debug("Applying Kotlin script to {}", target)
        script(target)
    }
}



// script代码快
KotlinScriptPlugin(scriptSource) { target ->

            kotlinScriptEvaluator
                .evaluate(
                    target,
                    scriptSource,
                    scriptHandler,
                    targetScope,
                    baseScope,
                    topLevelScript,
                    kotlinScriptOptions()
                )
        }

```



> 流程就到了evaluator完成script的执行
>
> evaluator内有一个interpretor对script代码进行编译执行。

```kotlin
internal
class StandardKotlinScriptEvaluator(
    private val classPathProvider: KotlinScriptClassPathProvider,
    private val classloadingCache: KotlinScriptClassloadingCache,
    private val pluginRequestApplicator: PluginRequestApplicator,
    private val pluginRequestsHandler: PluginRequestsHandler,
    private val embeddedKotlinProvider: EmbeddedKotlinProvider,
    private val classPathModeExceptionCollector: ClassPathModeExceptionCollector,
    private val kotlinScriptBasePluginsApplicator: KotlinScriptBasePluginsApplicator,
    private val scriptSourceHasher: ScriptSourceHasher,
    private val classpathHasher: ClasspathHasher,
    private val implicitImports: ImplicitImports,
    private val progressLoggerFactory: ProgressLoggerFactory,
    private val buildOperationExecutor: BuildOperationExecutor,
    private val cachedClasspathTransformer: CachedClasspathTransformer,
    private val scriptExecutionListener: ScriptExecutionListener,
    private val executionEngine: ExecutionEngine,
    private val workspaceProvider: KotlinDslWorkspaceProvider,
    private val fileCollectionFactory: FileCollectionFactory,
    private val inputFingerprinter: InputFingerprinter
) : KotlinScriptEvaluator {

    override fun evaluate(
            target: Any,
            scriptSource: ScriptSource,
            scriptHandler: ScriptHandler,
            targetScope: ClassLoaderScope,
            baseScope: ClassLoaderScope,
            topLevelScript: Boolean,
            options: EvalOptions
        ) {
            withOptions(options) {

                interpreter.eval(
                    target,
                    scriptSource,
                    scriptSourceHasher.hash(scriptSource),
                    scriptHandler,
                    targetScope,
                    baseScope,
                    topLevelScript,
                    options
                )
            }
        }
    
}
```



> Interpretor编译执行

```kotlin
// Interpretor.kt
fun eval(
        target: Any,
        scriptSource: ScriptSource,
        sourceHash: HashCode,
        scriptHandler: ScriptHandler,
        targetScope: ClassLoaderScope,
        baseScope: ClassLoaderScope,
        topLevelScript: Boolean,
        options: EvalOptions = defaultEvalOptions
    ) {

      // ......

        programHost.eval(specializedProgram, scriptHost)
    }


// ProgramHost.kt
fun eval(compiledScript: CompiledScript, scriptHost: KotlinScriptHost<*>) {
    // 加载编译后的build.gradle的jar包
        val program = load(compiledScript, scriptHost)
        withContextClassLoader(program.classLoader) {
            host.onScriptClassLoaded(scriptHost.scriptSource, program)
            // 实例化Program类并执行execute方法
            instantiate(program).execute(this, scriptHost)
        }
    }
```



## task 



> 这一过程的职责很单一即，准备task，对task进行拓扑排序。获得拓扑排序后的节点。



![image-20240422143457910](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240422143457910.png)

> BuildTreeWorkPreparer中有两个步骤
>
> 1. configure modules ()
> 2. configure tasks

```java
public class DefaultBuildTreeWorkPreparer implements BuildTreeWorkPreparer {
	public BuildTreeWorkGraph.FinalizedGraph scheduleRequestedTasks(BuildTreeWorkGraph graph, 
                                                                    @Nullable EntryTaskSelector selector) {
        // 准备阶段 Controller
        // from Configure -> TaskSchedule
        targetBuildController.prepareToScheduleTasks();
        // 运行graph
        return graph.scheduleWork(graphBuilder -> {
            graphBuilder.withWorkGraph(targetBuild, builder -> builder.addRequestedTasks(selector));
        });
    }

}   
```



> 主要完成了
>
> 1. workGraphPreparer的方法初始化配置项
> 2. controllers准备tasks

```java
// DefaultIncludedBuildTaskGraph.java

@Override
public FinalizedGraph scheduleWork(Consumer<? super Builder> action) {
    assertIsOwner();
    // NotPrepared -> Preparing
    expectInState(State.NotPrepared);
    state = State.Preparing;
    
    // Preparing -> ReadyToRun
    buildOperationExecutor.run(new RunnableBuildOperation() {
        @Override
        public void run(BuildOperationContext context) {
            // prepare graph
            DefaultBuildTreeWorkGraphBuilder graphBuilder = 
                new DefaultBuildTreeWorkGraphBuilder(DefaultBuildTreeWorkGraph.this);
            workGraphPreparer.prepareToScheduleTasks(graphBuilder);
            // 拓扑排序准备graph
            action.accept(graphBuilder);
            controllers.populateWorkGraphs();
            context.setResult(new CalculateTreeTaskGraphBuildOperationType.Result() {
            });
        }

        @Override
        public BuildOperationDescriptor.Builder description() {
            return BuildOperationDescriptor.displayName("Calculate build tree task graph")
                .details(new CalculateTreeTaskGraphBuildOperationType.Details() {
                });
        }
    });
    state = State.ReadyToRun;
    return this;
}
```



> 简单看看拓扑排序的过程

```java
// DetermineExecutionPlanAction.java 
private void processNodeQueue() {
        while (!nodeQueue.isEmpty()) {
            final NodeInVisitingSegment nodeInVisitingSegment = nodeQueue.peekFirst();
            final int currentSegment = nodeInVisitingSegment.visitingSegment;
            final Node node = nodeInVisitingSegment.node;

         	// .....

            if (visitingNodes.put(node, currentSegment)) {
                // Have not seen this node before - add its dependencies to the head of the queue and leave this
                // node in the queue
                if (node instanceof TaskNode) {
                    TaskNode taskNode = (TaskNode) node;
                    recordEdgeIfArrivedViaShouldRunAfter(path, taskNode);
                    removeShouldRunAfterSuccessorsIfTheyImposeACycle(taskNode, nodeInVisitingSegment.visitingSegment);
                    takePlanSnapshotIfCanBeRestoredToCurrentTask(planBeforeVisiting, taskNode);
                }

                // 遍历所有的finalizer节点。当前节点被依赖的节点
                for (Node finalizer : node.getFinalizers()) {
                    addFinalizerToQueue(visitingSegmentCounter++, finalizer);
                }
				// 遍历所有的后继节点
                ListIterator<NodeInVisitingSegment> insertPoint = nodeQueue.listIterator();
                for (Node successor : node.getAllSuccessors()) {
                    if (visitingNodes.containsEntry(successor, currentSegment)) {
                        if (!walkedShouldRunAfterEdges.isEmpty()) {
                            //remove the last walked should run after edge and restore state from before walking it
                            GraphEdge toBeRemoved = walkedShouldRunAfterEdges.pop();
                            // Should run after edges only exist between tasks, so this cast is safe
                            TaskNode sourceTask = (TaskNode) toBeRemoved.from;
                            TaskNode targetTask = (TaskNode) toBeRemoved.to;
                            sourceTask.removeShouldSuccessor(targetTask);
                            restorePath(path, toBeRemoved);
                            restoreQueue(toBeRemoved);
                            restoreExecutionPlan(planBeforeVisiting, toBeRemoved);
                            break;
                        } else {
                            onOrderingCycle(successor, node);
                        }
                    }
                    insertPoint.add(new NodeInVisitingSegment(successor, currentSegment));
                }
                path.push(node);
            } else {
                // 如果是已经便利过的节点，并且无其他依赖的节点。（拓扑排序优先级最高）
                nodeQueue.removeFirst();
                maybeRemoveProcessedShouldRunAfterEdge(node);
                visitingNodes.remove(node, currentSegment);
                path.pop();
                nodeMapping.add(node);
            }
        }
    }
```







## run



![gradle-task-run.drawio](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/gradle-task-run.drawio.png)



> run过程即已经拓扑排序后的结果，对task逐一执行。
>
> 其中finalizedGraph是上一部task配置的参数

```java
return workExecutor.execute(finalizedGraph);
```



> 首先会经过两层prepare的配置

```java
protected BuildWorkPreparer createWorkPreparer(BuildOperationExecutor buildOperationExecutor, 
                                               ExecutionPlanFactory executionPlanFactory) {
    return new BuildOperationFiringBuildWorkPreparer(
        buildOperationExecutor,
        new DefaultBuildWorkPreparer(
            executionPlanFactory
        ));
}
```



> 之后会向线程池中放入一个runnable——ExecutorWorker

```java
// ExecutorWorker.java\

public void run() {
        try {
            boolean releaseLeaseOnCompletion;
            if (workerLease == null) {
                workerLease = workerLeaseService.newWorkerLease();
                releaseLeaseOnCompletion = true;
            } else {
                releaseLeaseOnCompletion = false;
            }

            while (true) {
                // 获取下一个需要执行的worker
                WorkItem workItem = getNextItem(workerLease);
                if (workItem == null) {
                    break;
                }
                Object selected = workItem.selection.getItem();
                LOGGER.info("{} ({}) started.", selected, Thread.currentThread());
                // 执行
                execute(selected, workItem.plan, workItem.executor);
            }

            if (releaseLeaseOnCompletion) {
                coordinationService.withStateLock(() -> workerLease.unlock());
            }
        } finally {
            stats.finish();
        }
    }
```



> 最后经过一系列executor & action之后就开始执行task了(这些不是核心逻辑。)

```java
TaskExecuter createTaskExecuter(
        AsyncWorkTracker asyncWorkTracker,
        BuildCacheController buildCacheController,
        BuildOperationExecutor buildOperationExecutor,
        BuildOutputCleanupRegistry cleanupRegistry,
        GradleEnterprisePluginManager gradleEnterprisePluginManager,
        ClassLoaderHierarchyHasher classLoaderHierarchyHasher,
        Deleter deleter,
        ExecutionHistoryStore executionHistoryStore,
        FileCollectionFactory fileCollectionFactory,
        FileOperations fileOperations,
        ListenerManager listenerManager,
        OutputChangeListener outputChangeListener,
        OutputFilesRepository outputFilesRepository,
        ReservedFileSystemLocationRegistry reservedFileSystemLocationRegistry,
        org.gradle.api.execution.TaskActionListener actionListener,
        TaskCacheabilityResolver taskCacheabilityResolver,
        TaskExecutionGraphInternal taskExecutionGraph,
        org.gradle.api.execution.TaskExecutionListener taskExecutionListener,
        TaskExecutionModeResolver repository,
        TaskListenerInternal taskListenerInternal,
        ExecutionEngine executionEngine,
        InputFingerprinter inputFingerprinter
    ) {
        TaskExecuter executer = new ExecuteActionsTaskExecuter(
            buildCacheController.isEnabled()
                ? ExecuteActionsTaskExecuter.BuildCacheState.ENABLED
                : ExecuteActionsTaskExecuter.BuildCacheState.DISABLED,
            gradleEnterprisePluginManager.isPresent()
                ? ExecuteActionsTaskExecuter.ScanPluginState.APPLIED
                : ExecuteActionsTaskExecuter.ScanPluginState.NOT_APPLIED,
            executionHistoryStore,
            buildOperationExecutor,
            asyncWorkTracker,
            actionListener,
            taskCacheabilityResolver,
            classLoaderHierarchyHasher,
            executionEngine,
            inputFingerprinter,
            listenerManager,
            reservedFileSystemLocationRegistry,
            fileCollectionFactory,
            fileOperations
        );
        executer = new CleanupStaleOutputsExecuter(
            buildOperationExecutor,
            cleanupRegistry,
            deleter,
            outputChangeListener,
            outputFilesRepository,
            executer
        );
        executer = new FinalizePropertiesTaskExecuter(executer);
        executer = new ResolveTaskExecutionModeExecuter(repository, executer);
        executer = new SkipTaskWithNoActionsExecuter(taskExecutionGraph, executer);
        executer = new SkipOnlyIfTaskExecuter(executer);
        executer = new CatchExceptionTaskExecuter(executer);
        executer = new EventFiringTaskExecuter(buildOperationExecutor, taskExecutionListener, taskListenerInternal, executer);
        return executer;
    }
```



> 其中ExecuteActionsTaskExecuter包含了一个ExecutionEngine，这个Engine包含有很多的actions。

```java
 public ExecutionEngine createExecutionEngine(
        BuildCacheController buildCacheController,
        BuildCancellationToken cancellationToken,
        BuildInvocationScopeId buildInvocationScopeId,
        BuildOperationExecutor buildOperationExecutor,
        BuildOutputCleanupRegistry buildOutputCleanupRegistry,
        GradleEnterprisePluginManager gradleEnterprisePluginManager,
        ClassLoaderHierarchyHasher classLoaderHierarchyHasher,
        CurrentBuildOperationRef currentBuildOperationRef,
        Deleter deleter,
        ExecutionStateChangeDetector changeDetector,
        OutputChangeListener outputChangeListener,
        WorkInputListeners workInputListeners, OutputFilesRepository outputFilesRepository,
        OutputSnapshotter outputSnapshotter,
        OverlappingOutputDetector overlappingOutputDetector,
        TimeoutHandler timeoutHandler,
        ValidateStep.ValidationWarningRecorder validationWarningRecorder,
        VirtualFileSystem virtualFileSystem,
        DocumentationRegistry documentationRegistry
    ) {
        Supplier<OutputsCleaner> skipEmptyWorkOutputsCleanerSupplier = () -> new OutputsCleaner(deleter, buildOutputCleanupRegistry::isOutputOwnedByBuild, buildOutputCleanupRegistry::isOutputOwnedByBuild);
        // @formatter:off
        return new DefaultExecutionEngine(documentationRegistry,
            new IdentifyStep<>(
            new IdentityCacheStep<>(
            new AssignWorkspaceStep<>(
            new LoadPreviousExecutionStateStep<>(
            new MarkSnapshottingInputsStartedStep<>(
            new RemoveUntrackedExecutionStateStep<>(
            new SkipEmptyWorkStep(outputChangeListener, workInputListeners, skipEmptyWorkOutputsCleanerSupplier,
            new CaptureStateBeforeExecutionStep<>(buildOperationExecutor, classLoaderHierarchyHasher, outputSnapshotter, overlappingOutputDetector,
            new ValidateStep<>(virtualFileSystem, validationWarningRecorder,
            new ResolveCachingStateStep<>(buildCacheController, gradleEnterprisePluginManager.isPresent(),
            new MarkSnapshottingInputsFinishedStep<>(
            new ResolveChangesStep<>(changeDetector,
            new SkipUpToDateStep<>(
            new RecordOutputsStep<>(outputFilesRepository,
            new StoreExecutionStateStep<>(
            new BuildCacheStep(buildCacheController, deleter, outputChangeListener,
            new ResolveInputChangesStep<>(
            new CaptureStateAfterExecutionStep<>(buildOperationExecutor, buildInvocationScopeId.getId(), outputSnapshotter, outputChangeListener,
            new CreateOutputsStep<>(
            new TimeoutStep<>(timeoutHandler, currentBuildOperationRef,
            new CancelExecutionStep<>(cancellationToken,
            new RemovePreviousOutputsStep<>(deleter, outputChangeListener,
            new ExecuteStep<>(buildOperationExecutor
        ))))))))))))))))))))))));
        // @formatter:on
    }
```



> 最后一个ExecuteStep会触发task的执行。

其中Task是一个简单包裹的数据结构

![image-20240422151308806](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20240422151308806.png)

> 其执行过程，其实也就是把所有的actions都遍历调用execute方法。

```java
  private void executeActions(TaskInternal task, @Nullable InputChangesInternal inputChanges) {
        boolean hasTaskListener = 
            listenerManager.hasListeners(org.gradle.api.execution.TaskActionListener.class) || listenerManager.hasListeners(org.gradle.api.execution.TaskExecutionListener.class);
        Iterator<InputChangesAwareTaskAction> actions = new ArrayList<>(task.getTaskActions()).iterator();
        while (actions.hasNext()) {
            InputChangesAwareTaskAction action = actions.next();
            task.getState().setDidWork(true);
            task.getStandardOutputCapture().start();
            boolean hasMoreWork = hasTaskListener || actions.hasNext();
            try {
                executeAction(action.getDisplayName(), task, action, inputChanges, hasMoreWork);
            } catch (StopActionException e) {
                // Ignore
                LOGGER.debug("Action stopped by some action with message: {}", e.getMessage());
            } catch (StopExecutionException e) {
                LOGGER.info("Execution stopped by some action with message: {}", e.getMessage());
                break;
            } finally {
                task.getStandardOutputCapture().stop();
            }
        }
    }
```



# 缘灭



> 诶~灭不了了。
