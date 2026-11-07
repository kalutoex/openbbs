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

  /// No description provided for @netDownBanner.
  ///
  /// In zh, this message translates to:
  /// **'连不上服务器，网络一通就自己收起来'**
  String get netDownBanner;

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

  /// No description provided for @easterEggButton.
  ///
  /// In zh, this message translates to:
  /// **'没啥用的小按钮'**
  String get easterEggButton;

  /// No description provided for @easterEggTitle.
  ///
  /// In zh, this message translates to:
  /// **'小玩意'**
  String get easterEggTitle;

  /// No description provided for @hueCards.
  ///
  /// In zh, this message translates to:
  /// **'卡片跟着人染色'**
  String get hueCards;

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

  /// No description provided for @mustUpdate.
  ///
  /// In zh, this message translates to:
  /// **'这一版太旧了，先更新才能继续用。'**
  String get mustUpdate;

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

  /// No description provided for @noPostsHint.
  ///
  /// In zh, this message translates to:
  /// **'发第一条，把这里开个头'**
  String get noPostsHint;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'没能拉到内容'**
  String get loadFailed;

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

  /// No description provided for @goLogin.
  ///
  /// In zh, this message translates to:
  /// **'去登录'**
  String get goLogin;

  /// No description provided for @noIntro.
  ///
  /// In zh, this message translates to:
  /// **'还没有简介'**
  String get noIntro;

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

  /// No description provided for @followWallpaper.
  ///
  /// In zh, this message translates to:
  /// **'跟随壁纸取色'**
  String get followWallpaper;

  /// No description provided for @followWallpaperHint.
  ///
  /// In zh, this message translates to:
  /// **'Android 12 及以上可用。开启后主题色由系统壁纸决定，下面的色带不起作用。'**
  String get followWallpaperHint;

  /// No description provided for @appIconTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用图标'**
  String get appIconTitle;

  /// No description provided for @appIconHint.
  ///
  /// In zh, this message translates to:
  /// **'桌面图标和名字是打包时定死的，这里换的是预先做好的几套。选完桌面要等几秒才变，个别启动器还得重启一下。'**
  String get appIconHint;

  /// No description provided for @appIconChanged.
  ///
  /// In zh, this message translates to:
  /// **'换好了，看桌面'**
  String get appIconChanged;

  /// No description provided for @appIconUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这个平台上换不了图标'**
  String get appIconUnavailable;

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

  /// No description provided for @siteNeedsUpdate.
  ///
  /// In zh, this message translates to:
  /// **'这个站点的接口版本是 {v1}，当前客户端只认到 {v2}。请更新客户端后再用。'**
  String siteNeedsUpdate(Object v1, Object v2);

  /// No description provided for @sitesManage.
  ///
  /// In zh, this message translates to:
  /// **'站点管理'**
  String get sitesManage;

  /// No description provided for @sitesManageHint.
  ///
  /// In zh, this message translates to:
  /// **'一个入口管多个站，连不上的自动跳过'**
  String get sitesManageHint;

  /// No description provided for @siteAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加站点'**
  String get siteAdd;

  /// No description provided for @siteImportPaste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴清单'**
  String get siteImportPaste;

  /// No description provided for @siteImportMaster.
  ///
  /// In zh, this message translates to:
  /// **'从主站拉目录'**
  String get siteImportMaster;

  /// No description provided for @importIt.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get importIt;

  /// No description provided for @siteImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'读不出清单：{v1}'**
  String siteImportFailed(String v1);

  /// No description provided for @siteImportEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这份清单里没有站点'**
  String get siteImportEmpty;

  /// No description provided for @siteImportNone.
  ///
  /// In zh, this message translates to:
  /// **'没有可导入的站：{v1}'**
  String siteImportNone(String v1);

  /// No description provided for @siteImported.
  ///
  /// In zh, this message translates to:
  /// **'导入 {v1} 座站'**
  String siteImported(String v1);

  /// No description provided for @siteImportedSkipped.
  ///
  /// In zh, this message translates to:
  /// **'导入 {v1} 座站，跳过 {v2} 条：{v3}'**
  String siteImportedSkipped(String v1, String v2, String v3);

  /// No description provided for @skipNoUrl.
  ///
  /// In zh, this message translates to:
  /// **'没有地址'**
  String get skipNoUrl;

  /// No description provided for @skipDuplicateId.
  ///
  /// In zh, this message translates to:
  /// **'id 重复'**
  String get skipDuplicateId;

  /// No description provided for @skipApiTooNew.
  ///
  /// In zh, this message translates to:
  /// **'接口版本太新'**
  String get skipApiTooNew;

  /// No description provided for @skipBadFormat.
  ///
  /// In zh, this message translates to:
  /// **'不是清单格式'**
  String get skipBadFormat;

  /// No description provided for @siteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有站点'**
  String get siteEmpty;

  /// No description provided for @siteEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'填一个地址就能开始，账号和帖子都在对方服务器上。'**
  String get siteEmptyHint;

  /// No description provided for @siteLoginSite.
  ///
  /// In zh, this message translates to:
  /// **'登录站'**
  String get siteLoginSite;

  /// No description provided for @siteCurrentNow.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get siteCurrentNow;

  /// No description provided for @siteUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'连不上'**
  String get siteUnreachable;

  /// No description provided for @siteSetLogin.
  ///
  /// In zh, this message translates to:
  /// **'设为登录站'**
  String get siteSetLogin;

  /// No description provided for @siteSwitch.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get siteSwitch;

  /// No description provided for @siteProbe.
  ///
  /// In zh, this message translates to:
  /// **'重新探测'**
  String get siteProbe;

  /// No description provided for @siteRemoveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'从这台设备移除 {v1}？账号和帖子都还在服务器上。'**
  String siteRemoveConfirm(String v1);

  /// No description provided for @siteLoginSet.
  ///
  /// In zh, this message translates to:
  /// **'登录站改成 {v1}'**
  String siteLoginSet(String v1);

  /// No description provided for @sites.
  ///
  /// In zh, this message translates to:
  /// **'站点'**
  String get sites;

  /// No description provided for @siteMaster.
  ///
  /// In zh, this message translates to:
  /// **'主站'**
  String get siteMaster;

  /// No description provided for @siteSmall.
  ///
  /// In zh, this message translates to:
  /// **'小站'**
  String get siteSmall;

  /// No description provided for @sitePostTo.
  ///
  /// In zh, this message translates to:
  /// **'发到'**
  String get sitePostTo;

  /// No description provided for @siteMasterFixed.
  ///
  /// In zh, this message translates to:
  /// **'主站不能移除'**
  String get siteMasterFixed;

  /// No description provided for @siteSpeedTest.
  ///
  /// In zh, this message translates to:
  /// **'测速'**
  String get siteSpeedTest;

  /// No description provided for @siteSpeedRunning.
  ///
  /// In zh, this message translates to:
  /// **'测速中…'**
  String get siteSpeedRunning;

  /// No description provided for @siteSpeedResult.
  ///
  /// In zh, this message translates to:
  /// **'测速：{v1}'**
  String siteSpeedResult(String v1);

  /// No description provided for @siteSpeedNone.
  ///
  /// In zh, this message translates to:
  /// **'都不通'**
  String get siteSpeedNone;

  /// No description provided for @siteSwitching.
  ///
  /// In zh, this message translates to:
  /// **'正在切到 {v1}'**
  String siteSwitching(String v1);

  /// No description provided for @listSep.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get listSep;

  /// No description provided for @bannedTitle.
  ///
  /// In zh, this message translates to:
  /// **'账号已被封禁'**
  String get bannedTitle;

  /// No description provided for @bannedBody.
  ///
  /// In zh, this message translates to:
  /// **'这个账号被管理员封了，帖子也发不出去。换个号，或者找站长问原因。'**
  String get bannedBody;

  /// No description provided for @posts.
  ///
  /// In zh, this message translates to:
  /// **'帖子'**
  String get posts;

  /// No description provided for @siteBlock.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽'**
  String get siteBlock;

  /// No description provided for @siteUnblock.
  ///
  /// In zh, this message translates to:
  /// **'取消屏蔽'**
  String get siteUnblock;

  /// No description provided for @siteBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已屏蔽'**
  String get siteBlocked;

  /// No description provided for @siteBlockedDone.
  ///
  /// In zh, this message translates to:
  /// **'已屏蔽，目录里不再显示这座站'**
  String get siteBlockedDone;

  /// No description provided for @siteUnblockedDone.
  ///
  /// In zh, this message translates to:
  /// **'已取消屏蔽'**
  String get siteUnblockedDone;

  /// No description provided for @siteCatalogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有别的站'**
  String get siteCatalogEmpty;

  /// No description provided for @siteCatalogEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'在设置里的「站点管理」加一座，或者等主站收录。'**
  String get siteCatalogEmptyHint;

  /// No description provided for @siteNoPosts.
  ///
  /// In zh, this message translates to:
  /// **'这座站还没有帖子'**
  String get siteNoPosts;

  /// No description provided for @searchThreads.
  ///
  /// In zh, this message translates to:
  /// **'帖子'**
  String get searchThreads;

  /// No description provided for @searchReplies.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get searchReplies;

  /// No description provided for @searchUsers.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get searchUsers;

  /// No description provided for @dmTitle.
  ///
  /// In zh, this message translates to:
  /// **'私信'**
  String get dmTitle;

  /// No description provided for @dmEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有私信'**
  String get dmEmpty;

  /// No description provided for @messagesTab.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get messagesTab;

  /// No description provided for @siteMessages.
  ///
  /// In zh, this message translates to:
  /// **'站内消息'**
  String get siteMessages;

  /// No description provided for @pinChat.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get pinChat;

  /// No description provided for @unpinChat.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get unpinChat;

  /// No description provided for @muteChat.
  ///
  /// In zh, this message translates to:
  /// **'免打扰'**
  String get muteChat;

  /// No description provided for @unmuteChat.
  ///
  /// In zh, this message translates to:
  /// **'取消免打扰'**
  String get unmuteChat;

  /// No description provided for @markRead.
  ///
  /// In zh, this message translates to:
  /// **'标为已读'**
  String get markRead;

  /// No description provided for @deleteChat.
  ///
  /// In zh, this message translates to:
  /// **'删除该聊天'**
  String get deleteChat;

  /// No description provided for @dmEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'在别人主页点「发私信」'**
  String get dmEmptyHint;

  /// No description provided for @dmEarlier.
  ///
  /// In zh, this message translates to:
  /// **'加载更早'**
  String get dmEarlier;

  /// No description provided for @dmSend.
  ///
  /// In zh, this message translates to:
  /// **'发私信'**
  String get dmSend;

  /// No description provided for @pickFromDevice.
  ///
  /// In zh, this message translates to:
  /// **'从设备选'**
  String get pickFromDevice;

  /// No description provided for @pickFromCloud.
  ///
  /// In zh, this message translates to:
  /// **'从云盘选'**
  String get pickFromCloud;

  /// No description provided for @cloudPickEmpty.
  ///
  /// In zh, this message translates to:
  /// **'云盘里还没有文件'**
  String get cloudPickEmpty;

  /// No description provided for @cloudPickDone.
  ///
  /// In zh, this message translates to:
  /// **'完成（{v1}）'**
  String cloudPickDone(String v1);

  /// No description provided for @attachFile.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get attachFile;

  /// No description provided for @attachMax.
  ///
  /// In zh, this message translates to:
  /// **'最多 {v1} 个附件'**
  String attachMax(String v1);

  /// No description provided for @attachTooBig.
  ///
  /// In zh, this message translates to:
  /// **'文件不能超过 {v1}'**
  String attachTooBig(String v1);

  /// No description provided for @attachUploading.
  ///
  /// In zh, this message translates to:
  /// **'正在上传 {v1}'**
  String attachUploading(String v1);

  /// No description provided for @pasteCredential.
  ///
  /// In zh, this message translates to:
  /// **'粘贴登录凭证'**
  String get pasteCredential;

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

  /// No description provided for @restoreWithCredential.
  ///
  /// In zh, this message translates to:
  /// **'用登录凭证恢复'**
  String get restoreWithCredential;

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

  /// No description provided for @forumStats.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 帖 · {v2} 关注'**
  String forumStats(String v1, String v2);

  /// No description provided for @addFromDevice.
  ///
  /// In zh, this message translates to:
  /// **'把别的设备上的账号加进这台机器'**
  String get addFromDevice;

  /// No description provided for @cloudDisk.
  ///
  /// In zh, this message translates to:
  /// **'云盘'**
  String get cloudDisk;

  /// No description provided for @recycleBin.
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get recycleBin;

  /// No description provided for @deleteThisFile.
  ///
  /// In zh, this message translates to:
  /// **'删除这个文件？'**
  String get deleteThisFile;

  /// No description provided for @fileUsedByPosts.
  ///
  /// In zh, this message translates to:
  /// **'有 {v1} 个帖子正在用它。删掉之后，那些地方会显示「文件已失效」。'**
  String fileUsedByPosts(String v1);

  /// No description provided for @goesToTrashHint.
  ///
  /// In zh, this message translates to:
  /// **'文件先进回收站，7 天内还能恢复。空间会立刻还回来。'**
  String get goesToTrashHint;

  /// No description provided for @movedToTrash.
  ///
  /// In zh, this message translates to:
  /// **'已移入回收站'**
  String get movedToTrash;

  /// No description provided for @notConnectedTapRetry.
  ///
  /// In zh, this message translates to:
  /// **'没连上，点这里重试'**
  String get notConnectedTapRetry;

  /// No description provided for @nothingUploadedYet.
  ///
  /// In zh, this message translates to:
  /// **'还没传过东西'**
  String get nothingUploadedYet;

  /// No description provided for @notFound.
  ///
  /// In zh, this message translates to:
  /// **'没找到'**
  String get notFound;

  /// No description provided for @findFile.
  ///
  /// In zh, this message translates to:
  /// **'找文件'**
  String get findFile;

  /// No description provided for @bySize.
  ///
  /// In zh, this message translates to:
  /// **'按大小'**
  String get bySize;

  /// No description provided for @byTime.
  ///
  /// In zh, this message translates to:
  /// **'按时间'**
  String get byTime;

  /// No description provided for @usedByPosts.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个帖子在用'**
  String usedByPosts(String v1);

  /// No description provided for @fileCount2.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个文件'**
  String fileCount2(String v1);

  /// No description provided for @usedSpace.
  ///
  /// In zh, this message translates to:
  /// **'已用 {v1}'**
  String usedSpace(String v1);

  /// No description provided for @usedOfTotal.
  ///
  /// In zh, this message translates to:
  /// **'{v1} / {v2}'**
  String usedOfTotal(String v1, String v2);

  /// No description provided for @daysLeft.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {v1} 天'**
  String daysLeft(String v1);

  /// No description provided for @hoursLeft.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {v1} 小时'**
  String hoursLeft(String v1);

  /// No description provided for @expiringSoon.
  ///
  /// In zh, this message translates to:
  /// **'就要清了'**
  String get expiringSoon;

  /// No description provided for @emptyHere.
  ///
  /// In zh, this message translates to:
  /// **'空的'**
  String get emptyHere;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @upload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get upload;

  /// No description provided for @uploadingFile2.
  ///
  /// In zh, this message translates to:
  /// **'正在上传 {v1}'**
  String uploadingFile2(String v1);

  /// No description provided for @uploadedDone.
  ///
  /// In zh, this message translates to:
  /// **'传好了'**
  String get uploadedDone;

  /// No description provided for @uploadCancelled.
  ///
  /// In zh, this message translates to:
  /// **'上传已取消'**
  String get uploadCancelled;

  /// No description provided for @uploadedDoneAll.
  ///
  /// In zh, this message translates to:
  /// **'都传好了，{v1} 个'**
  String uploadedDoneAll(String v1);

  /// No description provided for @uploadedFailedAll.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个都没传上去'**
  String uploadedFailedAll(String v1);

  /// No description provided for @uploadedPartly.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个传好了，{v2} 个没成'**
  String uploadedPartly(String v1, String v2);

  /// No description provided for @uploadFailedTapRetry.
  ///
  /// In zh, this message translates to:
  /// **'没传上去，点那一行可以重试'**
  String get uploadFailedTapRetry;

  /// No description provided for @uploadWrongAccount.
  ///
  /// In zh, this message translates to:
  /// **'换过账号了，这条停在这儿。要传到当前账号，点那一行重试。'**
  String get uploadWrongAccount;

  /// No description provided for @fileTooBigHint.
  ///
  /// In zh, this message translates to:
  /// **'单个文件别超过 500MB'**
  String get fileTooBigHint;

  /// No description provided for @cloudRefsWarn.
  ///
  /// In zh, this message translates to:
  /// **'有 {v1} 个帖子正在用它。删掉之后，那些地方会显示「文件已失效」。'**
  String cloudRefsWarn(String v1);

  /// No description provided for @restoredDone.
  ///
  /// In zh, this message translates to:
  /// **'恢复了'**
  String get restoredDone;

  /// No description provided for @cloudUsage.
  ///
  /// In zh, this message translates to:
  /// **'云盘用量'**
  String get cloudUsage;

  /// No description provided for @changeQuota.
  ///
  /// In zh, this message translates to:
  /// **'调整额度'**
  String get changeQuota;

  /// No description provided for @quotaMbHint.
  ///
  /// In zh, this message translates to:
  /// **'额度（MB，留空 = 跟全站默认）'**
  String get quotaMbHint;

  /// No description provided for @quotaSaved.
  ///
  /// In zh, this message translates to:
  /// **'额度已更新'**
  String get quotaSaved;

  /// No description provided for @cloudQuotaDefault.
  ///
  /// In zh, this message translates to:
  /// **'全站默认'**
  String get cloudQuotaDefault;

  /// No description provided for @cloudSection.
  ///
  /// In zh, this message translates to:
  /// **'云服务'**
  String get cloudSection;

  /// No description provided for @cloudSettings.
  ///
  /// In zh, this message translates to:
  /// **'云服务设置'**
  String get cloudSettings;

  /// No description provided for @cloudSettingsHint.
  ///
  /// In zh, this message translates to:
  /// **'下载存哪、下完做什么'**
  String get cloudSettingsHint;

  /// No description provided for @cloudSettingsIntro.
  ///
  /// In zh, this message translates to:
  /// **'云盘和帖子里的文件，下载后会存到下面这个位置。要换个地方就在这里改。'**
  String get cloudSettingsIntro;

  /// No description provided for @downloadLocation.
  ///
  /// In zh, this message translates to:
  /// **'下载位置'**
  String get downloadLocation;

  /// No description provided for @downloadLocationDefault.
  ///
  /// In zh, this message translates to:
  /// **'还没改过，用默认的「下载/OpenBBS」'**
  String get downloadLocationDefault;

  /// No description provided for @downloadLocationReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认位置'**
  String get downloadLocationReset;

  /// No description provided for @downloadLocationDefaultHint.
  ///
  /// In zh, this message translates to:
  /// **'回到「下载/OpenBBS」'**
  String get downloadLocationDefaultHint;

  /// No description provided for @downloadDirReset.
  ///
  /// In zh, this message translates to:
  /// **'已恢复默认位置'**
  String get downloadDirReset;

  /// No description provided for @downloadAutoOpen.
  ///
  /// In zh, this message translates to:
  /// **'下完自动打开'**
  String get downloadAutoOpen;

  /// No description provided for @downloadAutoOpenHint.
  ///
  /// In zh, this message translates to:
  /// **'关掉就只存下来，自己去文件夹里找'**
  String get downloadAutoOpenHint;

  /// No description provided for @downloadCache.
  ///
  /// In zh, this message translates to:
  /// **'下载缓存'**
  String get downloadCache;

  /// No description provided for @downloadCacheUsed.
  ///
  /// In zh, this message translates to:
  /// **'断掉的下载残留 {v1}'**
  String downloadCacheUsed(String v1);

  /// No description provided for @downloadCacheEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有残留'**
  String get downloadCacheEmpty;

  /// No description provided for @cacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'清掉了'**
  String get cacheCleared;

  /// No description provided for @downloadByBrowser.
  ///
  /// In zh, this message translates to:
  /// **'网页版的下载位置由浏览器决定，在浏览器自己的设置里改。'**
  String get downloadByBrowser;

  /// No description provided for @deleteForever.
  ///
  /// In zh, this message translates to:
  /// **'彻底删除'**
  String get deleteForever;

  /// No description provided for @deleteForeverHint.
  ///
  /// In zh, this message translates to:
  /// **'删了就找不回来。'**
  String get deleteForeverHint;

  /// No description provided for @deletedForever.
  ///
  /// In zh, this message translates to:
  /// **'已彻底删除'**
  String get deletedForever;

  /// No description provided for @downloadedBadge.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloadedBadge;

  /// No description provided for @downloadingShort.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get downloadingShort;

  /// No description provided for @browseFiles.
  ///
  /// In zh, this message translates to:
  /// **'手机文件'**
  String get browseFiles;

  /// No description provided for @browseFilesHint.
  ///
  /// In zh, this message translates to:
  /// **'翻手机里的文件，选中直接传'**
  String get browseFilesHint;

  /// No description provided for @pickFromSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统选择器'**
  String get pickFromSystem;

  /// No description provided for @allFilesAccess.
  ///
  /// In zh, this message translates to:
  /// **'访问所有文件'**
  String get allFilesAccess;

  /// No description provided for @allFilesWhy.
  ///
  /// In zh, this message translates to:
  /// **'要翻整个手机的存储，得在系统设置里给这个权限。只用来读你选中的文件，别的不动。'**
  String get allFilesWhy;

  /// No description provided for @allFilesOpen.
  ///
  /// In zh, this message translates to:
  /// **'去设置里开'**
  String get allFilesOpen;

  /// No description provided for @allFilesDenied.
  ///
  /// In zh, this message translates to:
  /// **'没拿到访问权限，翻不了手机存储'**
  String get allFilesDenied;

  /// No description provided for @allFilesRetry.
  ///
  /// In zh, this message translates to:
  /// **'我开好了，再试一次'**
  String get allFilesRetry;

  /// No description provided for @searchThisFolder.
  ///
  /// In zh, this message translates to:
  /// **'在这个文件夹里找'**
  String get searchThisFolder;

  /// No description provided for @folderEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个文件夹是空的'**
  String get folderEmpty;

  /// No description provided for @noAccessFolder.
  ///
  /// In zh, this message translates to:
  /// **'进不去，系统限制了'**
  String get noAccessFolder;

  /// No description provided for @pickedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {v1}'**
  String pickedCount(String v1);

  /// No description provided for @uploadPicked.
  ///
  /// In zh, this message translates to:
  /// **'上传 {v1} 个'**
  String uploadPicked(String v1);

  /// No description provided for @uploadingIndexOf.
  ///
  /// In zh, this message translates to:
  /// **'正在传 {v1}/{v2}：{v3}'**
  String uploadingIndexOf(String v1, String v2, String v3);

  /// No description provided for @uploadSomeFailed.
  ///
  /// In zh, this message translates to:
  /// **'传完 {v1} 个，{v2} 个没传上去'**
  String uploadSomeFailed(String v1, String v2);

  /// No description provided for @storageRoot.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get storageRoot;

  /// No description provided for @systemFolderHidden.
  ///
  /// In zh, this message translates to:
  /// **'系统目录（看不到内容）'**
  String get systemFolderHidden;

  /// No description provided for @dmWaitReply.
  ///
  /// In zh, this message translates to:
  /// **'对方还没回关，等他回一句你就能接着发'**
  String get dmWaitReply;

  /// No description provided for @dmNewMessages.
  ///
  /// In zh, this message translates to:
  /// **'有新消息'**
  String get dmNewMessages;

  /// No description provided for @dmTapToProfile.
  ///
  /// In zh, this message translates to:
  /// **'点开看资料'**
  String get dmTapToProfile;

  /// No description provided for @dmNoChat.
  ///
  /// In zh, this message translates to:
  /// **'还没聊过，说点什么吧'**
  String get dmNoChat;

  /// No description provided for @quote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quote;

  /// No description provided for @replyRecalled.
  ///
  /// In zh, this message translates to:
  /// **'该回复已撤回'**
  String get replyRecalled;

  /// No description provided for @replyRemembered.
  ///
  /// In zh, this message translates to:
  /// **'两分钟内可以撤回，过了就撤不回了'**
  String get replyRemembered;

  /// No description provided for @replyImage.
  ///
  /// In zh, this message translates to:
  /// **'[图片]'**
  String get replyImage;

  /// No description provided for @dmPickImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get dmPickImage;

  /// No description provided for @dmPickFile.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get dmPickFile;

  /// No description provided for @dmAttach.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get dmAttach;

  /// No description provided for @notifyNewDm.
  ///
  /// In zh, this message translates to:
  /// **'新私信'**
  String get notifyNewDm;

  /// No description provided for @notifyNewCount.
  ///
  /// In zh, this message translates to:
  /// **'{n} 条新消息'**
  String notifyNewCount(int n);

  /// No description provided for @sysNotify.
  ///
  /// In zh, this message translates to:
  /// **'消息通知'**
  String get sysNotify;

  /// No description provided for @sysNotifyHint.
  ///
  /// In zh, this message translates to:
  /// **'有新消息时弹一条系统通知'**
  String get sysNotifyHint;

  /// No description provided for @sysNotifyOff.
  ///
  /// In zh, this message translates to:
  /// **'系统通知权限没开，去手机设置里打开'**
  String get sysNotifyOff;

  /// No description provided for @bgKeepAlive.
  ///
  /// In zh, this message translates to:
  /// **'后台保活'**
  String get bgKeepAlive;

  /// No description provided for @bgKeepAliveHint.
  ///
  /// In zh, this message translates to:
  /// **'不豁免电池优化，系统会在后台冻住 App，锁屏后收不到提醒'**
  String get bgKeepAliveHint;

  /// No description provided for @bgKeepAliveOn.
  ///
  /// In zh, this message translates to:
  /// **'已豁免'**
  String get bgKeepAliveOn;

  /// No description provided for @bgKeepAliveOff.
  ///
  /// In zh, this message translates to:
  /// **'去设置'**
  String get bgKeepAliveOff;

  /// No description provided for @notifyPerm.
  ///
  /// In zh, this message translates to:
  /// **'通知权限'**
  String get notifyPerm;

  /// No description provided for @notifyPermHint.
  ///
  /// In zh, this message translates to:
  /// **'通知权限没开，系统一条提醒都不会显示'**
  String get notifyPermHint;

  /// No description provided for @notifyPermOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get notifyPermOn;

  /// No description provided for @notifyPermOff.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get notifyPermOff;

  /// No description provided for @notifyPermDenied.
  ///
  /// In zh, this message translates to:
  /// **'通知权限没开，先去系统里打开'**
  String get notifyPermDenied;

  /// No description provided for @notifyTest.
  ///
  /// In zh, this message translates to:
  /// **'发一条测试通知'**
  String get notifyTest;

  /// No description provided for @notifyTestTitle.
  ///
  /// In zh, this message translates to:
  /// **'测试通知'**
  String get notifyTestTitle;

  /// No description provided for @notifyTestBody.
  ///
  /// In zh, this message translates to:
  /// **'能看到这条，说明通知是通的'**
  String get notifyTestBody;

  /// No description provided for @noRepliesHint.
  ///
  /// In zh, this message translates to:
  /// **'说两句，让楼主知道有人看。'**
  String get noRepliesHint;

  /// No description provided for @usernameOrEmail.
  ///
  /// In zh, this message translates to:
  /// **'用户名或邮箱'**
  String get usernameOrEmail;

  /// No description provided for @changePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In zh, this message translates to:
  /// **'原密码'**
  String get currentPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'再输一次新密码'**
  String get confirmPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的新密码不一样'**
  String get passwordMismatch;

  /// No description provided for @passwordChanged.
  ///
  /// In zh, this message translates to:
  /// **'密码改好了，别的设备得重新登录'**
  String get passwordChanged;

  /// No description provided for @revokeOtherDevices.
  ///
  /// In zh, this message translates to:
  /// **'退出其他设备'**
  String get revokeOtherDevices;

  /// No description provided for @revokedOther.
  ///
  /// In zh, this message translates to:
  /// **'已退出其他设备'**
  String get revokedOther;

  /// No description provided for @revokeFailed.
  ///
  /// In zh, this message translates to:
  /// **'没退成：{v1}'**
  String revokeFailed(String v1);

  /// No description provided for @currentPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'先填原密码'**
  String get currentPasswordRequired;

  /// No description provided for @showPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get hidePassword;

  /// No description provided for @downloadsPage.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloadsPage;

  /// No description provided for @downloadsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没下载过文件'**
  String get downloadsEmpty;

  /// No description provided for @downloadsCount.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个 · {v2}'**
  String downloadsCount(Object v1, Object v2);

  /// No description provided for @showInFolder.
  ///
  /// In zh, this message translates to:
  /// **'在文件夹中显示'**
  String get showInFolder;

  /// No description provided for @deleteLocalFile.
  ///
  /// In zh, this message translates to:
  /// **'删除本地文件'**
  String get deleteLocalFile;

  /// No description provided for @deleteLocalAsk.
  ///
  /// In zh, this message translates to:
  /// **'删了手机上就没了，云盘里的还在。'**
  String get deleteLocalAsk;

  /// No description provided for @localFileGone.
  ///
  /// In zh, this message translates to:
  /// **'文件不在了'**
  String get localFileGone;

  /// No description provided for @removeFromList.
  ///
  /// In zh, this message translates to:
  /// **'从列表移除'**
  String get removeFromList;

  /// No description provided for @cantOpenThis.
  ///
  /// In zh, this message translates to:
  /// **'打不开这个文件：{v1}'**
  String cantOpenThis(Object v1);

  /// No description provided for @downloadsByBrowser.
  ///
  /// In zh, this message translates to:
  /// **'网页版的下载归浏览器管，这里列不出来。'**
  String get downloadsByBrowser;

  /// No description provided for @clearMissingRecords.
  ///
  /// In zh, this message translates to:
  /// **'清掉不在了的'**
  String get clearMissingRecords;

  /// No description provided for @followsHidden.
  ///
  /// In zh, this message translates to:
  /// **'对方没有公开'**
  String get followsHidden;

  /// No description provided for @showFollows.
  ///
  /// In zh, this message translates to:
  /// **'公开关注和粉丝'**
  String get showFollows;

  /// No description provided for @showFollowsHint.
  ///
  /// In zh, this message translates to:
  /// **'关掉后别人看不到你的关注和粉丝列表'**
  String get showFollowsHint;

  /// No description provided for @selectMode.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get selectMode;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @selectNone.
  ///
  /// In zh, this message translates to:
  /// **'全不选'**
  String get selectNone;

  /// No description provided for @deleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'删除所选'**
  String get deleteSelected;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 个'**
  String selectedCount(int n);

  /// No description provided for @deleteSelectedAsk.
  ///
  /// In zh, this message translates to:
  /// **'这 {n} 个文件会从手机里删掉，云盘里的还在。'**
  String deleteSelectedAsk(int n);

  /// No description provided for @deletedSelected.
  ///
  /// In zh, this message translates to:
  /// **'已删 {n} 个'**
  String deletedSelected(int n);

  /// No description provided for @deleteTaskAsk.
  ///
  /// In zh, this message translates to:
  /// **'删除这个下载任务吗？'**
  String get deleteTaskAsk;

  /// No description provided for @deleteTasksAskN.
  ///
  /// In zh, this message translates to:
  /// **'删除这 {n} 个下载任务吗？'**
  String deleteTasksAskN(int n);

  /// No description provided for @alsoDeleteFile.
  ///
  /// In zh, this message translates to:
  /// **'同时删除已下载的文件'**
  String get alsoDeleteFile;

  /// No description provided for @clearedFromList.
  ///
  /// In zh, this message translates to:
  /// **'已清 {n} 条'**
  String clearedFromList(int n);

  /// No description provided for @uiConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'界面参数'**
  String get uiConfigTitle;

  /// No description provided for @uiConfigHint.
  ///
  /// In zh, this message translates to:
  /// **'这里改的是卡片高度、边距、字号这类纯视觉的数字，保存后客户端下次拉取就换过来，不用重新发包。\n\n格式是一个 JSON 对象，键名固定（见下方清单），值只接受数字或在允许范围内的取值。键名不认识、数值超范围都会被拒绝，并告诉你是哪一条。留空保存等于全部恢复默认。'**
  String get uiConfigHint;

  /// No description provided for @uiConfigKeys.
  ///
  /// In zh, this message translates to:
  /// **'可用键：fileCard.height（卡片高度，24~240）、fileCard.maxWidth（宽屏上限，120~2000）、fileCard.compactWidth（私信里的宽度）、fileCard.padV（上下留白）、fileCard.padH（左右留白）、fileCard.radius（圆角）、fileCard.icon（图标大小）、fileCard.nameSize（文件名字号）、fileCard.sizeSize（大小文字字号）、fileCard.gap（图标与文字间距）、fileCard.arrowIcon（右侧图标大小）、threadCard.avatarRadius（头像半径）、threadCard.gap（头像与名字间距）、threadCard.tagSide（角标位置：leftOfTime / rightOfTime / belowTime）。'**
  String get uiConfigKeys;

  /// No description provided for @uiConfigSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get uiConfigSave;

  /// No description provided for @uiConfigSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存，返回上一页就能看到'**
  String get uiConfigSaved;

  /// No description provided for @uiConfigBadJson.
  ///
  /// In zh, this message translates to:
  /// **'不是合法的 JSON 对象'**
  String get uiConfigBadJson;

  /// No description provided for @uiConfigDefaults.
  ///
  /// In zh, this message translates to:
  /// **'填回默认值'**
  String get uiConfigDefaults;

  /// No description provided for @uiConfigRejected.
  ///
  /// In zh, this message translates to:
  /// **'有 {count} 条被拒绝：\n{lines}'**
  String uiConfigRejected(int count, String lines);

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @dmRecall.
  ///
  /// In zh, this message translates to:
  /// **'撤回'**
  String get dmRecall;

  /// No description provided for @dmRecalledMine.
  ///
  /// In zh, this message translates to:
  /// **'你撤回了一条消息'**
  String get dmRecalledMine;

  /// No description provided for @dmRecalledPeer.
  ///
  /// In zh, this message translates to:
  /// **'对方撤回了一条消息'**
  String get dmRecalledPeer;

  /// No description provided for @dmRead.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get dmRead;

  /// No description provided for @saveToCloud.
  ///
  /// In zh, this message translates to:
  /// **'添加到云盘'**
  String get saveToCloud;

  /// No description provided for @alreadyInCloud.
  ///
  /// In zh, this message translates to:
  /// **'该文件已在云盘中'**
  String get alreadyInCloud;

  /// No description provided for @addedToCloud.
  ///
  /// In zh, this message translates to:
  /// **'已添加到云盘'**
  String get addedToCloud;

  /// No description provided for @dmMulti.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get dmMulti;

  /// No description provided for @dmSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索聊天记录'**
  String get dmSearchHint;

  /// No description provided for @dmSearchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的消息'**
  String get dmSearchEmpty;

  /// No description provided for @dmNewBelow.
  ///
  /// In zh, this message translates to:
  /// **'{n} 条新消息'**
  String dmNewBelow(int n);

  /// No description provided for @dmSelectCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {n} 条'**
  String dmSelectCount(int n);

  /// No description provided for @dmEmoji.
  ///
  /// In zh, this message translates to:
  /// **'表情'**
  String get dmEmoji;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get saved;

  /// No description provided for @accentIsIdentity.
  ///
  /// In zh, this message translates to:
  /// **'这个颜色也是你的颜色——私信气泡、头像外圈、楼层都跟着它，别人看得到。'**
  String get accentIsIdentity;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @select.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get select;

  /// No description provided for @selectedN.
  ///
  /// In zh, this message translates to:
  /// **'已选 {v1} 个'**
  String selectedN(String v1);

  /// No description provided for @deleteTheseN.
  ///
  /// In zh, this message translates to:
  /// **'删掉这 {v1} 个？'**
  String deleteTheseN(String v1);

  /// No description provided for @movedToTrashN.
  ///
  /// In zh, this message translates to:
  /// **'{v1} 个已移入回收站'**
  String movedToTrashN(String v1);

  /// No description provided for @cloudNoRoom.
  ///
  /// In zh, this message translates to:
  /// **'空间不够了，还剩 {v1}'**
  String cloudNoRoom(String v1);

  /// No description provided for @uploadQueuedN.
  ///
  /// In zh, this message translates to:
  /// **'上传 ·{v1}'**
  String uploadQueuedN(String v1);

  /// No description provided for @moreQueuedN.
  ///
  /// In zh, this message translates to:
  /// **'还有 {v1} 个在排队'**
  String moreQueuedN(String v1);

  /// No description provided for @waitingTurn.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get waitingTurn;

  /// No description provided for @newRepliesN.
  ///
  /// In zh, this message translates to:
  /// **'有 {v1} 条新回复'**
  String newRepliesN(String v1);

  /// No description provided for @newMessagesBelow.
  ///
  /// In zh, this message translates to:
  /// **'以下是新消息'**
  String get newMessagesBelow;

  /// No description provided for @endpointHint.
  ///
  /// In zh, this message translates to:
  /// **'两个地址是同一个站。主入口连不上时会自己走备用那条。'**
  String get endpointHint;

  /// No description provided for @handleHint.
  ///
  /// In zh, this message translates to:
  /// **'别人用 @ 找到你；小写字母、数字、下划线，3–16 位'**
  String get handleHint;

  /// No description provided for @profileSavedHint.
  ///
  /// In zh, this message translates to:
  /// **'改完立刻生效，回主页刷新就能看到。'**
  String get profileSavedHint;

  /// No description provided for @bindEmailWhy.
  ///
  /// In zh, this message translates to:
  /// **'绑了之后，忘记密码不用找人：登录页点「忘记密码」，收个验证码就能改。'**
  String get bindEmailWhy;

  /// No description provided for @newPasswordOnce.
  ///
  /// In zh, this message translates to:
  /// **'关掉就看不到了。让本人登录后马上改成自己记得的。'**
  String get newPasswordOnce;

  /// No description provided for @creditsAdminOnly.
  ///
  /// In zh, this message translates to:
  /// **'这份名单只有管理员能改（当前登录：{v1}）。'**
  String creditsAdminOnly(String v1);

  /// No description provided for @permOptionalNote.
  ///
  /// In zh, this message translates to:
  /// **'不想开的可以一直关着，只是发图时得手动去系统里选。'**
  String get permOptionalNote;

  /// No description provided for @siteAddHint.
  ///
  /// In zh, this message translates to:
  /// **'填对方给的地址，带不带 http:// 都行'**
  String get siteAddHint;

  /// No description provided for @siteImportPasteHint.
  ///
  /// In zh, this message translates to:
  /// **'把 bbs.json 的内容贴进来，一个文件可以有多座站'**
  String get siteImportPasteHint;

  /// No description provided for @notifyImage.
  ///
  /// In zh, this message translates to:
  /// **'[图片]'**
  String get notifyImage;

  /// No description provided for @transfers.
  ///
  /// In zh, this message translates to:
  /// **'传输'**
  String get transfers;

  /// No description provided for @uploadsTab.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get uploadsTab;

  /// No description provided for @downloadsTab.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloadsTab;

  /// No description provided for @trashFilesTab.
  ///
  /// In zh, this message translates to:
  /// **'云盘文件'**
  String get trashFilesTab;

  /// No description provided for @trashThreadsTab.
  ///
  /// In zh, this message translates to:
  /// **'帖子'**
  String get trashThreadsTab;

  /// No description provided for @trashEmptyFiles.
  ///
  /// In zh, this message translates to:
  /// **'回收站里没有文件'**
  String get trashEmptyFiles;

  /// No description provided for @trashEmptyThreads.
  ///
  /// In zh, this message translates to:
  /// **'回收站里没有帖子'**
  String get trashEmptyThreads;

  /// No description provided for @trashKeptHint.
  ///
  /// In zh, this message translates to:
  /// **'删掉的东西先在这儿放几天，过期才真清。'**
  String get trashKeptHint;

  /// No description provided for @trashThreadHint.
  ///
  /// In zh, this message translates to:
  /// **'帖子删了也会在这儿留几天，想找回来还来得及。'**
  String get trashThreadHint;

  /// No description provided for @threadBack.
  ///
  /// In zh, this message translates to:
  /// **'帖子回来了'**
  String get threadBack;

  /// No description provided for @threadPurgeHint.
  ///
  /// In zh, this message translates to:
  /// **'帖子里的回复、点赞、通知在删的时候就清了，彻底删掉就只剩这一下。'**
  String get threadPurgeHint;

  /// No description provided for @restored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复'**
  String get restored;

  /// No description provided for @adminTrash.
  ///
  /// In zh, this message translates to:
  /// **'管理员回收站'**
  String get adminTrash;

  /// No description provided for @adminTrashEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有管理员删掉的东西'**
  String get adminTrashEmpty;

  /// No description provided for @adminTrashHint.
  ///
  /// In zh, this message translates to:
  /// **'管理员删掉的帖子和文件，原主人那边看不到，只有这儿能捞回来。'**
  String get adminTrashHint;

  /// No description provided for @allOwners.
  ///
  /// In zh, this message translates to:
  /// **'全部用户'**
  String get allOwners;

  /// No description provided for @allKinds.
  ///
  /// In zh, this message translates to:
  /// **'全部类型'**
  String get allKinds;

  /// No description provided for @filter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get filter;

  /// No description provided for @uploadsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有在上传的文件'**
  String get uploadsEmpty;

  /// No description provided for @uploadsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'选好文件点上传，进度都在这儿看。'**
  String get uploadsEmptyHint;

  /// No description provided for @uploadsRunningN.
  ///
  /// In zh, this message translates to:
  /// **'正在传 v1 个'**
  String uploadsRunningN(String v1);

  /// No description provided for @uploadsFailedN.
  ///
  /// In zh, this message translates to:
  /// **'v1 个没传上去'**
  String uploadsFailedN(String v1);

  /// No description provided for @uploadsDoneN.
  ///
  /// In zh, this message translates to:
  /// **'已传完 v1 个'**
  String uploadsDoneN(String v1);

  /// No description provided for @clearFinished.
  ///
  /// In zh, this message translates to:
  /// **'清空已完成'**
  String get clearFinished;

  /// No description provided for @uploading.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get uploading;

  /// No description provided for @uploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'没传上去'**
  String get uploadFailed;

  /// No description provided for @uploadedOk.
  ///
  /// In zh, this message translates to:
  /// **'已传完'**
  String get uploadedOk;
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
