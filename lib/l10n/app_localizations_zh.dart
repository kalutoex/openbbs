// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class LZh extends L {
  LZh([String locale = 'zh']) : super(locale);

  @override
  String get ok => '好';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get retry => '重试';

  @override
  String get copy => '复制';

  @override
  String get close => '关闭';

  @override
  String get done => '完成';

  @override
  String get confirm => '确认';

  @override
  String get send => '发送';

  @override
  String get submit => '提交';

  @override
  String get back => '返回';

  @override
  String get search => '搜索';

  @override
  String get refresh => '刷新';

  @override
  String get share => '分享';

  @override
  String get report => '举报';

  @override
  String get more => '更多';

  @override
  String get loading => '加载中…';

  @override
  String get emptyList => '这里还没有东西';

  @override
  String get noMore => '没有更多了';

  @override
  String get networkError => '网络不太行，等会儿再试';

  @override
  String get unknownError => '出了点问题';

  @override
  String get retryLater => '稍后再试';

  @override
  String get login => '登录';

  @override
  String get logout => '退出登录';

  @override
  String get register => '注册';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get email => '邮箱';

  @override
  String get forgotPassword => '忘记密码';

  @override
  String get settings => '设置';

  @override
  String get about => '关于';

  @override
  String get accounts => '账号';

  @override
  String get friends => '朋友';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get accentColor => '主题色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get home => '首页';

  @override
  String get forums => '板块';

  @override
  String get notice => '通知';

  @override
  String get me => '我';

  @override
  String get newThread => '发帖';

  @override
  String get title => '标题';

  @override
  String get body => '正文';

  @override
  String get publish => '发布';

  @override
  String get reply => '回复';

  @override
  String get addImage => '添加图片';

  @override
  String get confirmDelete => '删了就找不回来，确定？';

  @override
  String get confirmLogout => '确定要退出登录？';

  @override
  String get unsavedChanges => '有没保存的内容，确定离开？';

  @override
  String get errNotConfigured => '还没设置服务器地址';

  @override
  String get errUploadNoUrl => '上传没返回地址';

  @override
  String errUploadFailed(String reason) {
    return '上传失败：$reason';
  }

  @override
  String errBadResponse(int status) {
    return '服务器返回了看不懂的东西（$status）';
  }

  @override
  String errRequestFailed(int status) {
    return '请求失败（$status）';
  }

  @override
  String errDownloadFailed(int status) {
    return '下载失败（$status）';
  }
}
