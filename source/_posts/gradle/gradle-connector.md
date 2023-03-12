---
title: Gradle之C/S通信
date: 2023-02-21 23:50:50
tags:
- gradle
categories:
- gradle 
---



# Gradle Connector



## 连接建立

> Client和Server通常运行在不同的进程，不同进程的通信最常用的就是socket。

> 确实Gradle也是使用的socket建立C/S的连接

> 对于Gradle来说一个连接既是

```java
public interface Connection<T> extends Dispatch<T>, Receive<T>, Stoppable {
}

public class DaemonClientConnection implements Connection<Message> {}
```

> 所以如果想要创建连接即是实例化一个此类的对象。



`DaemonClient.java`

> 如下

```java
public BuildActionResult execute(BuildAction action, BuildActionParameters parameters, BuildRequestContext requestContext) {
    UUID buildId = idGenerator.generateId();
    // 异常信息
    List<DaemonInitialConnectException> accumulatedExceptions = Lists.newArrayList();

    LOGGER.debug("Executing build {} in daemon client {pid={}}", buildId, processEnvironment.maybeGetPid());

    // 重尝试连接
    int saneNumberOfAttempts = 100;
    for (int i = 1; i < saneNumberOfAttempts; i++) {
        // 建立连接
        final DaemonClientConnection connection = connector.connect(compatibilitySpec);
        // 连接失败
        if (connection == null) {
            break;
        }
        // 连接成功，直接发送执行
        try {
            Build build = new Build(buildId, connection.getDaemon().getToken(), action, requestContext.getClient(), requestContext.getStartTime(), requestContext.isInteractive(), parameters);
            return executeBuild(build, connection, requestContext.getCancellationToken(), requestContext.getEventConsumer());
        } catch (DaemonInitialConnectException e) {
            // 初始化task异常
            LOGGER.debug("{}, Trying a different daemon...", e.getMessage());
            accumulatedExceptions.add(e);
        } finally {
            // 关闭连接
            connection.stop();
        }
    }

    // 没有可复用的连接
    // 开启新的server进程
    final DaemonClientConnection connection = connector.startDaemon(compatibilitySpec);
    try {
        // 执行
        Build build = new Build(buildId, connection.getDaemon().getToken(), action, requestContext.getClient(), requestContext.getStartTime(), requestContext.isInteractive(), parameters);
        return executeBuild(build, connection, requestContext.getCancellationToken(), requestContext.getEventConsumer());
    } catch (DaemonInitialConnectException e) {
        // 异常
        throw new NoUsableDaemonFoundException("A new daemon was started but could not be connected to: " +
            "pid=" + connection.getDaemon() + ", address= " + connection.getDaemon().getAddress() + ". " +
            Documentation.userManual("troubleshooting", "network_connection").consultDocumentationMessage(),
            accumulatedExceptions);
    } finally {
        // 关闭连接
        connection.stop();
    }
}
```



> Connector虽说是一个接口，但是只有一个实现类

```java
public DaemonClientConnection connect(ExplainingSpec<DaemonContext> constraint) {
    // 从文件中读取daemon进行信息
    final Pair<Collection<DaemonInfo>, Collection<DaemonInfo>> idleBusy = partitionByState(daemonRegistry.getAll(), Idle);
    final Collection<DaemonInfo> idleDaemons = idleBusy.getLeft();
    final Collection<DaemonInfo> busyDaemons = idleBusy.getRight();

    // 尝试连接idle daemon进程
    DaemonClientConnection connection = connectToIdleDaemon(idleDaemons, constraint);
    if (connection != null) {
        return connection;
    }

    // 尝试连接被取消的busy进程
    connection = connectToCanceledDaemon(busyDaemons, constraint);
    if (connection != null) {
        return connection;
    }

    // 当前运行的进行都不符合，准备开启新的进程
    handleStopEvents(idleDaemons, busyDaemons);
    return null;
}
```



### 复用idle进程

> 连接符合条件的idle daemon进程

```kotlin
private DaemonClientConnection connectToIdleDaemon(Collection<DaemonInfo> idleDaemons, ExplainingSpec<DaemonContext> constraint) {
    final List<DaemonInfo> compatibleIdleDaemons = getCompatibleDaemons(idleDaemons, constraint);
    return findConnection(compatibleIdleDaemons);
}
```

> 依此尝试连接

```java
private DaemonClientConnection findConnection(List<DaemonInfo> compatibleDaemons) {
    for (DaemonInfo daemon : compatibleDaemons) {
        try {
            return connectToDaemon(daemon, new CleanupOnStaleAddress(daemon, true));
        } catch (ConnectException e) {
            LOGGER.debug("Cannot connect to daemon {} due to {}. Trying a different daemon...", daemon, e);
        }
    }
    return null;
}
```



> 连接

```java
private DaemonClientConnection connectToDaemon(DaemonConnectDetails daemon, DaemonClientConnection.StaleAddressDetector staleAddressDetector) throws ConnectException {
    ProgressLogger progressLogger = progressLoggerFactory.newOperation(DefaultDaemonConnector.class)
        .start("Connecting to Gradle Daemon", "Connecting to Daemon");
    RemoteConnection<Message> connection;
    try {
        connection = connector.connect(daemon.getAddress()).create(Serializers.stateful(serializer));
    } catch (ConnectException e) {
        staleAddressDetector.maybeStaleAddress(e);
        throw e;
    } finally {
        progressLogger.completed();
    }
    return new DaemonClientConnection(connection, daemon, staleAddressDetector);
}
```



`TcpOutgoingConnector.java`

> 连接socket

```java
public ConnectCompletion connect(Address destinationAddress) throws org.gradle.internal.remote.internal.ConnectException {
   //......
    InetEndpoint address = (InetEndpoint) destinationAddress;
   //......
    List<InetAddress> candidateAddresses = address.getCandidates();

    // 对每一个可能的地址进行连接
    try {
        Exception lastFailure = null;
        for (InetAddress candidate : candidateAddresses) {
            LOGGER.debug("Trying to connect to address {}.", candidate);
            SocketChannel socketChannel;
            try {
                socketChannel = tryConnect(address, candidate);
            } catch (SocketException e) {
                LOGGER.debug("Cannot connect to address {}, skipping.", candidate);
                lastFailure = e;
                continue;
            } catch (SocketTimeoutException e) {
                LOGGER.debug("Timeout connecting to address {}, skipping.", candidate);
                lastFailure = e;
                continue;
            }
            LOGGER.debug("Connected to address {}.", socketChannel.socket().getRemoteSocketAddress());
            return new SocketConnectCompletion(socketChannel);
        }
        throw new org.gradle.internal.remote.internal.ConnectException(String.format("Could not connect to server %s. Tried addresses: %s.",
                destinationAddress, candidateAddresses), lastFailure);
    } catch (org.gradle.internal.remote.internal.ConnectException e) { // 异常
        throw e;
    } catch (Exception e) { // 异常
        throw new RuntimeException(String.format("Could not connect to server %s. Tried addresses: %s.",
                destinationAddress, candidateAddresses), e);
    }
}

// 尝试连接
private SocketChannel tryConnect(InetEndpoint address, InetAddress candidate) throws IOException {
        SocketChannel socketChannel = SocketChannel.open();

        try {
            socketChannel.socket().connect(new InetSocketAddress(candidate, address.getPort()), CONNECT_TIMEOUT);

            if (!detectSelfConnect(socketChannel)) {
                return socketChannel;
            }
            socketChannel.close();
        } catch (IOException e) {
            socketChannel.close();
            throw e;
        } catch (Throwable e) {
            socketChannel.close();
            throw UncheckedException.throwAsUncheckedException(e);
        }

        throw new java.net.ConnectException(String.format("Socket connected to itself on %s port %s.", candidate, address.getPort()));
    }
```



> 创建connection实例

```java
@Override
    public <T> RemoteConnection<T> create(StatefulSerializer<T> serializer) {
        // 传入socket，Kryo序列化器，序列化
        return new SocketConnection<T>(socket, new KryoBackedMessageSerializer(), serializer);
    }
```



```java
public SocketConnection(SocketChannel socket, MessageSerializer streamSerializer, StatefulSerializer<T> messageSerializer) {
    this.socket = socket;
    try {
        // NOTE: we use non-blocking IO as there is no reliable way when using blocking IO to shutdown reads while
        // keeping writes active. For example, Socket.shutdownInput() does not work on Windows.
        socket.configureBlocking(false);
        outstr = new SocketOutputStream(socket);
        instr = new SocketInputStream(socket);
    } catch (IOException e) {
        throw UncheckedException.throwAsUncheckedException(e);
    }
    InetSocketAddress localSocketAddress = (InetSocketAddress) socket.socket().getLocalSocketAddress();
    localAddress = new SocketInetAddress(localSocketAddress.getAddress(), localSocketAddress.getPort());
    InetSocketAddress remoteSocketAddress = (InetSocketAddress) socket.socket().getRemoteSocketAddress();
    remoteAddress = new SocketInetAddress(remoteSocketAddress.getAddress(), remoteSocketAddress.getPort());
    objectReader = messageSerializer.newReader(streamSerializer.newDecoder(instr));
    encoder = streamSerializer.newEncoder(outstr);
    objectWriter = messageSerializer.newWriter(encoder);
}
```



### 复用busy进程

> 连接已经取消任务的busy 进程

```java
private DaemonClientConnection connectToCanceledDaemon(Collection<DaemonInfo> busyDaemons, ExplainingSpec<DaemonContext> constraint) {
    DaemonClientConnection connection = null;
    final Pair<Collection<DaemonInfo>, Collection<DaemonInfo>> canceledBusy = partitionByState(busyDaemons, Canceled);
    // 获取兼容的进程
    final Collection<DaemonInfo> compatibleCanceledDaemons = getCompatibleDaemons(canceledBusy.getLeft(), constraint);
    if (!compatibleCanceledDaemons.isEmpty()) {
        LOGGER.info(DaemonMessages.WAITING_ON_CANCELED);
        // 定时连接
        CountdownTimer timer = Time.startCountdownTimer(CANCELED_WAIT_TIMEOUT);
        while (connection == null && !timer.hasExpired()) {
            try {
                sleep(200);
                connection = connectToIdleDaemon(daemonRegistry.getIdle(), constraint);
            } catch (InterruptedException e) {
                throw UncheckedException.throwAsUncheckedException(e);
            }
        }
    }
    return connection;
}
```



> 连接

```java
private DaemonClientConnection connectToIdleDaemon(Collection<DaemonInfo> idleDaemons, ExplainingSpec<DaemonContext> constraint) {
    final List<DaemonInfo> compatibleIdleDaemons = getCompatibleDaemons(idleDaemons, constraint);
    return findConnection(compatibleIdleDaemons);
}
```



### 开启新的进程

`DefaultDaemonConnector.java`

```java
@Override
public DaemonClientConnection startDaemon(ExplainingSpec<DaemonContext> constraint) {
    return doStartDaemon(constraint, false);
}
```



> 开启daemon进程并连接

```java
private DaemonClientConnection doStartDaemon(ExplainingSpec<DaemonContext> constraint, boolean singleRun) {
    ProgressLogger progressLogger = progressLoggerFactory.newOperation(DefaultDaemonConnector.class)
        .start("Starting Gradle Daemon", "Starting Daemon");
    // 开启进程
    final DaemonStartupInfo startupInfo = daemonStarter.startDaemon(singleRun);
    LOGGER.debug("Started Gradle daemon {}", startupInfo);
    // 定时
    CountdownTimer timer = Time.startCountdownTimer(connectTimeout);
    try {
        // 连接
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



## 消息发送

> 连接既是一个发送者，也是一个接收者

```java
public interface Connection<T> extends Dispatch<T>, Receive<T>, Stoppable {
}
```



> 发送者

```java
public interface Dispatch<T> {
    // 发送消息
    void dispatch(T message);
}
```



`DaemonClientConnection.java`

```java
public void dispatch(Message message) throws DaemonConnectionException {
    LOG.debug("thread {}: dispatching {}", Thread.currentThread().getId(), message.getClass());
    try {
        // ReentrantLock
        dispatchLock.lock();
        try {
            // 发送
            connection.dispatch(message);
            connection.flush();
        } finally {
            dispatchLock.unlock();
        }
    } catch (MessageIOException e) {
        LOG.debug("Problem dispatching message to the daemon. Performing 'on failure' operation...");
        if (!hasReceived && staleAddressDetector.maybeStaleAddress(e)) {
            throw new StaleDaemonAddressException("Could not dispatch a message to the daemon.", e);
        }
        throw new DaemonConnectionException("Could not dispatch a message to the daemon.", e);
    }
}
```



`SocketConnection.java`

> 发送数据

```java
public void dispatch(T message) throws MessageIOException {
    try {
        objectWriter.write(message);
    } catch (ObjectStreamException e) {
        throw new RecoverableMessageIOException(String.format("Could not write message %s to '%s'.", message, remoteAddress), e);
    } catch (ClassNotFoundException e) {
        throw new RecoverableMessageIOException(String.format("Could not write message %s to '%s'.", message, remoteAddress), e);
    } catch (IOException e) {
        throw new RecoverableMessageIOException(String.format("Could not write message %s to '%s'.", message, remoteAddress), e);
    } catch (Throwable e) {
        throw new MessageIOException(String.format("Could not write message %s to '%s'.", message, remoteAddress), e);
    }
}
```



```java
@Override
public ObjectWriter<T> newWriter(final Encoder encoder) {
    return new ObjectWriter<T>() {
        @Override
        public void write(T value) throws Exception {
            // 序列化后发送
            serializer.write(encoder, value);
        }
    };
}
```



`DefaultSerializerRegistry.java`

```java
public void write(Encoder encoder, T value) throws Exception {
    // 获取需要序列化的消息
    TypeInfo typeInfo = map(value.getClass());
    // 写入类型
    encoder.writeSmallInt(typeInfo.tag);
    // 获取指定的序列化器并写入实体
    Cast.<Serializer<T>>uncheckedNonnullCast(typeInfo.serializer).write(encoder, value);
}
```

> 由于发送的是`Build`所以使用了如下序列化器

`BuildSerializer.java`

```java
public void write(Encoder encoder, Build build) throws Exception {
    encoder.writeLong(build.getIdentifier().getMostSignificantBits());
    encoder.writeLong(build.getIdentifier().getLeastSignificantBits());
    encoder.writeBinary(build.getToken());
    encoder.writeLong(build.getStartTime());
    encoder.writeBoolean(build.isInteractive());
    buildActionSerializer.write(encoder, build.getAction());
    GradleLauncherMetaData metaData = (GradleLauncherMetaData) build.getBuildClientMetaData();
    encoder.writeString(metaData.getAppName());
    buildActionParametersSerializer.write(encoder, build.getParameters());
}
```



> 关于序列化器

> 支持read读取和write写入

```java
public interface Serializer<T> {
    /**
     * Reads the next object from the given stream. The implementation must not perform any buffering, so that it reads only those bytes from the input stream that are
     * required to deserialize the next object.
     *
     * @throws EOFException When the next object cannot be fully read due to reaching the end of stream.
     */
    T read(Decoder decoder) throws EOFException, Exception;

    /**
     * Writes the given object to the given stream. The implementation must not perform any buffering.
     */
    void write(Encoder encoder, T value) throws Exception;
}
```



> 每一个可序列化的事件都会有一个序列化器

![image-20230312173501101](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230312173501101.png)



## 消息接受

```java
public interface Receive<T> {
    /**
     * Blocks until the next message is available. Returns null when the end of the message stream has been reached.
     *
     * @return The next message, or null when the end of the stream has been reached.
     */
    @Nullable
    T receive();
}
```

`DaemonClientConnection.java`

```java
public Message receive() throws DaemonConnectionException {
    try {
        return connection.receive();
    } catch (MessageIOException e) {
        LOG.debug("Problem receiving message to the daemon. Performing 'on failure' operation...");
        if (!hasReceived && staleAddressDetector.maybeStaleAddress(e)) {
            throw new StaleDaemonAddressException("Could not receive a message from the daemon.", e);
        }
        throw new DaemonConnectionException("Could not receive a message from the daemon.", e);
    } finally {
        hasReceived = true;
    }
}
```

`SocketConnection.java`

```java
public T receive() throws MessageIOException {
    try {
        return objectReader.read();
    } catch (EOFException e) {
        if (LOGGER.isDebugEnabled()) {
            LOGGER.debug("Discarding EOFException: {}", e.toString());
        }
        return null;
    } catch (ObjectStreamException e) {
        throw new RecoverableMessageIOException(String.format("Could not read message from '%s'.", remoteAddress), e);
    } catch (ClassNotFoundException e) {
        throw new RecoverableMessageIOException(String.format("Could not read message from '%s'.", remoteAddress), e);
    } catch (IOException e) {
        throw new RecoverableMessageIOException(String.format("Could not read message from '%s'.", remoteAddress), e);
    } catch (Throwable e) {
        throw new MessageIOException(String.format("Could not read message from '%s'.", remoteAddress), e);
    }

}
```

> 使用序列化器进行读取

```java
public ObjectReader<T> newReader(final Decoder decoder) {
    return new ObjectReader<T>() {
        @Override
        public T read() throws Exception {
            return serializer.read(decoder);
        }
    };
}
```



## 总结



- Gradle C/S连接的建立依托于Socket
- Server的相关信息会写入到文件中，Client需要建立连接的时候会优先读取文件内容，从而确认服务端的端口号，如果没有满足的服务端进程才会考虑开启新的进程
- C/S的通过依靠`SocketConnection<T>`对象完成，C/S预先定义了交互的事件。消息对象发送会先经过Kryo（一个序列化框架）进行序列化，然后再通过Socket发送。

