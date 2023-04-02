---
title: Gson源代码解析
date: 2023-03-30 22:37:54
tags:
- android
---



# Gson源码解析

> 源码版本基于2.10.1

## 分析方向



> 由于Gson是用于做序列化和反序列的一个框架。所以核心方法也就两个
>
> - `toJson`
> - `fromJson`
>
> 后续也只会对如上两个方法进行分析



## toJson



> toJson方法有不少的重载方法，不过按类型划分就两种。
>
> - Object -> String
> - JsonElement -> String
>
> 由于JsonElement用于序列化的情况比较少见，所以真正采用的只有Object-> String的序列化



![image-20230330231227677](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230330231227677.png)

> 之后会对`public String toJson(Object src) `进行分析

```java
public String toJson(Object src) {
    // 对null值进行序列化
  if (src == null) {
    return toJson(JsonNull.INSTANCE);
  }
    // 非空值序列化
  return toJson(src, src.getClass());
}
```

> 非null object序列化

```java
public String toJson(Object src, Type typeOfSrc) {
  // writer
  StringWriter writer = new StringWriter();
  // 序列化并将结果写入到writer中
  toJson(src, typeOfSrc, writer);
  // 输出writer结果
  return writer.toString();
}
```

> 序列化

```java
public void toJson(Object src, Type typeOfSrc, Appendable writer) throws JsonIOException {
  try {
      // 创建writer
    JsonWriter jsonWriter = newJsonWriter(Streams.writerForAppendable(writer));
      // 进行序列化操作
    toJson(src, typeOfSrc, jsonWriter);
  } catch (IOException e) {
    throw new JsonIOException(e);
  }
}
```

> 序列化过程

```java
public void toJson(Object src, Type typeOfSrc, JsonWriter writer) throws JsonIOException {
    @SuppressWarnings("unchecked")
    // 获取适配器
    TypeAdapter<Object> adapter = (TypeAdapter<Object>) getAdapter(TypeToken.get(typeOfSrc));
    // 是否进行宽松解析（即如果json不满足json规范是否抛异常）
    boolean oldLenient = writer.isLenient();
    writer.setLenient(true);
    // 是否对html标签进行转义（转为unicode）
    boolean oldHtmlSafe = writer.isHtmlSafe();
    writer.setHtmlSafe(htmlSafe);
    // 是否对null值进行序列化
    boolean oldSerializeNulls = writer.getSerializeNulls();
    writer.setSerializeNulls(serializeNulls);
    try {
        // 通过适配器进行序列化操作。
        // 并将结果写入writer中
      adapter.write(writer, src);
    } catch (IOException e) {
      throw new JsonIOException(e);
    } catch (AssertionError e) {
      throw new AssertionError("AssertionError (GSON " + GsonBuildConfig.VERSION + "): " + e.getMessage(), e);
    } finally {
      writer.setLenient(oldLenient);
      writer.setHtmlSafe(oldHtmlSafe);
      writer.setSerializeNulls(oldSerializeNulls);
    }
  }
```



### adapter



> 可以发现gson的序列化采用了适配器设计模式，即object -> json string的过程时由adapter完成的。



```java
public <T> TypeAdapter<T> getAdapter(TypeToken<T> type) {
    // 非空断言
  Objects.requireNonNull(type, "type must not be null");
    // 获取缓存的typeAdapter
  TypeAdapter<?> cached = typeTokenCache.get(type);
    // 如果缓存中含有，直接返回
  if (cached != null) {
    @SuppressWarnings("unchecked")
    TypeAdapter<T> adapter = (TypeAdapter<T>) cached;
    return adapter;
  }
	// 缓存中不包含，获取ThreadLocal中的adapter
  Map<TypeToken<?>, TypeAdapter<?>> threadCalls = threadLocalAdapterResults.get();
  boolean isInitialAdapterRequest = false;
    // 如果threadlocal没有初始化
  if (threadCalls == null) {
    threadCalls = new HashMap<>();
    threadLocalAdapterResults.set(threadCalls);
    isInitialAdapterRequest = true;
  } else {
      // 如果已经初始化
    @SuppressWarnings("unchecked")
    TypeAdapter<T> ongoingCall = (TypeAdapter<T>) threadCalls.get(type);
    if (ongoingCall != null) {
      return ongoingCall;
    }
  }

  TypeAdapter<T> candidate = null;
  try {
      // 创建adapter
    FutureTypeAdapter<T> call = new FutureTypeAdapter<>();
      // 放入
    threadCalls.put(type, call);
	// 遍历所有的factory
    for (TypeAdapterFactory factory : factories) {
        // 创建adapter
      candidate = factory.create(this, type);
      if (candidate != null) {
        call.setDelegate(candidate);
        // 存入threadCalls
        threadCalls.put(type, candidate);
        break;
      }
    }
  } finally {
      // 移除threadlocal
    if (isInitialAdapterRequest) {
      threadLocalAdapterResults.remove();
    }
  }

  if (candidate == null) {
    throw new IllegalArgumentException("GSON (" + GsonBuildConfig.VERSION + ") cannot handle " + type);
  }

  if (isInitialAdapterRequest) {
    // 将threadLocal的adapter存入缓存中
    typeTokenCache.putAll(threadCalls);
  }
  return candidate;
}
```



### factory



> `Gson`的序列化使用`TypeAdapter`进行适配，而`TypeAdapter`是由`TypeAdapterFactory`进行创建



> `TypeAdapterFactory`是存放在Gson一个成员里卖弄

```java
for (TypeAdapterFactory factory : factories) {
  candidate = factory.create(this, type);
  if (candidate != null) {
    call.setDelegate(candidate);
    // Replace future adapter with actual adapter
    threadCalls.put(type, candidate);
    break;
  }
}
```

> factory存放在一个List里面

```java
final List<TypeAdapterFactory> factories;
```

> factory生成

```java
 Gson(Excluder excluder, FieldNamingStrategy fieldNamingStrategy,
      Map<Type, InstanceCreator<?>> instanceCreators, boolean serializeNulls,
      boolean complexMapKeySerialization, boolean generateNonExecutableGson, boolean htmlSafe,
      boolean prettyPrinting, boolean lenient, boolean serializeSpecialFloatingPointValues,
      boolean useJdkUnsafe,
      LongSerializationPolicy longSerializationPolicy, String datePattern, int dateStyle,
      int timeStyle, List<TypeAdapterFactory> builderFactories,
      List<TypeAdapterFactory> builderHierarchyFactories,
      List<TypeAdapterFactory> factoriesToBeAdded,
      ToNumberStrategy objectToNumberStrategy, ToNumberStrategy numberToNumberStrategy,
      List<ReflectionAccessFilter> reflectionFilters) {
     // ......
     
     
	List<TypeAdapterFactory> factories = new ArrayList<>();

    // built-in type adapters that cannot be overridden
     // JsonElement适配器
    factories.add(TypeAdapters.JSON_ELEMENT_FACTORY);
     // object转数字的转化策略
    factories.add(ObjectTypeAdapter.getFactory(objectToNumberStrategy));

    // 排除器
    factories.add(excluder);

    // 用户自定义的类型适配器
    factories.addAll(factoriesToBeAdded);

    // 基础的类型适配器
     // 包含： 基础数据类型（int，float，double等），常见的数据类型（AtomicInteger，URL，BigInteger，BigDecimal等）
    factories.add(TypeAdapters.STRING_FACTORY);
    factories.add(TypeAdapters.INTEGER_FACTORY);
    factories.add(TypeAdapters.BOOLEAN_FACTORY);
    factories.add(TypeAdapters.BYTE_FACTORY);
    factories.add(TypeAdapters.SHORT_FACTORY);
    TypeAdapter<Number> longAdapter = longAdapter(longSerializationPolicy);
    factories.add(TypeAdapters.newFactory(long.class, Long.class, longAdapter));
    factories.add(TypeAdapters.newFactory(double.class, Double.class,
            doubleAdapter(serializeSpecialFloatingPointValues)));
    factories.add(TypeAdapters.newFactory(float.class, Float.class,
            floatAdapter(serializeSpecialFloatingPointValues)));
    factories.add(NumberTypeAdapter.getFactory(numberToNumberStrategy));
    factories.add(TypeAdapters.ATOMIC_INTEGER_FACTORY);
    factories.add(TypeAdapters.ATOMIC_BOOLEAN_FACTORY);
    factories.add(TypeAdapters.newFactory(AtomicLong.class, atomicLongAdapter(longAdapter)));
    factories.add(TypeAdapters.newFactory(AtomicLongArray.class, atomicLongArrayAdapter(longAdapter)));
    factories.add(TypeAdapters.ATOMIC_INTEGER_ARRAY_FACTORY);
    factories.add(TypeAdapters.CHARACTER_FACTORY);
    factories.add(TypeAdapters.STRING_BUILDER_FACTORY);
    factories.add(TypeAdapters.STRING_BUFFER_FACTORY);
    factories.add(TypeAdapters.newFactory(BigDecimal.class, TypeAdapters.BIG_DECIMAL));
    factories.add(TypeAdapters.newFactory(BigInteger.class, TypeAdapters.BIG_INTEGER));
    // Add adapter for LazilyParsedNumber because user can obtain it from Gson and then try to serialize it again
    factories.add(TypeAdapters.newFactory(LazilyParsedNumber.class, TypeAdapters.LAZILY_PARSED_NUMBER));
    factories.add(TypeAdapters.URL_FACTORY);
    factories.add(TypeAdapters.URI_FACTORY);
    factories.add(TypeAdapters.UUID_FACTORY);
    factories.add(TypeAdapters.CURRENCY_FACTORY);
    factories.add(TypeAdapters.LOCALE_FACTORY);
    factories.add(TypeAdapters.INET_ADDRESS_FACTORY);
    factories.add(TypeAdapters.BIT_SET_FACTORY);
    factories.add(DateTypeAdapter.FACTORY);
    factories.add(TypeAdapters.CALENDAR_FACTORY);

    if (SqlTypesSupport.SUPPORTS_SQL_TYPES) {
      factories.add(SqlTypesSupport.TIME_FACTORY);
      factories.add(SqlTypesSupport.DATE_FACTORY);
      factories.add(SqlTypesSupport.TIMESTAMP_FACTORY);
    }
	// array序列化
    factories.add(ArrayTypeAdapter.FACTORY);
    factories.add(TypeAdapters.CLASS_FACTORY);

    factories.add(new CollectionTypeAdapterFactory(constructorConstructor));
    factories.add(new MapTypeAdapterFactory(constructorConstructor, complexMapKeySerialization));
    this.jsonAdapterFactory = new JsonAdapterAnnotationTypeAdapterFactory(constructorConstructor);
    factories.add(jsonAdapterFactory);
    factories.add(TypeAdapters.ENUM_FACTORY);
     // 万能适配器，通过反射可以对任何自定义的bean类进行序列化
    factories.add(new ReflectiveTypeAdapterFactory(
        constructorConstructor, fieldNamingStrategy, excluder, jsonAdapterFactory, reflectionFilters));

    this.factories = Collections.unmodifiableList(factories);

}
```



### ReflectiveTypeAdapterFactory



> factory类型都类似，但是其中比较重要的是，`ReflectiveTypeAdapterFactory`因为大部分的Java Bean都会使用它

```java
@Override
public <T> TypeAdapter<T> create(Gson gson, final TypeToken<T> type) {
    // 获取类型
  Class<? super T> raw = type.getRawType();
	// 如果是基本数据类型
  if (!Object.class.isAssignableFrom(raw)) {
    return null;
  }

  FilterResult filterResult =
      ReflectionAccessFilterHelper.getFilterResult(reflectionFilters, raw);
  if (filterResult == FilterResult.BLOCK_ALL) {
    throw new JsonIOException(
        "ReflectionAccessFilter does not permit using reflection for " + raw
            + ". Register a TypeAdapter for this type or adjust the access filter.");
  }
  boolean blockInaccessible = filterResult == FilterResult.BLOCK_INACCESSIBLE;

  // 适配java record类型
  if (ReflectionHelper.isRecord(raw)) {
    @SuppressWarnings("unchecked")
    TypeAdapter<T> adapter = (TypeAdapter<T>) new RecordAdapter<>(raw,
        getBoundFields(gson, type, raw, blockInaccessible, true), blockInaccessible);
    return adapter;
  }
	// 实例化对象
  ObjectConstructor<T> constructor = constructorConstructor.get(type);
    // 获取类成员，并创建adapter对象
  return new FieldReflectionAdapter<>(constructor, getBoundFields(gson, type, raw, blockInaccessible, false));
}
```



### FieldReflectionAdapter

> write方法
>
> 关于read方法将在之后的fromJson分析

```java
 public void write(JsonWriter out, T value) throws IOException {
      if (value == null) {
        out.nullValue();
        return;
      }
		// object开始
        // 1. 写入参数名称
     	// 2. 将EMPTY_OBJECT标记压入栈内，并写入{（确保{}成对出现）
      out.beginObject();
      try {
          // 写入field参数
        for (BoundField boundField : boundFields.values()) {
          boundField.write(out, value);
        }
      } catch (IllegalAccessException e) {
        throw ReflectionHelper.createExceptionForUnexpectedIllegalAccess(e);
      }
     // object结束
     // 出栈并向JsonWriter写入}
      out.endObject();
    }
```



### 小结



> - 可见的是toJson进行序列化的核心其实就是通过获取adapter然后借用adapter对实现从Object到String的序列化操作。
>
> - 其中有一个万用的Adapter，`FieldReflectionAdapter`他会使用反射去拿所有的Field，并将Field转入基础类型的Adapter。
>
> - Adapter的序列化会触发Field的序列化过程，整个Object就转为了Json字符串



## fromJson



> 和toJson类似，fromJson也会经过几层包装

```java
public <T> T fromJson(String json, Class<T> classOfT) throws JsonSyntaxException {
  T object = fromJson(json, TypeToken.get(classOfT));
  return Primitives.wrap(classOfT).cast(object);
}
```



```java
public <T> T fromJson(String json, TypeToken<T> typeOfT) throws JsonSyntaxException {
  if (json == null) {
    return null;
  }
  StringReader reader = new StringReader(json);
  return fromJson(reader, typeOfT);
}
```



```java
public <T> T fromJson(Reader json, TypeToken<T> typeOfT) throws JsonIOException, JsonSyntaxException {
  JsonReader jsonReader = newJsonReader(json);
  T object = fromJson(jsonReader, typeOfT);
  assertFullConsumption(object, jsonReader);
  return object;
}
```



```java
public <T> T fromJson(JsonReader reader, TypeToken<T> typeOfT) throws JsonIOException, JsonSyntaxException {
  // 设置参数
  boolean isEmpty = true;
  boolean oldLenient = reader.isLenient();
  reader.setLenient(true);
  try {
    reader.peek();
    isEmpty = false;
      // 获取adapter
    TypeAdapter<T> typeAdapter = getAdapter(typeOfT);
      // 读取
    return typeAdapter.read(reader);
  } catch (EOFException e) {
    /*
     * For compatibility with JSON 1.5 and earlier, we return null for empty
     * documents instead of throwing.
     */
    if (isEmpty) {
      return null;
    }
    throw new JsonSyntaxException(e);
  } catch (IllegalStateException e) {
    throw new JsonSyntaxException(e);
  } catch (IOException e) {
    // TODO(inder): Figure out whether it is indeed right to rethrow this as JsonSyntaxException
    throw new JsonSyntaxException(e);
  } catch (AssertionError e) {
    throw new AssertionError("AssertionError (GSON " + GsonBuildConfig.VERSION + "): " + e.getMessage(), e);
  } finally {
    reader.setLenient(oldLenient);
  }
}
```



> 核心读取逻辑

`FieldReflectionAdapter.java`

```java
public T read(JsonReader in) throws IOException {
    // 获取栈顶元素
  if (in.peek() == JsonToken.NULL) {
    in.nextNull();
    return null;
  }
	// 实例化对象
  A accumulator = createAccumulator();

  try {
      // 消费{
    in.beginObject();
    while (in.hasNext()) {
        // 读取属性名
      String name = in.nextName();
        // 获取boundFields
      BoundField field = boundFields.get(name);
        // field == null表明不需要进行序列化
      if (field == null || !field.deserialized) {
        in.skipValue();
      } else {
          // 非null将读取的内容写入对象里面
        readField(accumulator, in, field);
      }
    }
  } catch (IllegalStateException e) {
    throw new JsonSyntaxException(e);
  } catch (IllegalAccessException e) {
    throw ReflectionHelper.createExceptionForUnexpectedIllegalAccess(e);
  }
    // 消费}
  in.endObject();
    // 返回
  return finalize(accumulator);
}
```



### 小结

- fromJson的实现中有一个有些类似于词法解析器的东西，通过JsonReader读取数据，再有Adapter对读取的数据做整合，写入到对象中。

![image-20230331182121951](https://typora-blog-picture.oss-cn-chengdu.aliyuncs.com/blog/image-20230331182121951.png)

- 反序列过程中依然是和Adapter深度关联的，使用Adapter的`read`方法实现从`JsonReader`中读取数据。



## 总结



- Gson的序列化采用了**适配器**的设计模式实现了Object -> JSON 和JSON -> Object的转换
- `toJson`方法在转化Json的时候会有层级关系，所以JsonWriter会维护一个栈，遇上json object，json array，等都会进行压栈，结束层级就会出栈。
- `fromJson`方法在转化Object的过程中需要一一读取字符，JsonReader中封装了较多相关的方法，采用了一种类似于**词法解析**的方法，在**有限的状态**间进行转换。



