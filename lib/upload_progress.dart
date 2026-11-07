/// 上传进度：已发字节 / 总字节。两个平台实现共用这一个签名。
typedef UploadProgress = void Function(int got, int total);
