import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'好'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @submit.
  ///
  /// In zh, this message translates to:
  /// **'提交'**
  String get submit;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @report.
  ///
  /// In zh, this message translates to:
  /// **'举报'**
  String get report;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get loading;

  /// No description provided for @emptyList.
  ///
  /// In zh, this message translates to:
  /// **'这里还没有东西'**
  String get emptyList;

  /// No description provided for @noMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多了'**
  String get noMore;

  /// No description provided for @networkError.
  ///
  /// In zh, this message translates to:
  /// **'网络不太行，等会儿再试'**
  String get networkError;

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'出了点问题'**
  String get unknownError;

  /// No description provided for @retryLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后再试'**
  String get retryLater;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @register.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get register;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get email;

  /// No description provided for @forgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码'**
  String get forgotPassword;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @accounts.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get accounts;

  /// No description provided for @friends.
  ///
  /// In zh, this message translates to:
  /// **'朋友'**
  String get friends;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @accentColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get accentColor;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get home;

  /// No description provided for @forums.
  ///
  /// In zh, this message translates to:
  /// **'板块'**
  String get forums;

  /// No description provided for @notice.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get notice;

  /// No description provided for @me.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get me;

  /// No description provided for @newThread.
  ///
  /// In zh, this message translates to:
  /// **'发帖'**
  String get newThread;

  /// No description provided for @title.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get title;

  /// No description provided for @body.
  ///
  /// In zh, this message translates to:
  /// **'正文'**
  String get body;

  /// No description provided for @publish.
  ///
  /// In zh, this message translates to:
  /// **'发布'**
  String get publish;

  /// No description provided for @reply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get reply;

  /// No description provided for @addImage.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get addImage;

  /// No description provided for @confirmDelete.
  ///
  /// In zh, this message translates to:
  /// **'删了就找不回来，确定？'**
  String get confirmDelete;

  /// No description provided for @confirmLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录？'**
  String get confirmLogout;

  /// No description provided for @unsavedChanges.
  ///
  /// In zh, this message translates to:
  /// **'有没保存的内容，确定离开？'**
  String get unsavedChanges;

  /// No description provided for @errNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'还没设置服务器地址'**
  String get errNotConfigured;

  /// No description provided for @errUploadNoUrl.
  ///
  /// In zh, this message translates to:
  /// **'上传没返回地址'**
  String get errUploadNoUrl;

  /// No description provided for @errUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：{reason}'**
  String errUploadFailed(String reason);

  /// No description provided for @errBadResponse.
  ///
  /// In zh, this message translates to:
  /// **'服务器返回了看不懂的东西（{status}）'**
  String errBadResponse(int status);

  /// No description provided for @errRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败（{status}）'**
  String errRequestFailed(int status);

  /// No description provided for @errDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败（{status}）'**
  String errDownloadFailed(int status);

  /// No description provided for @needLogin.
  ///
  /// In zh, this message translates to:
  /// **'先登录'**
  String get needLogin;

  /// No description provided for @forgetIt.
  ///
  /// In zh, this message translates to:
  /// **'算了'**
  String get forgetIt;

  /// No description provided for @follow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get follow;

  /// No description provided for @connectFailed.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器：{v1}'**
  String connectFailed(String v1);

  /// No description provided for @myFavorites.
  ///
  /// In zh, this message translates to:
  /// **'我的收藏'**
  String get myFavorites;

  /// No description provided for @browseHistory.
  ///
  /// In zh, this message translates to:
  /// **'浏览历史'**
  String get browseHistory;

  /// No description provided for @notLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'还没登录'**
  String get notLoggedIn;

  /// No description provided for @menu.
  ///
  /// In zh, this message translates to:
  /// **'菜单'**
  String get menu;

  /// No description provided for @densityNormal.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get densityNormal;

  /// No description provided for @timeline.
  ///
  /// In zh, this message translates to:
  /// **'时间线'**
  String get timeline;

  /// No description provided for @deleteIt.
  ///
  /// In zh, this message translates to:
  /// **'删掉'**
  String get deleteIt;

  /// No description provided for @postDeleted.
  ///
  /// In zh, this message translates to:
  /// **'帖子已删'**
  String get postDeleted;

  /// No description provided for @emailAndCodeRequired.
  ///
  /// In zh, this message translates to:
  /// **'邮箱和验证码都要填'**
  String get emailAndCodeRequired;

  /// No description provided for @maxImages.
  ///
  /// In zh, this message translates to:
  /// **'最多 {v1} 张'**
  String maxImages(String v1);

  /// No description provided for @imageStillTooBig.
  ///
  /// In zh, this message translates to:
  /// **'有张图压完还是太大，跳过了'**
  String get imageStillTooBig;

  /// No description provided for @addImageShort.
  ///
  /// In zh, this message translates to:
  /// **'加图'**
  String get addImageShort;

  /// No description provided for @accept.
  ///
  /// In zh, this message translates to:
  /// **'采纳'**
  String get accept;

  /// No description provided for @wontDo.
  ///
  /// In zh, this message translates to:
  /// **'不做'**
  String get wontDo;

  /// No description provided for @endOfList.
  ///
  /// In zh, this message translates to:
  /// **'到底了'**
  String get endOfList;

  /// No description provided for @following.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get following;

  /// No description provided for @sortUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最新回复'**
  String get sortUpdated;

  /// No description provided for @sortCreated.
  ///
  /// In zh, this message translates to:
  /// **'最新发布'**
  String get sortCreated;

  /// No description provided for @connectFailedPlain.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器'**
  String get connectFailedPlain;

  /// No description provided for @server.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get server;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @uploadFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：{v1}'**
  String uploadFailedWith(String v1);

  /// No description provided for @album.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get album;

  /// No description provided for @allowed.
  ///
  /// In zh, this message translates to:
  /// **'已允许'**
  String get allowed;

  /// No description provided for @accountManagement.
  ///
  /// In zh, this message translates to:
  /// **'账号管理'**
  String get accountManagement;

  /// No description provided for @featureRequests.
  ///
  /// In zh, this message translates to:
  /// **'想要的新功能'**
  String get featureRequests;

  /// No description provided for @tapToRetry.
  ///
  /// In zh, this message translates to:
  /// **'点一下重试'**
  String get tapToRetry;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{v1}'**
  String saveFailed(String v1);

  /// No description provided for @deleteThreadConfirm.
  ///
  /// In zh, this message translates to:
  /// **'帖子和下面所有回复一起消失，删了找不回来。'**
  String get deleteThreadConfirm;

  /// No description provided for @pinned.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get pinned;

  /// No description provided for @fillEmailFirst.
  ///
  /// In zh, this message translates to:
  /// **'先填邮箱'**
  String get fillEmailFirst;

  /// No description provided for @accountSecurity.
  ///
  /// In zh, this message translates to:
  /// **'账号安全'**
  String get accountSecurity;

  /// No description provided for @code.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get code;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @pasteCredential.
  ///
  /// In zh, this message translates to:
  /// **'粘贴登录凭证'**
  String get pasteCredential;

  /// No description provided for @ignore.
  ///
  /// In zh, this message translates to:
  /// **'忽略'**
  String get ignore;

  /// No description provided for @loadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get loadMore;

  /// No description provided for @post.
  ///
  /// In zh, this message translates to:
  /// **'帖子'**
  String get post;

  /// No description provided for @resetPassword.
  ///
  /// In zh, this message translates to:
  /// **'重置密码'**
  String get resetPassword;

  /// No description provided for @newPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get newPassword;

  /// No description provided for @albumFailed.
  ///
  /// In zh, this message translates to:
  /// **'打不开相册：{v1}'**
  String albumFailed(String v1);

  /// No description provided for @readImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'读图失败：{v1}'**
  String readImageFailed(String v1);

  /// No description provided for @publishing.
  ///
  /// In zh, this message translates to:
  /// **'发布中…'**
  String get publishing;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get saving;

  /// No description provided for @editPost.
  ///
  /// In zh, this message translates to:
  /// **'编辑帖子'**
  String get editPost;

  /// No description provided for @clearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clearAll;

  /// No description provided for @tryAgain.
  ///
  /// In zh, this message translates to:
  /// **'再试一次'**
  String get tryAgain;

  /// No description provided for @addPeople.
  ///
  /// In zh, this message translates to:
  /// **'加人'**
  String get addPeople;

  /// No description provided for @takeDown.
  ///
  /// In zh, this message translates to:
  /// **'拿下来'**
  String get takeDown;

  /// No description provided for @permissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get permissions;

  /// No description provided for @auto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get auto;

  /// No description provided for @manual.
  ///
  /// In zh, this message translates to:
  /// **'手动'**
  String get manual;

  /// No description provided for @fontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get fontSize;

  /// No description provided for @listDensity.
  ///
  /// In zh, this message translates to:
  /// **'列表密度'**
  String get listDensity;

  /// No description provided for @feedSort.
  ///
  /// In zh, this message translates to:
  /// **'时间线排序'**
  String get feedSort;

  /// No description provided for @startTab.
  ///
  /// In zh, this message translates to:
  /// **'启动页'**
  String get startTab;

  /// No description provided for @sizeSmall.
  ///
  /// In zh, this message translates to:
  /// **'小'**
  String get sizeSmall;

  /// No description provided for @sizeHuge.
  ///
  /// In zh, this message translates to:
  /// **'特大'**
  String get sizeHuge;

  /// No description provided for @sizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大'**
  String get sizeLarge;

  /// No description provided for @densityCompact.
  ///
  /// In zh, this message translates to:
  /// **'紧凑'**
  String get densityCompact;

  /// No description provided for @densityLoose.
  ///
  /// In zh, this message translates to:
  /// **'宽松'**
  String get densityLoose;

  /// No description provided for @chinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @updateChannel.
  ///
  /// In zh, this message translates to:
  /// **'更新通道'**
  String get updateChannel;

  /// No description provided for @clearCache.
  ///
  /// In zh, this message translates to:
  /// **'清除缓存'**
  String get clearCache;

  /// No description provided for @jumpToFloor.
  ///
  /// In zh, this message translates to:
  /// **'跳转楼层'**
  String get jumpToFloor;

  /// No description provided for @changed.
  ///
  /// In zh, this message translates to:
  /// **'改好了'**
  String get changed;

  /// No description provided for @deletePostConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删掉这帖？'**
  String get deletePostConfirm;

  /// No description provided for @edited.
  ///
  /// In zh, this message translates to:
  /// **'已编辑'**
  String get edited;

  /// No description provided for @hueRed.
  ///
  /// In zh, this message translates to:
  /// **'红'**
  String get hueRed;

  /// No description provided for @hueOrangeRed.
  ///
  /// In zh, this message translates to:
  /// **'橙红'**
  String get hueOrangeRed;

  /// No description provided for @hueOrange.
  ///
  /// In zh, this message translates to:
  /// **'橙'**
  String get hueOrange;

  /// No description provided for @hueAmber.
  ///
  /// In zh, this message translates to:
  /// **'橙黄'**
  String get hueAmber;

  /// No description provided for @hueYellow.
  ///
  /// In zh, this message translates to:
  /// **'黄'**
  String get hueYellow;

  /// No description provided for @hueLime.
  ///
  /// In zh, this message translates to:
  /// **'黄绿'**
  String get hueLime;

  /// No description provided for @hueGrass.
  ///
  /// In zh, this message translates to:
  /// **'草绿'**
  String get hueGrass;

  /// No description provided for @hueGreen.
  ///
  /// In zh, this message translates to:
  /// **'绿'**
  String get hueGreen;

  /// No description provided for @hueTeal.
  ///
  /// In zh, this message translates to:
  /// **'青绿'**
  String get hueTeal;

  /// No description provided for @hueCyan.
  ///
  /// In zh, this message translates to:
  /// **'青'**
  String get hueCyan;

  /// No description provided for @hueAzure.
  ///
  /// In zh, this message translates to:
  /// **'青蓝'**
  String get hueAzure;

  /// No description provided for @hueBlue.
  ///
  /// In zh, this message translates to:
  /// **'蓝'**
  String get hueBlue;

  /// No description provided for @hueIndigo.
  ///
  /// In zh, this message translates to:
  /// **'靛蓝'**
  String get hueIndigo;

  /// No description provided for @hueViolet.
  ///
  /// In zh, this message translates to:
  /// **'紫蓝'**
  String get hueViolet;

  /// No description provided for @huePurple.
  ///
  /// In zh, this message translates to:
  /// **'紫'**
  String get huePurple;

  /// No description provided for @hueMagenta.
  ///
  /// In zh, this message translates to:
  /// **'紫红'**
  String get hueMagenta;

  /// No description provided for @huePink.
  ///
  /// In zh, this message translates to:
  /// **'粉'**
  String get huePink;

  /// No description provided for @huePinkLight.
  ///
  /// In zh, this message translates to:
  /// **'浅粉'**
  String get huePinkLight;

  /// No description provided for @permNotificationWhy.
  ///
  /// In zh, this message translates to:
  /// **'有人回复、赞你时提醒你'**
  String get permNotificationWhy;

  /// No description provided for @permPhotosWhy.
  ///
  /// In zh, this message translates to:
  /// **'发帖、回复时从相册选图'**
  String get permPhotosWhy;

  /// No description provided for @permDeniedForever.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝 · 去系统设置开'**
  String get permDeniedForever;

  /// No description provided for @permRestricted.
  ///
  /// In zh, this message translates to:
  /// **'被系统限制'**
  String get permRestricted;

  /// No description provided for @permAsk.
  ///
  /// In zh, this message translates to:
  /// **'未允许 · 点一下申请'**
  String get permAsk;

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 分钟前'**
  String minutesAgo(String v1);

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @bigNumSuffix.
  ///
  /// In zh, this message translates to:
  /// **'{v1}万'**
  String bigNumSuffix(String v1);

  /// No description provided for @am.
  ///
  /// In zh, this message translates to:
  /// **'上午'**
  String get am;

  /// No description provided for @pm.
  ///
  /// In zh, this message translates to:
  /// **'下午'**
  String get pm;

  /// No description provided for @postTimeFmt.
  ///
  /// In zh, this message translates to:
  /// **'{v1}年{v2}月{v3}日, {v4}:{v5} {v6}'**
  String postTimeFmt(
    String v1,
    String v2,
    String v3,
    String v4,
    String v5,
    String v6,
  );

  /// No description provided for @threadSpacing.
  ///
  /// In zh, this message translates to:
  /// **'帖子之间的间距'**
  String get threadSpacing;

  /// No description provided for @browseSection.
  ///
  /// In zh, this message translates to:
  /// **'浏览'**
  String get browseSection;

  /// No description provided for @startTabHint.
  ///
  /// In zh, this message translates to:
  /// **'打开 app 先看哪个'**
  String get startTabHint;

  /// No description provided for @showThumbnails.
  ///
  /// In zh, this message translates to:
  /// **'显示缩略图'**
  String get showThumbnails;

  /// No description provided for @showThumbnailsHint.
  ///
  /// In zh, this message translates to:
  /// **'关掉后时间线只留文字，省流量'**
  String get showThumbnailsHint;

  /// No description provided for @autoCheckNotice.
  ///
  /// In zh, this message translates to:
  /// **'自动检查通知'**
  String get autoCheckNotice;

  /// No description provided for @autoCheckNoticeHint.
  ///
  /// In zh, this message translates to:
  /// **'每分钟问一次未读数'**
  String get autoCheckNoticeHint;

  /// No description provided for @networkSection.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get networkSection;

  /// No description provided for @contentSection.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get contentSection;

  /// No description provided for @clearSearchHistory.
  ///
  /// In zh, this message translates to:
  /// **'清除搜索记录'**
  String get clearSearchHistory;

  /// No description provided for @searchHistoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'搜索记录已清除'**
  String get searchHistoryCleared;

  /// No description provided for @permSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'通知、相册'**
  String get permSubtitle;

  /// No description provided for @currentAccount.
  ///
  /// In zh, this message translates to:
  /// **'当前账号'**
  String get currentAccount;

  /// No description provided for @noEmailBoundHint.
  ///
  /// In zh, this message translates to:
  /// **'还没绑邮箱，忘了密码只能找管理员'**
  String get noEmailBoundHint;

  /// No description provided for @copyCredential.
  ///
  /// In zh, this message translates to:
  /// **'复制登录凭证'**
  String get copyCredential;

  /// No description provided for @copyCredentialHint.
  ///
  /// In zh, this message translates to:
  /// **'重装或换机后，登录页可粘贴恢复'**
  String get copyCredentialHint;

  /// No description provided for @credentialCopied.
  ///
  /// In zh, this message translates to:
  /// **'凭证已复制'**
  String get credentialCopied;

  /// No description provided for @webAccessSection.
  ///
  /// In zh, this message translates to:
  /// **'网页访问'**
  String get webAccessSection;

  /// No description provided for @aboutBrand.
  ///
  /// In zh, this message translates to:
  /// **'关于{v1}'**
  String aboutBrand(String v1);

  /// No description provided for @aboutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'开源信息、更新日志、许可证'**
  String get aboutSubtitle;

  /// No description provided for @logoutShort.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get logoutShort;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @tapToCheckUpdate.
  ///
  /// In zh, this message translates to:
  /// **'点一下检查更新'**
  String get tapToCheckUpdate;

  /// No description provided for @betaChannelHint.
  ///
  /// In zh, this message translates to:
  /// **'内测版，只推给你'**
  String get betaChannelHint;

  /// No description provided for @stableChannelHint.
  ///
  /// In zh, this message translates to:
  /// **'稳定版，所有人都在用'**
  String get stableChannelHint;

  /// No description provided for @stableOption.
  ///
  /// In zh, this message translates to:
  /// **'稳定版　验证过的'**
  String get stableOption;

  /// No description provided for @betaOption.
  ///
  /// In zh, this message translates to:
  /// **'内测版　改一点就推给你'**
  String get betaOption;

  /// No description provided for @betaVersion.
  ///
  /// In zh, this message translates to:
  /// **'内测版 {v1}'**
  String betaVersion(String v1);

  /// No description provided for @newVersion.
  ///
  /// In zh, this message translates to:
  /// **'有新版本 {v1}'**
  String newVersion(String v1);

  /// No description provided for @installOverwrite.
  ///
  /// In zh, this message translates to:
  /// **'大小 {v1}，装完会覆盖当前版本，登录和设置都还在。'**
  String installOverwrite(String v1);

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'以后再说'**
  String get later;

  /// No description provided for @downloadAndInstall.
  ///
  /// In zh, this message translates to:
  /// **'下载并安装'**
  String get downloadAndInstall;

  /// No description provided for @downloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载'**
  String get downloading;

  /// No description provided for @handedToSystem.
  ///
  /// In zh, this message translates to:
  /// **'已交给系统打开'**
  String get handedToSystem;

  /// No description provided for @handedToInstaller.
  ///
  /// In zh, this message translates to:
  /// **'已交给系统安装，没反应就去设置里允许安装未知应用'**
  String get handedToInstaller;

  /// No description provided for @downloadFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'下载失败：{v1}'**
  String downloadFailedWith(String v1);

  /// No description provided for @primaryEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'当前入口'**
  String get primaryEndpoint;

  /// No description provided for @backupEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'备用入口'**
  String get backupEndpoint;

  /// No description provided for @endpointHint.
  ///
  /// In zh, this message translates to:
  /// **'两个地址是同一个站。主入口连不上时会自己走备用那条。'**
  String get endpointHint;

  /// No description provided for @addressCopied.
  ///
  /// In zh, this message translates to:
  /// **'地址已复制'**
  String get addressCopied;

  /// No description provided for @clearing.
  ///
  /// In zh, this message translates to:
  /// **'正在清…'**
  String get clearing;

  /// No description provided for @calculating.
  ///
  /// In zh, this message translates to:
  /// **'正在算…'**
  String get calculating;

  /// No description provided for @cacheEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂时是空的'**
  String get cacheEmpty;

  /// No description provided for @cacheSize.
  ///
  /// In zh, this message translates to:
  /// **'占 {v1}'**
  String cacheSize(String v1);

  /// No description provided for @cleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除'**
  String get cleared;

  /// No description provided for @clearedAmount.
  ///
  /// In zh, this message translates to:
  /// **'已清除 {v1}'**
  String clearedAmount(String v1);

  /// No description provided for @newerThanServer.
  ///
  /// In zh, this message translates to:
  /// **'你手上是 build {v1}，比{v2}版的 {v3} 还新。同签名的包不能往低号装，要回退得先卸载。'**
  String newerThanServer(String v1, String v2, String v3);

  /// No description provided for @upToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版（{v1}）'**
  String upToDate(String v1);

  /// No description provided for @accountLine.
  ///
  /// In zh, this message translates to:
  /// **'{v1} · 本机 {v2} 个账号'**
  String accountLine(String v1, String v2);

  /// No description provided for @betaShort.
  ///
  /// In zh, this message translates to:
  /// **'内测'**
  String get betaShort;

  /// No description provided for @stableShort.
  ///
  /// In zh, this message translates to:
  /// **'稳定'**
  String get stableShort;

  /// No description provided for @releaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'{v1}\n\n大小 {v2}，装完会覆盖当前版本，登录和设置都还在。'**
  String releaseNotes(String v1, String v2);

  /// No description provided for @clearCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'图片和接口缓存都会删掉，下次打开重新下载。\n登录状态和设置不受影响。'**
  String get clearCacheConfirm;

  /// No description provided for @floorJumpHint.
  ///
  /// In zh, this message translates to:
  /// **'输入楼层号，比如 128'**
  String get floorJumpHint;

  /// No description provided for @jump.
  ///
  /// In zh, this message translates to:
  /// **'跳'**
  String get jump;

  /// No description provided for @notReachedFloor.
  ///
  /// In zh, this message translates to:
  /// **'还没翻到第 {v1} 楼'**
  String notReachedFloor(String v1);

  /// No description provided for @noSuchFloor.
  ///
  /// In zh, this message translates to:
  /// **'没有第 {v1} 楼'**
  String noSuchFloor(String v1);

  /// No description provided for @offlineCached.
  ///
  /// In zh, this message translates to:
  /// **'网络不通，下面是上次缓存的内容'**
  String get offlineCached;

  /// No description provided for @pinnedToast.
  ///
  /// In zh, this message translates to:
  /// **'已置顶'**
  String get pinnedToast;

  /// No description provided for @unpinnedToast.
  ///
  /// In zh, this message translates to:
  /// **'已取消置顶'**
  String get unpinnedToast;

  /// No description provided for @featuredToast.
  ///
  /// In zh, this message translates to:
  /// **'已加精'**
  String get featuredToast;

  /// No description provided for @unfeaturedToast.
  ///
  /// In zh, this message translates to:
  /// **'已取消加精'**
  String get unfeaturedToast;

  /// No description provided for @reportReason.
  ///
  /// In zh, this message translates to:
  /// **'举报理由'**
  String get reportReason;

  /// No description provided for @reportSpam.
  ///
  /// In zh, this message translates to:
  /// **'垃圾广告'**
  String get reportSpam;

  /// No description provided for @reportAbuse.
  ///
  /// In zh, this message translates to:
  /// **'人身攻击'**
  String get reportAbuse;

  /// No description provided for @reportIllegal.
  ///
  /// In zh, this message translates to:
  /// **'违法违规'**
  String get reportIllegal;

  /// No description provided for @reportFalse.
  ///
  /// In zh, this message translates to:
  /// **'内容不实'**
  String get reportFalse;

  /// No description provided for @reportOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get reportOther;

  /// No description provided for @reportDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'已经报过一次了'**
  String get reportDuplicate;

  /// No description provided for @reportThanks.
  ///
  /// In zh, this message translates to:
  /// **'收到了，会看'**
  String get reportThanks;

  /// No description provided for @editFloor.
  ///
  /// In zh, this message translates to:
  /// **'改这一楼'**
  String get editFloor;

  /// No description provided for @saySomething.
  ///
  /// In zh, this message translates to:
  /// **'说点什么…'**
  String get saySomething;

  /// No description provided for @replaceWithPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'换成占位图？'**
  String get replaceWithPlaceholder;

  /// No description provided for @replacePlaceholderConfirm.
  ///
  /// In zh, this message translates to:
  /// **'这一帖和下面所有回复里的图都会换成同一张占位图，原图找不回来。'**
  String get replacePlaceholderConfirm;

  /// No description provided for @replacedImages.
  ///
  /// In zh, this message translates to:
  /// **'已换掉 {v1} 张图'**
  String replacedImages(String v1);

  /// No description provided for @deleteFloorConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除这楼？'**
  String get deleteFloorConfirm;

  /// No description provided for @deleteThreadBody.
  ///
  /// In zh, this message translates to:
  /// **'帖子连同所有回复一起删掉，删了不能恢复。'**
  String get deleteThreadBody;

  /// No description provided for @deleteFloorBody.
  ///
  /// In zh, this message translates to:
  /// **'这楼和它下面的楼中楼一起删掉。'**
  String get deleteFloorBody;

  /// No description provided for @deleteReplyConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除这条回复？'**
  String get deleteReplyConfirm;

  /// No description provided for @cannotUndo.
  ///
  /// In zh, this message translates to:
  /// **'删了不能恢复。'**
  String get cannotUndo;

  /// No description provided for @onlyAuthorOn.
  ///
  /// In zh, this message translates to:
  /// **'已只看楼主'**
  String get onlyAuthorOn;

  /// No description provided for @onlyAuthorOff.
  ///
  /// In zh, this message translates to:
  /// **'只看楼主'**
  String get onlyAuthorOff;

  /// No description provided for @jumpToFloorPages.
  ///
  /// In zh, this message translates to:
  /// **'跳转楼层（共 {v1} 页）'**
  String jumpToFloorPages(String v1);

  /// No description provided for @unpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get unpin;

  /// No description provided for @unfeature.
  ///
  /// In zh, this message translates to:
  /// **'取消加精'**
  String get unfeature;

  /// No description provided for @feature.
  ///
  /// In zh, this message translates to:
  /// **'加精'**
  String get feature;

  /// No description provided for @replaceAllImages.
  ///
  /// In zh, this message translates to:
  /// **'一键替换图片'**
  String get replaceAllImages;

  /// No description provided for @deletePost.
  ///
  /// In zh, this message translates to:
  /// **'删除帖子'**
  String get deletePost;

  /// No description provided for @viewsCount.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 浏览'**
  String viewsCount(String v1);

  /// No description provided for @related.
  ///
  /// In zh, this message translates to:
  /// **'相关'**
  String get related;

  /// No description provided for @repliesCount.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 条回复'**
  String repliesCount(String v1);

  /// No description provided for @noReplies.
  ///
  /// In zh, this message translates to:
  /// **'还没有回复'**
  String get noReplies;

  /// No description provided for @favorited.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get favorited;

  /// No description provided for @unfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get unfavorite;

  /// No description provided for @meShort.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get meShort;

  /// No description provided for @replyTo.
  ///
  /// In zh, this message translates to:
  /// **'回复 {v1}'**
  String replyTo(String v1);

  /// No description provided for @replyHint.
  ///
  /// In zh, this message translates to:
  /// **'发布你的回复'**
  String get replyHint;

  /// No description provided for @maxNineImages.
  ///
  /// In zh, this message translates to:
  /// **'最多 9 张'**
  String get maxNineImages;

  /// No description provided for @opAuthor.
  ///
  /// In zh, this message translates to:
  /// **'楼主'**
  String get opAuthor;

  /// No description provided for @copyFullText.
  ///
  /// In zh, this message translates to:
  /// **'复制全文'**
  String get copyFullText;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @collapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get collapse;

  /// No description provided for @expandAllReplies.
  ///
  /// In zh, this message translates to:
  /// **'展开全部 {v1} 条回复'**
  String expandAllReplies(String v1);

  /// No description provided for @resumeDraft.
  ///
  /// In zh, this message translates to:
  /// **'接着上次的写'**
  String get resumeDraft;

  /// No description provided for @resumeDraftImages.
  ///
  /// In zh, this message translates to:
  /// **'接着上次的写，带 {v1} 张图'**
  String resumeDraftImages(String v1);

  /// No description provided for @discardDraft.
  ///
  /// In zh, this message translates to:
  /// **'清掉'**
  String get discardDraft;

  /// No description provided for @pickFromAlbum.
  ///
  /// In zh, this message translates to:
  /// **'从相册选'**
  String get pickFromAlbum;

  /// No description provided for @canAddMore.
  ///
  /// In zh, this message translates to:
  /// **'还能加 {v1} 张'**
  String canAddMore(String v1);

  /// No description provided for @takePhoto.
  ///
  /// In zh, this message translates to:
  /// **'拍一张'**
  String get takePhoto;

  /// No description provided for @cameraFailed.
  ///
  /// In zh, this message translates to:
  /// **'打不开相机：{v1}'**
  String cameraFailed(String v1);

  /// No description provided for @tooManyImages.
  ///
  /// In zh, this message translates to:
  /// **'最多 {v1} 张，多的没收'**
  String tooManyImages(String v1);

  /// No description provided for @deleteThisImage.
  ///
  /// In zh, this message translates to:
  /// **'删掉这张'**
  String get deleteThisImage;

  /// No description provided for @uploadingStart.
  ///
  /// In zh, this message translates to:
  /// **'上传图片 0/{v1}'**
  String uploadingStart(String v1);

  /// No description provided for @uploadingImages.
  ///
  /// In zh, this message translates to:
  /// **'上传图片 {v1}/{v2}'**
  String uploadingImages(String v1, String v2);

  /// No description provided for @postFailed.
  ///
  /// In zh, this message translates to:
  /// **'发不出去：{v1}'**
  String postFailed(String v1);

  /// No description provided for @draftUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'这篇还没发出去'**
  String get draftUnsaved;

  /// No description provided for @draftImagesNote.
  ///
  /// In zh, this message translates to:
  /// **'图片不进草稿，只有标题和正文会留着'**
  String get draftImagesNote;

  /// No description provided for @saveDraftAndLeave.
  ///
  /// In zh, this message translates to:
  /// **'存草稿，先走'**
  String get saveDraftAndLeave;

  /// No description provided for @discardPost.
  ///
  /// In zh, this message translates to:
  /// **'扔掉这篇'**
  String get discardPost;

  /// No description provided for @keepEditing.
  ///
  /// In zh, this message translates to:
  /// **'再改改'**
  String get keepEditing;

  /// No description provided for @composeTitle.
  ///
  /// In zh, this message translates to:
  /// **'发新帖'**
  String get composeTitle;

  /// No description provided for @forumSuffix.
  ///
  /// In zh, this message translates to:
  /// **'吧'**
  String get forumSuffix;

  /// No description provided for @composeHint.
  ///
  /// In zh, this message translates to:
  /// **'说点什么…（@ 找人）'**
  String get composeHint;

  /// No description provided for @imageCount.
  ///
  /// In zh, this message translates to:
  /// **'图片 {v1}/{v2}'**
  String imageCount(String v1, String v2);

  /// No description provided for @dragToReorder.
  ///
  /// In zh, this message translates to:
  /// **'长按拖动换顺序'**
  String get dragToReorder;

  /// No description provided for @titleRequiredMaxImages.
  ///
  /// In zh, this message translates to:
  /// **'标题必填 · 最多 {v1} 张图'**
  String titleRequiredMaxImages(String v1);

  /// No description provided for @imageCountPrefix.
  ///
  /// In zh, this message translates to:
  /// **'{v1}/{v2} 张 · {v3}'**
  String imageCountPrefix(String v1, String v2, String v3);

  /// No description provided for @bodyLength.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 字'**
  String bodyLength(String v1);

  /// No description provided for @credentialHint.
  ///
  /// In zh, this message translates to:
  /// **'在旧设备「设置 → 复制登录凭证」里复制'**
  String get credentialHint;

  /// No description provided for @restore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get restore;

  /// No description provided for @credentialInvalid.
  ///
  /// In zh, this message translates to:
  /// **'凭证无效或已失效'**
  String get credentialInvalid;

  /// No description provided for @restoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{v1}'**
  String restoreFailed(String v1);

  /// No description provided for @codeSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'验证码没发出去：{v1}'**
  String codeSendFailed(String v1);

  /// No description provided for @passwordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 8 位'**
  String get passwordTooShort;

  /// No description provided for @passwordChangeFailed.
  ///
  /// In zh, this message translates to:
  /// **'没改成：{v1}'**
  String passwordChangeFailed(String v1);

  /// No description provided for @fillUserAndPassword.
  ///
  /// In zh, this message translates to:
  /// **'用户名和密码都要填'**
  String get fillUserAndPassword;

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录没成功：{v1}'**
  String loginFailed(String v1);

  /// No description provided for @resetTitle.
  ///
  /// In zh, this message translates to:
  /// **'找回密码'**
  String get resetTitle;

  /// No description provided for @atLeast8.
  ///
  /// In zh, this message translates to:
  /// **'至少 8 位'**
  String get atLeast8;

  /// No description provided for @emailUsedToRegister.
  ///
  /// In zh, this message translates to:
  /// **'注册时用的邮箱'**
  String get emailUsedToRegister;

  /// No description provided for @emailForCode.
  ///
  /// In zh, this message translates to:
  /// **'用来收注册验证码'**
  String get emailForCode;

  /// No description provided for @sending.
  ///
  /// In zh, this message translates to:
  /// **'发送中'**
  String get sending;

  /// No description provided for @getCode.
  ///
  /// In zh, this message translates to:
  /// **'获取验证码'**
  String get getCode;

  /// No description provided for @changePasswordAndLogin.
  ///
  /// In zh, this message translates to:
  /// **'改密码并登录'**
  String get changePasswordAndLogin;

  /// No description provided for @registerAndLogin.
  ///
  /// In zh, this message translates to:
  /// **'注册并登录'**
  String get registerAndLogin;

  /// No description provided for @backToLogin.
  ///
  /// In zh, this message translates to:
  /// **'返回登录'**
  String get backToLogin;

  /// No description provided for @haveAccountLogin.
  ///
  /// In zh, this message translates to:
  /// **'已有账号，去登录'**
  String get haveAccountLogin;

  /// No description provided for @noAccountRegister.
  ///
  /// In zh, this message translates to:
  /// **'没有账号，去注册'**
  String get noAccountRegister;

  /// No description provided for @forgotPasswordQuestion.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？'**
  String get forgotPasswordQuestion;

  /// No description provided for @restoreWithCredential.
  ///
  /// In zh, this message translates to:
  /// **'用登录凭证恢复'**
  String get restoreWithCredential;

  /// No description provided for @accountCopied.
  ///
  /// In zh, this message translates to:
  /// **'账号已复制'**
  String get accountCopied;

  /// No description provided for @coverUpdated.
  ///
  /// In zh, this message translates to:
  /// **'封面已换'**
  String get coverUpdated;

  /// No description provided for @coverFailed.
  ///
  /// In zh, this message translates to:
  /// **'换封面失败：{v1}'**
  String coverFailed(String v1);

  /// No description provided for @saveCover.
  ///
  /// In zh, this message translates to:
  /// **'保存背景图'**
  String get saveCover;

  /// No description provided for @saveCoverConfirm.
  ///
  /// In zh, this message translates to:
  /// **'把这张背景图存到相册？'**
  String get saveCoverConfirm;

  /// No description provided for @savedTo.
  ///
  /// In zh, this message translates to:
  /// **'已保存到 {v1}'**
  String savedTo(String v1);

  /// No description provided for @changeCover.
  ///
  /// In zh, this message translates to:
  /// **'换封面'**
  String get changeCover;

  /// No description provided for @addCover.
  ///
  /// In zh, this message translates to:
  /// **'加封面'**
  String get addCover;

  /// No description provided for @joinedAt.
  ///
  /// In zh, this message translates to:
  /// **'加入于 {v1}'**
  String joinedAt(String v1);

  /// No description provided for @followingCount.
  ///
  /// In zh, this message translates to:
  /// **'正在关注'**
  String get followingCount;

  /// No description provided for @followers.
  ///
  /// In zh, this message translates to:
  /// **'关注者'**
  String get followers;

  /// No description provided for @editProfile.
  ///
  /// In zh, this message translates to:
  /// **'编辑个人资料'**
  String get editProfile;

  /// No description provided for @noPostsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有人发帖'**
  String get noPostsYet;

  /// No description provided for @longAgo.
  ///
  /// In zh, this message translates to:
  /// **'很久以前'**
  String get longAgo;

  /// No description provided for @yearMonth.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 年 {v2} 月'**
  String yearMonth(String v1, String v2);

  /// No description provided for @acceptConfirm.
  ///
  /// In zh, this message translates to:
  /// **'采纳这条？'**
  String get acceptConfirm;

  /// No description provided for @rejectConfirm.
  ///
  /// In zh, this message translates to:
  /// **'不做这条？'**
  String get rejectConfirm;

  /// No description provided for @reopenConfirm.
  ///
  /// In zh, this message translates to:
  /// **'退回待看？'**
  String get reopenConfirm;

  /// No description provided for @replyOptional.
  ///
  /// In zh, this message translates to:
  /// **'回一句（可选）'**
  String get replyOptional;

  /// No description provided for @adminReplyHint.
  ///
  /// In zh, this message translates to:
  /// **'排期中 / 做不了，原因是……'**
  String get adminReplyHint;

  /// No description provided for @accepted.
  ///
  /// In zh, this message translates to:
  /// **'已采纳'**
  String get accepted;

  /// No description provided for @markedWontDo.
  ///
  /// In zh, this message translates to:
  /// **'已标记不做'**
  String get markedWontDo;

  /// No description provided for @movedBack.
  ///
  /// In zh, this message translates to:
  /// **'已退回待看'**
  String get movedBack;

  /// No description provided for @requestsDone.
  ///
  /// In zh, this message translates to:
  /// **'需求 · 已处理'**
  String get requestsDone;

  /// No description provided for @requestsCount.
  ///
  /// In zh, this message translates to:
  /// **'需求（{v1}）'**
  String requestsCount(String v1);

  /// No description provided for @requests.
  ///
  /// In zh, this message translates to:
  /// **'需求'**
  String get requests;

  /// No description provided for @viewPending.
  ///
  /// In zh, this message translates to:
  /// **'看待看'**
  String get viewPending;

  /// No description provided for @viewDone.
  ///
  /// In zh, this message translates to:
  /// **'看已处理'**
  String get viewDone;

  /// No description provided for @nothingHandled.
  ///
  /// In zh, this message translates to:
  /// **'还没处理过'**
  String get nothingHandled;

  /// No description provided for @noPendingRequests.
  ///
  /// In zh, this message translates to:
  /// **'没有待看的需求'**
  String get noPendingRequests;

  /// No description provided for @replyLine.
  ///
  /// In zh, this message translates to:
  /// **'回复：{v1}'**
  String replyLine(String v1);

  /// No description provided for @submittedBy.
  ///
  /// In zh, this message translates to:
  /// **'提交人：{v1}'**
  String submittedBy(String v1);

  /// No description provided for @moveBack.
  ///
  /// In zh, this message translates to:
  /// **'退回待看'**
  String get moveBack;

  /// No description provided for @avatarUpdated.
  ///
  /// In zh, this message translates to:
  /// **'头像已换上 · {v1}'**
  String avatarUpdated(String v1);

  /// No description provided for @chooseFromAlbum.
  ///
  /// In zh, this message translates to:
  /// **'从相册选择'**
  String get chooseFromAlbum;

  /// No description provided for @compressNote.
  ///
  /// In zh, this message translates to:
  /// **'自动压到 100KB 上下再上传'**
  String get compressNote;

  /// No description provided for @nicknameRequired.
  ///
  /// In zh, this message translates to:
  /// **'昵称不能为空'**
  String get nicknameRequired;

  /// No description provided for @handleInvalid.
  ///
  /// In zh, this message translates to:
  /// **'标识只能用小写字母、数字、下划线，3–16 位'**
  String get handleInvalid;

  /// No description provided for @editProfileTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑资料'**
  String get editProfileTitle;

  /// No description provided for @nickname.
  ///
  /// In zh, this message translates to:
  /// **'昵称'**
  String get nickname;

  /// No description provided for @nicknameMax.
  ///
  /// In zh, this message translates to:
  /// **'最多 20 个字'**
  String get nicknameMax;

  /// No description provided for @handle.
  ///
  /// In zh, this message translates to:
  /// **'标识'**
  String get handle;

  /// No description provided for @handleHint.
  ///
  /// In zh, this message translates to:
  /// **'别人用 @ 找到你；小写字母、数字、下划线，3–16 位'**
  String get handleHint;

  /// No description provided for @bio.
  ///
  /// In zh, this message translates to:
  /// **'签名'**
  String get bio;

  /// No description provided for @bioHint.
  ///
  /// In zh, this message translates to:
  /// **'最多 80 个字，可以留空'**
  String get bioHint;

  /// No description provided for @profileSavedHint.
  ///
  /// In zh, this message translates to:
  /// **'改完立刻生效，回主页刷新就能看到。'**
  String get profileSavedHint;

  /// No description provided for @openSource.
  ///
  /// In zh, this message translates to:
  /// **'开源'**
  String get openSource;

  /// No description provided for @thanksFriends.
  ///
  /// In zh, this message translates to:
  /// **'致谢我的朋友们'**
  String get thanksFriends;

  /// No description provided for @thanksFriendsSub.
  ///
  /// In zh, this message translates to:
  /// **'这里是他们的账号'**
  String get thanksFriendsSub;

  /// No description provided for @thirdPartyLicenses.
  ///
  /// In zh, this message translates to:
  /// **'第三方许可证'**
  String get thirdPartyLicenses;

  /// No description provided for @thirdPartyLicensesSub.
  ///
  /// In zh, this message translates to:
  /// **'各依赖自带的许可文本'**
  String get thirdPartyLicensesSub;

  /// No description provided for @gplLicense.
  ///
  /// In zh, this message translates to:
  /// **'GPL-3.0 许可证'**
  String get gplLicense;

  /// No description provided for @gplLicenseSub.
  ///
  /// In zh, this message translates to:
  /// **'本项目以 GPL-3.0 发布'**
  String get gplLicenseSub;

  /// No description provided for @links.
  ///
  /// In zh, this message translates to:
  /// **'链接'**
  String get links;

  /// No description provided for @sourceCode.
  ///
  /// In zh, this message translates to:
  /// **'源代码'**
  String get sourceCode;

  /// No description provided for @issues.
  ///
  /// In zh, this message translates to:
  /// **'问题反馈'**
  String get issues;

  /// No description provided for @issuesSub.
  ///
  /// In zh, this message translates to:
  /// **'发现什么不对，记在这里'**
  String get issuesSub;

  /// No description provided for @cantOpenLink.
  ///
  /// In zh, this message translates to:
  /// **'打不开这个链接'**
  String get cantOpenLink;

  /// No description provided for @reportKeepNote.
  ///
  /// In zh, this message translates to:
  /// **'这条没问题，关掉举报。'**
  String get reportKeepNote;

  /// No description provided for @reportDeleteFloorNote.
  ///
  /// In zh, this message translates to:
  /// **'楼层内容会被删掉，删了找不回来。'**
  String get reportDeleteFloorNote;

  /// No description provided for @reportDeletePostNote.
  ///
  /// In zh, this message translates to:
  /// **'整个帖子连同回复一起删掉，删了找不回来。'**
  String get reportDeletePostNote;

  /// No description provided for @ignoreReportConfirm.
  ///
  /// In zh, this message translates to:
  /// **'忽略这条举报？'**
  String get ignoreReportConfirm;

  /// No description provided for @deleteContentConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删掉这条内容？'**
  String get deleteContentConfirm;

  /// No description provided for @ignored.
  ///
  /// In zh, this message translates to:
  /// **'已忽略'**
  String get ignored;

  /// No description provided for @deleted.
  ///
  /// In zh, this message translates to:
  /// **'已删掉'**
  String get deleted;

  /// No description provided for @reportsCount.
  ///
  /// In zh, this message translates to:
  /// **'举报（{v1}）'**
  String reportsCount(String v1);

  /// No description provided for @noReports.
  ///
  /// In zh, this message translates to:
  /// **'没有待处理的举报'**
  String get noReports;

  /// No description provided for @floor.
  ///
  /// In zh, this message translates to:
  /// **'楼层'**
  String get floor;

  /// No description provided for @reportLine.
  ///
  /// In zh, this message translates to:
  /// **'理由：{v1}　举报人：{v2}'**
  String reportLine(String v1, String v2);

  /// No description provided for @galleryReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'相册读不出来：{v1}'**
  String galleryReadFailed(String v1);

  /// No description provided for @albumOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'这个相册打不开：{v1}'**
  String albumOpenFailed(String v1);

  /// No description provided for @maxSelectImages.
  ///
  /// In zh, this message translates to:
  /// **'最多选 {v1} 张'**
  String maxSelectImages(String v1);

  /// No description provided for @pickPhotos.
  ///
  /// In zh, this message translates to:
  /// **'选择照片'**
  String get pickPhotos;

  /// No description provided for @doneWithCount.
  ///
  /// In zh, this message translates to:
  /// **'完成 ({v1})'**
  String doneWithCount(String v1);

  /// No description provided for @albumEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个相册里没有图片'**
  String get albumEmpty;

  /// No description provided for @needsAlbumPermission.
  ///
  /// In zh, this message translates to:
  /// **'需要相册权限才能列出照片'**
  String get needsAlbumPermission;

  /// No description provided for @noAlbumUsePicker.
  ///
  /// In zh, this message translates to:
  /// **'这台机器没有相册，用系统的文件选择'**
  String get noAlbumUsePicker;

  /// No description provided for @localThumbsOnly.
  ///
  /// In zh, this message translates to:
  /// **'只在本机缩略图里挑，不上传整本相册。'**
  String get localThumbsOnly;

  /// No description provided for @grantPermission.
  ///
  /// In zh, this message translates to:
  /// **'去开权限'**
  String get grantPermission;

  /// No description provided for @pickAnotherWay.
  ///
  /// In zh, this message translates to:
  /// **'换个方式选图'**
  String get pickAnotherWay;

  /// No description provided for @titleClearer.
  ///
  /// In zh, this message translates to:
  /// **'标题再写清楚一点'**
  String get titleClearer;

  /// No description provided for @requestDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'这条已经提过了'**
  String get requestDuplicate;

  /// No description provided for @requestSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'提交好了'**
  String get requestSubmitted;

  /// No description provided for @requestIntro.
  ///
  /// In zh, this message translates to:
  /// **'想到什么功能，写在这里。管理员会看，采纳了会回一句。'**
  String get requestIntro;

  /// No description provided for @requestTitleLabel.
  ///
  /// In zh, this message translates to:
  /// **'一句话说清要什么'**
  String get requestTitleLabel;

  /// No description provided for @requestTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'比如：帖子支持收藏到不同文件夹'**
  String get requestTitleHint;

  /// No description provided for @requestDetailLabel.
  ///
  /// In zh, this message translates to:
  /// **'细节（可选）'**
  String get requestDetailLabel;

  /// No description provided for @requestDetailHint.
  ///
  /// In zh, this message translates to:
  /// **'为什么需要、大概怎么用'**
  String get requestDetailHint;

  /// No description provided for @myRequests.
  ///
  /// In zh, this message translates to:
  /// **'我提过的'**
  String get myRequests;

  /// No description provided for @requestCount.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 条'**
  String requestCount(String v1);

  /// No description provided for @noRequestsYet.
  ///
  /// In zh, this message translates to:
  /// **'还没提过'**
  String get noRequestsYet;

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'待看'**
  String get statusPending;

  /// No description provided for @codeSentCheckEmail.
  ///
  /// In zh, this message translates to:
  /// **'验证码发出去了，去邮箱里看看'**
  String get codeSentCheckEmail;

  /// No description provided for @emailBound.
  ///
  /// In zh, this message translates to:
  /// **'绑好了'**
  String get emailBound;

  /// No description provided for @noEmailWarning.
  ///
  /// In zh, this message translates to:
  /// **'这个账号还没绑邮箱。忘了密码的话，现在只能找管理员重置。'**
  String get noEmailWarning;

  /// No description provided for @emailBoundHint.
  ///
  /// In zh, this message translates to:
  /// **'已绑定，忘了密码可以自己重置'**
  String get emailBoundHint;

  /// No description provided for @bindEmail.
  ///
  /// In zh, this message translates to:
  /// **'绑定邮箱'**
  String get bindEmail;

  /// No description provided for @changeEmail.
  ///
  /// In zh, this message translates to:
  /// **'换一个邮箱'**
  String get changeEmail;

  /// No description provided for @sendCode.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码'**
  String get sendCode;

  /// No description provided for @processing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get processing;

  /// No description provided for @bind.
  ///
  /// In zh, this message translates to:
  /// **'绑定'**
  String get bind;

  /// No description provided for @rebind.
  ///
  /// In zh, this message translates to:
  /// **'换绑'**
  String get rebind;

  /// No description provided for @bindEmailWhy.
  ///
  /// In zh, this message translates to:
  /// **'绑了之后，忘记密码不用找人：登录页点「忘记密码」，收个验证码就能改。'**
  String get bindEmailWhy;

  /// No description provided for @titleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'标题不能空'**
  String get titleEmpty;

  /// No description provided for @bodyOrImageRequired.
  ///
  /// In zh, this message translates to:
  /// **'正文或图片至少留一样'**
  String get bodyOrImageRequired;

  /// No description provided for @uploadingNewStart.
  ///
  /// In zh, this message translates to:
  /// **'上传新图 0/{v1}'**
  String uploadingNewStart(String v1);

  /// No description provided for @uploadingNewImages.
  ///
  /// In zh, this message translates to:
  /// **'上传新图 {v1}/{v2}'**
  String uploadingNewImages(String v1, String v2);

  /// No description provided for @changesUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'改动还没保存'**
  String get changesUnsaved;

  /// No description provided for @continueEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续改'**
  String get continueEditing;

  /// No description provided for @leaveWithoutSaving.
  ///
  /// In zh, this message translates to:
  /// **'不保存，退出'**
  String get leaveWithoutSaving;

  /// No description provided for @imageCountShort.
  ///
  /// In zh, this message translates to:
  /// **'图片 {v1}/{v2}'**
  String imageCountShort(String v1, String v2);

  /// No description provided for @noImagesYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有图'**
  String get noImagesYet;

  /// No description provided for @searchForumsHint.
  ///
  /// In zh, this message translates to:
  /// **'搜吧'**
  String get searchForumsHint;

  /// No description provided for @noSearchResult.
  ///
  /// In zh, this message translates to:
  /// **'没搜到「{v1}」'**
  String noSearchResult(String v1);

  /// No description provided for @searchResultCount.
  ///
  /// In zh, this message translates to:
  /// **'搜到 {v1} 个'**
  String searchResultCount(String v1);

  /// No description provided for @myFollowedForums.
  ///
  /// In zh, this message translates to:
  /// **'我关注的 {v1}'**
  String myFollowedForums(String v1);

  /// No description provided for @allForums.
  ///
  /// In zh, this message translates to:
  /// **'全部 {v1}'**
  String allForums(String v1);

  /// No description provided for @noForums.
  ///
  /// In zh, this message translates to:
  /// **'还没建板块'**
  String get noForums;

  /// No description provided for @loginToSeeFollowed.
  ///
  /// In zh, this message translates to:
  /// **'登录后能看到关注过的吧'**
  String get loginToSeeFollowed;

  /// No description provided for @goLogin.
  ///
  /// In zh, this message translates to:
  /// **'去登录'**
  String get goLogin;

  /// No description provided for @noFollowedForums.
  ///
  /// In zh, this message translates to:
  /// **'还没关注吧，进一个点关注'**
  String get noFollowedForums;

  /// No description provided for @noIntro.
  ///
  /// In zh, this message translates to:
  /// **'还没有简介'**
  String get noIntro;

  /// No description provided for @forumStats.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 帖 · {v2} 关注'**
  String forumStats(String v1, String v2);

  /// No description provided for @nRepliedPost.
  ///
  /// In zh, this message translates to:
  /// **'回复了你的帖'**
  String get nRepliedPost;

  /// No description provided for @nRepliedYou.
  ///
  /// In zh, this message translates to:
  /// **'回复了你'**
  String get nRepliedYou;

  /// No description provided for @nLiked.
  ///
  /// In zh, this message translates to:
  /// **'赞了你'**
  String get nLiked;

  /// No description provided for @nMentioned.
  ///
  /// In zh, this message translates to:
  /// **'在帖子里 @ 了你'**
  String get nMentioned;

  /// No description provided for @nFeatured.
  ///
  /// In zh, this message translates to:
  /// **'把你的帖加精了'**
  String get nFeatured;

  /// No description provided for @nDeleted.
  ///
  /// In zh, this message translates to:
  /// **'删了你的内容'**
  String get nDeleted;

  /// No description provided for @nNew.
  ///
  /// In zh, this message translates to:
  /// **'有新消息'**
  String get nNew;

  /// No description provided for @noticeLoginNeeded.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能收到通知'**
  String get noticeLoginNeeded;

  /// No description provided for @noticeLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'去「我的」登录'**
  String get noticeLoginHint;

  /// No description provided for @noNotifications.
  ///
  /// In zh, this message translates to:
  /// **'还没有通知'**
  String get noNotifications;

  /// No description provided for @noNotificationsHint.
  ///
  /// In zh, this message translates to:
  /// **'别人回复你、赞你，会出现在这里'**
  String get noNotificationsHint;

  /// No description provided for @reset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get reset;

  /// No description provided for @newPasswordFor.
  ///
  /// In zh, this message translates to:
  /// **'给「{v1}」的新密码：'**
  String newPasswordFor(String v1);

  /// No description provided for @newPasswordOnce.
  ///
  /// In zh, this message translates to:
  /// **'关掉就看不到了。让本人登录后马上改成自己记得的。'**
  String get newPasswordOnce;

  /// No description provided for @copyAndClose.
  ///
  /// In zh, this message translates to:
  /// **'复制并关闭'**
  String get copyAndClose;

  /// No description provided for @searchUsername.
  ///
  /// In zh, this message translates to:
  /// **'搜用户名'**
  String get searchUsername;

  /// No description provided for @noEmail.
  ///
  /// In zh, this message translates to:
  /// **'没绑邮箱'**
  String get noEmail;

  /// No description provided for @manualNeedsAddress.
  ///
  /// In zh, this message translates to:
  /// **'手动要填地址'**
  String get manualNeedsAddress;

  /// No description provided for @serverOkUsing.
  ///
  /// In zh, this message translates to:
  /// **'通了，当前用 {v1}'**
  String serverOkUsing(String v1);

  /// No description provided for @connectFailedBody.
  ///
  /// In zh, this message translates to:
  /// **'连不上：{v1}'**
  String connectFailedBody(String v1);

  /// No description provided for @ipv6FirstHint.
  ///
  /// In zh, this message translates to:
  /// **'先试 IPv6，连不上再用 IPv4'**
  String get ipv6FirstHint;

  /// No description provided for @channelIpv6.
  ///
  /// In zh, this message translates to:
  /// **'IPv6 通道'**
  String get channelIpv6;

  /// No description provided for @channelIpv4.
  ///
  /// In zh, this message translates to:
  /// **'IPv4 通道'**
  String get channelIpv4;

  /// No description provided for @enterManually.
  ///
  /// In zh, this message translates to:
  /// **'自己填地址'**
  String get enterManually;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @saveAndTest.
  ///
  /// In zh, this message translates to:
  /// **'保存并测试'**
  String get saveAndTest;

  /// No description provided for @currentExit.
  ///
  /// In zh, this message translates to:
  /// **'当前出口：{v1}'**
  String currentExit(String v1);

  /// No description provided for @switchedTo.
  ///
  /// In zh, this message translates to:
  /// **'已切换到 {v1}'**
  String switchedTo(String v1);

  /// No description provided for @accountExpiredRemoved.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 的登录已失效，已移除'**
  String accountExpiredRemoved(String v1);

  /// No description provided for @removeAccount.
  ///
  /// In zh, this message translates to:
  /// **'移除账号'**
  String get removeAccount;

  /// No description provided for @removeAccountConfirm.
  ///
  /// In zh, this message translates to:
  /// **'从本机移除 {v1}？只是退出这台设备，账号和帖子都还在服务器上。'**
  String removeAccountConfirm(String v1);

  /// No description provided for @accountAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {v1}'**
  String accountAdded(String v1);

  /// No description provided for @noAccounts.
  ///
  /// In zh, this message translates to:
  /// **'还没有账号'**
  String get noAccounts;

  /// No description provided for @addAccount.
  ///
  /// In zh, this message translates to:
  /// **'添加账号'**
  String get addAccount;

  /// No description provided for @addAccountHint.
  ///
  /// In zh, this message translates to:
  /// **'登录另一个账号，之后可以随时切回来'**
  String get addAccountHint;

  /// No description provided for @addFromDevice.
  ///
  /// In zh, this message translates to:
  /// **'把别的设备上的账号加进这台机器'**
  String get addFromDevice;

  /// No description provided for @friendSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'用户名 / @标识 / 昵称'**
  String get friendSearchHint;

  /// No description provided for @enterName.
  ///
  /// In zh, this message translates to:
  /// **'写个名字'**
  String get enterName;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get add;

  /// No description provided for @removeFriendConfirm.
  ///
  /// In zh, this message translates to:
  /// **'把 {v1} 拿下来？'**
  String removeFriendConfirm(String v1);

  /// No description provided for @removeFriendBody.
  ///
  /// In zh, this message translates to:
  /// **'只是从这页去掉，账号还在。'**
  String get removeFriendBody;

  /// No description provided for @credits.
  ///
  /// In zh, this message translates to:
  /// **'致谢'**
  String get credits;

  /// No description provided for @nobodyYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有人'**
  String get nobodyYet;

  /// No description provided for @creditsAdminOnly.
  ///
  /// In zh, this message translates to:
  /// **'这份名单只有管理员能改（当前登录：{v1}）。'**
  String creditsAdminOnly(String v1);

  /// No description provided for @unfollowed.
  ///
  /// In zh, this message translates to:
  /// **'已取消关注 {v1}'**
  String unfollowed(String v1);

  /// No description provided for @followedBack.
  ///
  /// In zh, this message translates to:
  /// **'已回关 {v1}'**
  String followedBack(String v1);

  /// No description provided for @fans.
  ///
  /// In zh, this message translates to:
  /// **'粉丝'**
  String get fans;

  /// No description provided for @notFollowingAnyone.
  ///
  /// In zh, this message translates to:
  /// **'还没关注谁'**
  String get notFollowingAnyone;

  /// No description provided for @noFans.
  ///
  /// In zh, this message translates to:
  /// **'还没有粉丝'**
  String get noFans;

  /// No description provided for @mutual.
  ///
  /// In zh, this message translates to:
  /// **'互相关注'**
  String get mutual;

  /// No description provided for @followBack.
  ///
  /// In zh, this message translates to:
  /// **'回关'**
  String get followBack;

  /// No description provided for @searchTitleOrBody.
  ///
  /// In zh, this message translates to:
  /// **'搜标题或内容'**
  String get searchTitleOrBody;

  /// No description provided for @searchPrompt.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词，按回车'**
  String get searchPrompt;

  /// No description provided for @recentSearches.
  ///
  /// In zh, this message translates to:
  /// **'最近搜索'**
  String get recentSearches;

  /// No description provided for @totalCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {v1} 条'**
  String totalCount(String v1);

  /// No description provided for @endTotalCount.
  ///
  /// In zh, this message translates to:
  /// **'到底了，共 {v1} 条'**
  String endTotalCount(String v1);

  /// No description provided for @noFavoritesYet.
  ///
  /// In zh, this message translates to:
  /// **'还没收藏过帖'**
  String get noFavoritesYet;

  /// No description provided for @reportHandling.
  ///
  /// In zh, this message translates to:
  /// **'举报处理'**
  String get reportHandling;

  /// No description provided for @requestHandling.
  ///
  /// In zh, this message translates to:
  /// **'需求处理'**
  String get requestHandling;

  /// No description provided for @noHistoryYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有浏览记录'**
  String get noHistoryYet;

  /// No description provided for @enterBio.
  ///
  /// In zh, this message translates to:
  /// **'请输入你的个人签名'**
  String get enterBio;

  /// No description provided for @tapToLogin.
  ///
  /// In zh, this message translates to:
  /// **'点这里登录'**
  String get tapToLogin;

  /// No description provided for @general.
  ///
  /// In zh, this message translates to:
  /// **'综合'**
  String get general;

  /// No description provided for @featured.
  ///
  /// In zh, this message translates to:
  /// **'精华'**
  String get featured;

  /// No description provided for @multiImage.
  ///
  /// In zh, this message translates to:
  /// **'多图片'**
  String get multiImage;

  /// No description provided for @comments.
  ///
  /// In zh, this message translates to:
  /// **'评论'**
  String get comments;

  /// No description provided for @loginBenefits.
  ///
  /// In zh, this message translates to:
  /// **'登录后可以发帖、回复、关注吧'**
  String get loginBenefits;

  /// No description provided for @hot.
  ///
  /// In zh, this message translates to:
  /// **'热门'**
  String get hot;

  /// No description provided for @forumEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个吧还没有帖'**
  String get forumEmpty;

  /// No description provided for @permIntro.
  ///
  /// In zh, this message translates to:
  /// **'联网权限安装时已经给了，这里只剩通知和相册需要你点头。'**
  String get permIntro;

  /// No description provided for @network.
  ///
  /// In zh, this message translates to:
  /// **'联网'**
  String get network;

  /// No description provided for @networkGranted.
  ///
  /// In zh, this message translates to:
  /// **'安装时自动授予，不用管'**
  String get networkGranted;

  /// No description provided for @permOptionalNote.
  ///
  /// In zh, this message translates to:
  /// **'不想开的可以一直关着，只是发图时得手动去系统里选。'**
  String get permOptionalNote;

  /// No description provided for @downloadImage.
  ///
  /// In zh, this message translates to:
  /// **'下载这张图'**
  String get downloadImage;

  /// No description provided for @backToTop.
  ///
  /// In zh, this message translates to:
  /// **'回到顶部'**
  String get backToTop;

  /// No description provided for @offlineCacheFeed.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器，这是上次的缓存'**
  String get offlineCacheFeed;

  /// No description provided for @chooseForum.
  ///
  /// In zh, this message translates to:
  /// **'发到哪个板块'**
  String get chooseForum;

  /// No description provided for @fillAddress.
  ///
  /// In zh, this message translates to:
  /// **'填一下地址'**
  String get fillAddress;

  /// No description provided for @fillServerAddress.
  ///
  /// In zh, this message translates to:
  /// **'填一下服务器地址'**
  String get fillServerAddress;

  /// No description provided for @connect.
  ///
  /// In zh, this message translates to:
  /// **'连上去'**
  String get connect;

  /// No description provided for @themeColorTitle.
  ///
  /// In zh, this message translates to:
  /// **'主题颜色'**
  String get themeColorTitle;

  /// No description provided for @accentColorHint.
  ///
  /// In zh, this message translates to:
  /// **'上面的按钮、选中状态、输入框焦点圈都会跟着这条色带走。'**
  String get accentColorHint;

  /// No description provided for @moreToLoad.
  ///
  /// In zh, this message translates to:
  /// **'还有更多'**
  String get moreToLoad;

  /// No description provided for @resetPasswordConfirm.
  ///
  /// In zh, this message translates to:
  /// **'把「{v1}」的密码换成随机的一串？\n\n原密码会立刻失效。新密码只显示一次，记得发给本人。'**
  String resetPasswordConfirm(String v1);
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'zh':
      return LZh();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
