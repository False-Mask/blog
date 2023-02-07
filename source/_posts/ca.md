# CA证书

> CA证书是https必不可少的东西，它包含了非对称加密的公钥信息，以及证书持有方的基本信息，以及颁发机构的信息。主要还是为了保证公钥的权威性，确保公钥的来源是可信的。



## 证书类型

- der： .DER = DER扩展用于二进制DER编码证书。这些文件也可能承载CER或CRT扩展。
- pem：使⽤Base64 ASCII进⾏编码的纯⽂本格式，是以“ - BEGIN …”前缀的ASCII（Base64）数据。
- key：.KEY 扩展名用于公钥和私钥，常见使用于私钥。也可以被编码为二进制DER或ASCII PEM。
- crs：证书签名请求。CSR文件是申请SSL证书时所需要的一个数据文件。
- crt：CRT扩展用于证书。 证书可以被编码为二进制DER或ASCII PEM。 CER和CRT扩展几乎是同义词。 最常见的于Unix 或类Unix系统。通俗来讲，.CRT文件常在Linux系统使用，包含公钥和主体信息。
- crt：.CRT的替代形式,您可以在微软系统环境下将.CRT转换为.CER（.both DER编码的.CER，或base64 [PEM]编码的.cer）。通俗来讲，就是.CER扩展文件是DER编码,并且.CER文件常在Windows系统使用。
- p12：P12证书全称是PKCS#12。是一种交换数字证书的加密标准，用来描述个人身份信息。p12证书包含了私钥、公钥并且有口令保护，在证书泄露后还有最后一道保障——证书口令，不知道正确的证书口令无法提取秘钥（文件的扩展名能够为pfx或p12）
- pfx：PFX也是由PKCS#12标准定义，包含了公钥和私钥的二进制格式的证书形式，以pfx做为证书文件后缀名（文件的扩展名能够为pfx或p12）
- jks：JKS是JAVA的keytools证书工具支持的证书私钥格式
  



## 自签CA证书



### 环境需要

- openssl



### 生成私钥

```shell
openssl genrsa -out ca.key 2048
```

- out输出文件名称
- 2048输出长度



### 生成根证书

```shell
 openssl req -new -x509 -days 3650 -key a.key -out a.crt
```

- req表示行为为证书请求
- -new 生成证书
- -x509生成x509格式证书
- -day证书有效期
- -key私钥
- -out输出文件名称

需要信息填写：（可以乱写）



点击证书查看详细可以发现处于证书链的top因此叫根证书。





### 生成服务端证书

> 同之前根证书的生成

```shell
openssl genrsa -out server.key 2048
```



> 生成request文件即crt文件

```shell
openssl req -new -key server.key -out server.csr
```

与根证书类似，只是少了-x509.

> Note:
>
> Common Name (e.g. server FQDN or YOUR name) []:
>
> 不能乱写，需要填上授权主机的域名，或者ip，否则客户端校验的过程会出错。
>
> 
>
> A challenge password []:
>
> 可以不填，但是如果填了，客户端证书的密码需要和其一致。





> 生成服务端证书

```shell
openssl x509 -req -sha256 -in server.csr -CA a.crt -CAkey a.key -CAcreateserial -days 3650 -out server.crt
```

- -sha256摘要格式
- -CA由哪个ca机构颁发
- -CAcreateserial 生成唯一序列号



### 生成客户端证书



> 生成公钥加密私钥

```shell
openssl genrsa -out client.key 2048
```



> 生成req文件

```shell
 openssl req -new -key client.key -out client.csr
```



> 根据生成客户端证书

```shell
openssl x509 -req -sha256 -in client.csr -CA a.crt -CAkey a.key -CAcreateserial -days 3650 -out client.crt
```

