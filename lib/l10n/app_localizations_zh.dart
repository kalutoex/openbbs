// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class LZh extends L {
  LZh([String locale = 'zh']) : super(locale);

  @override
  String get netDownBanner => '连不上服务器，网络一通就自己收起来';

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
  String get confirm => '确定';

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
  String get notice => '通知';

  @override
  String get me => '我的';

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
  String get confirmLogout => '退出登录？';

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

  @override
  String get needLogin => '先登录';

  @override
  String get forgetIt => '算了';

  @override
  String get follow => '关注';

  @override
  String connectFailed(String v1) {
    return '连不上服务器：$v1';
  }

  @override
  String get myFavorites => '我的收藏';

  @override
  String get browseHistory => '浏览历史';

  @override
  String get notLoggedIn => '还没登录';

  @override
  String get menu => '菜单';

  @override
  String get densityNormal => '标准';

  @override
  String get timeline => '时间线';

  @override
  String get deleteIt => '删掉';

  @override
  String get postDeleted => '帖子已删';

  @override
  String get emailAndCodeRequired => '邮箱和验证码都要填';

  @override
  String maxImages(String v1) {
    return '最多 $v1 张';
  }

  @override
  String get imageStillTooBig => '有张图压完还是太大，跳过了';

  @override
  String get addImageShort => '加图';

  @override
  String get accept => '采纳';

  @override
  String get wontDo => '不做';

  @override
  String get endOfList => '到底了';

  @override
  String get following => '已关注';

  @override
  String get sortUpdated => '最新回复';

  @override
  String get sortCreated => '最新发布';

  @override
  String get connectFailedPlain => '连不上服务器';

  @override
  String get server => '服务器';

  @override
  String get checkUpdate => '检查更新';

  @override
  String uploadFailedWith(String v1) {
    return '上传失败：$v1';
  }

  @override
  String get album => '相册';

  @override
  String get allowed => '已允许';

  @override
  String get accountManagement => '账号管理';

  @override
  String get featureRequests => '想要的新功能';

  @override
  String get tapToRetry => '点一下重试';

  @override
  String saveFailed(String v1) {
    return '保存失败：$v1';
  }

  @override
  String get deleteThreadConfirm => '帖子和下面所有回复一起消失，删了找不回来。';

  @override
  String get pinned => '置顶';

  @override
  String get fillEmailFirst => '先填邮箱';

  @override
  String get accountSecurity => '账号安全';

  @override
  String get code => '验证码';

  @override
  String get remove => '移除';

  @override
  String get ignore => '忽略';

  @override
  String get loadMore => '加载更多';

  @override
  String get post => '帖子';

  @override
  String get resetPassword => '重置密码';

  @override
  String get newPassword => '新密码';

  @override
  String albumFailed(String v1) {
    return '打不开相册：$v1';
  }

  @override
  String readImageFailed(String v1) {
    return '读图失败：$v1';
  }

  @override
  String get publishing => '发布中…';

  @override
  String get clear => '清除';

  @override
  String get saving => '保存中…';

  @override
  String get editPost => '编辑帖子';

  @override
  String get clearAll => '清空';

  @override
  String get tryAgain => '再试一次';

  @override
  String get addPeople => '加人';

  @override
  String get takeDown => '拿下来';

  @override
  String get permissions => '权限';

  @override
  String get auto => '自动';

  @override
  String get manual => '手动';

  @override
  String get fontSize => '字号';

  @override
  String get listDensity => '列表密度';

  @override
  String get feedSort => '时间线排序';

  @override
  String get startTab => '启动页';

  @override
  String get sizeSmall => '小';

  @override
  String get sizeHuge => '特大';

  @override
  String get sizeLarge => '大';

  @override
  String get densityCompact => '紧凑';

  @override
  String get densityLoose => '宽松';

  @override
  String get chinese => '中文';

  @override
  String get updateChannel => '更新通道';

  @override
  String get clearCache => '清除缓存';

  @override
  String get jumpToFloor => '跳转楼层';

  @override
  String get changed => '改好了';

  @override
  String get deletePostConfirm => '删掉这帖？';

  @override
  String get edited => '已编辑';

  @override
  String get hueRed => '红';

  @override
  String get hueOrangeRed => '橙红';

  @override
  String get hueOrange => '橙';

  @override
  String get hueAmber => '橙黄';

  @override
  String get hueYellow => '黄';

  @override
  String get hueLime => '黄绿';

  @override
  String get hueGrass => '草绿';

  @override
  String get hueGreen => '绿';

  @override
  String get hueTeal => '青绿';

  @override
  String get hueCyan => '青';

  @override
  String get hueAzure => '青蓝';

  @override
  String get hueBlue => '蓝';

  @override
  String get hueIndigo => '靛蓝';

  @override
  String get hueViolet => '紫蓝';

  @override
  String get huePurple => '紫';

  @override
  String get hueMagenta => '紫红';

  @override
  String get huePink => '粉';

  @override
  String get huePinkLight => '浅粉';

  @override
  String get permNotificationWhy => '有人回复、赞你时提醒你';

  @override
  String get permPhotosWhy => '发帖、回复时从相册选图';

  @override
  String get permDeniedForever => '已拒绝 · 去系统设置开';

  @override
  String get permRestricted => '被系统限制';

  @override
  String get permAsk => '未允许 · 点一下申请';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(String v1) {
    return '$v1 分钟前';
  }

  @override
  String get yesterday => '昨天';

  @override
  String bigNumSuffix(String v1) {
    return '$v1万';
  }

  @override
  String get am => '上午';

  @override
  String get pm => '下午';

  @override
  String postTimeFmt(
    String v1,
    String v2,
    String v3,
    String v4,
    String v5,
    String v6,
  ) {
    return '$v1年$v2月$v3日, $v4:$v5 $v6';
  }

  @override
  String get threadSpacing => '帖子之间的间距';

  @override
  String get browseSection => '浏览';

  @override
  String get startTabHint => '打开 app 先看哪个';

  @override
  String get easterEggButton => '没啥用的小按钮';

  @override
  String get easterEggTitle => '小玩意';

  @override
  String get hueCards => '卡片跟着人染色';

  @override
  String get showThumbnails => '显示缩略图';

  @override
  String get showThumbnailsHint => '关掉后时间线只留文字，省流量';

  @override
  String get autoCheckNotice => '自动检查通知';

  @override
  String get autoCheckNoticeHint => '每分钟问一次未读数';

  @override
  String get networkSection => '网络';

  @override
  String get contentSection => '内容';

  @override
  String get clearSearchHistory => '清除搜索记录';

  @override
  String get searchHistoryCleared => '搜索记录已清除';

  @override
  String get permSubtitle => '通知、相册';

  @override
  String get currentAccount => '当前账号';

  @override
  String get noEmailBoundHint => '还没绑邮箱，忘了密码只能找管理员';

  @override
  String get webAccessSection => '网页访问';

  @override
  String aboutBrand(String v1) {
    return '关于$v1';
  }

  @override
  String get aboutSubtitle => '开源信息、更新日志、许可证';

  @override
  String get logoutShort => '退出';

  @override
  String get version => '版本';

  @override
  String get tapToCheckUpdate => '点一下检查更新';

  @override
  String get betaChannelHint => '内测版，只推给你';

  @override
  String get stableChannelHint => '稳定版，所有人都在用';

  @override
  String get stableOption => '稳定版　验证过的';

  @override
  String get betaOption => '内测版　改一点就推给你';

  @override
  String betaVersion(String v1) {
    return '内测版 $v1';
  }

  @override
  String newVersion(String v1) {
    return '有新版本 $v1';
  }

  @override
  String installOverwrite(String v1) {
    return '大小 $v1，装完会覆盖当前版本，登录和设置都还在。';
  }

  @override
  String get later => '以后再说';

  @override
  String get downloadAndInstall => '下载并安装';

  @override
  String get mustUpdate => '这一版太旧了，先更新才能继续用。';

  @override
  String get downloading => '正在下载';

  @override
  String get handedToSystem => '已交给系统打开';

  @override
  String get handedToInstaller => '已交给系统安装，没反应就去设置里允许安装未知应用';

  @override
  String downloadFailedWith(String v1) {
    return '下载失败：$v1';
  }

  @override
  String get primaryEndpoint => '当前入口';

  @override
  String get backupEndpoint => '备用入口';

  @override
  String get addressCopied => '地址已复制';

  @override
  String get clearing => '正在清…';

  @override
  String get calculating => '正在算…';

  @override
  String get cacheEmpty => '暂时是空的';

  @override
  String cacheSize(String v1) {
    return '占 $v1';
  }

  @override
  String get cleared => '已清除';

  @override
  String clearedAmount(String v1) {
    return '已清除 $v1';
  }

  @override
  String newerThanServer(String v1, String v2, String v3) {
    return '你手上是 build $v1，比$v2版的 $v3 还新。同签名的包不能往低号装，要回退得先卸载。';
  }

  @override
  String upToDate(String v1) {
    return '已是最新版（$v1）';
  }

  @override
  String accountLine(String v1, String v2) {
    return '$v1 · 本机 $v2 个账号';
  }

  @override
  String get betaShort => '内测';

  @override
  String get stableShort => '稳定';

  @override
  String releaseNotes(String v1, String v2) {
    return '$v1\n\n大小 $v2，装完会覆盖当前版本，登录和设置都还在。';
  }

  @override
  String get clearCacheConfirm => '图片和接口缓存都会删掉，下次打开重新下载。\n登录状态和设置不受影响。';

  @override
  String get floorJumpHint => '输入楼层号，比如 128';

  @override
  String get jump => '跳';

  @override
  String notReachedFloor(String v1) {
    return '还没翻到第 $v1 楼';
  }

  @override
  String noSuchFloor(String v1) {
    return '没有第 $v1 楼';
  }

  @override
  String get offlineCached => '网络不通，下面是上次缓存的内容';

  @override
  String get pinnedToast => '已置顶';

  @override
  String get unpinnedToast => '已取消置顶';

  @override
  String get featuredToast => '已加精';

  @override
  String get unfeaturedToast => '已取消加精';

  @override
  String get reportReason => '举报理由';

  @override
  String get reportSpam => '垃圾广告';

  @override
  String get reportAbuse => '人身攻击';

  @override
  String get reportIllegal => '违法违规';

  @override
  String get reportFalse => '内容不实';

  @override
  String get reportOther => '其他';

  @override
  String get reportDuplicate => '已经报过一次了';

  @override
  String get reportThanks => '收到了，会看';

  @override
  String get editFloor => '改这一楼';

  @override
  String get saySomething => '说点什么…';

  @override
  String get replaceWithPlaceholder => '换成占位图？';

  @override
  String get replacePlaceholderConfirm => '这一帖和下面所有回复里的图都会换成同一张占位图，原图找不回来。';

  @override
  String replacedImages(String v1) {
    return '已换掉 $v1 张图';
  }

  @override
  String get deleteFloorConfirm => '删除这楼？';

  @override
  String get deleteThreadBody => '帖子连同所有回复一起删掉，删了不能恢复。';

  @override
  String get deleteFloorBody => '这楼和它下面的楼中楼一起删掉。';

  @override
  String get deleteReplyConfirm => '删除这条回复？';

  @override
  String get cannotUndo => '删了不能恢复。';

  @override
  String get onlyAuthorOn => '已只看楼主';

  @override
  String get onlyAuthorOff => '只看楼主';

  @override
  String jumpToFloorPages(String v1) {
    return '跳转楼层（共 $v1 页）';
  }

  @override
  String get unpin => '取消置顶';

  @override
  String get unfeature => '取消加精';

  @override
  String get feature => '加精';

  @override
  String get replaceAllImages => '一键替换图片';

  @override
  String get deletePost => '删除帖子';

  @override
  String viewsCount(String v1) {
    return '$v1 浏览';
  }

  @override
  String get related => '相关';

  @override
  String repliesCount(String v1) {
    return '$v1 条回复';
  }

  @override
  String get noReplies => '还没有回复';

  @override
  String get favorited => '已收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get meShort => '我';

  @override
  String replyTo(String v1) {
    return '回复 $v1';
  }

  @override
  String get replyHint => '发布你的回复';

  @override
  String get maxNineImages => '最多 9 张';

  @override
  String get opAuthor => '楼主';

  @override
  String get copyFullText => '复制全文';

  @override
  String get copied => '已复制';

  @override
  String get collapse => '收起';

  @override
  String expandAllReplies(String v1) {
    return '展开全部 $v1 条回复';
  }

  @override
  String get resumeDraft => '接着上次的写';

  @override
  String resumeDraftImages(String v1) {
    return '接着上次的写，带 $v1 张图';
  }

  @override
  String get discardDraft => '清掉';

  @override
  String get pickFromAlbum => '从相册选';

  @override
  String canAddMore(String v1) {
    return '还能加 $v1 张';
  }

  @override
  String get takePhoto => '拍一张';

  @override
  String cameraFailed(String v1) {
    return '打不开相机：$v1';
  }

  @override
  String tooManyImages(String v1) {
    return '最多 $v1 张，多的没收';
  }

  @override
  String get deleteThisImage => '删掉这张';

  @override
  String uploadingStart(String v1) {
    return '上传图片 0/$v1';
  }

  @override
  String uploadingImages(String v1, String v2) {
    return '上传图片 $v1/$v2';
  }

  @override
  String postFailed(String v1) {
    return '发不出去：$v1';
  }

  @override
  String get draftUnsaved => '这篇还没发出去';

  @override
  String get draftImagesNote => '图片不进草稿，只有标题和正文会留着';

  @override
  String get saveDraftAndLeave => '存草稿，先走';

  @override
  String get discardPost => '扔掉这篇';

  @override
  String get keepEditing => '再改改';

  @override
  String get composeTitle => '发新帖';

  @override
  String get composeHint => '说点什么…（@ 找人）';

  @override
  String imageCount(String v1, String v2) {
    return '图片 $v1/$v2';
  }

  @override
  String get dragToReorder => '长按拖动换顺序';

  @override
  String titleRequiredMaxImages(String v1) {
    return '标题必填 · 最多 $v1 张图';
  }

  @override
  String imageCountPrefix(String v1, String v2, String v3) {
    return '$v1/$v2 张 · $v3';
  }

  @override
  String bodyLength(String v1) {
    return '$v1 字';
  }

  @override
  String restoreFailed(String v1) {
    return '恢复失败：$v1';
  }

  @override
  String codeSendFailed(String v1) {
    return '验证码没发出去：$v1';
  }

  @override
  String get passwordTooShort => '密码至少 8 位';

  @override
  String passwordChangeFailed(String v1) {
    return '没改成：$v1';
  }

  @override
  String get fillUserAndPassword => '用户名和密码都要填';

  @override
  String loginFailed(String v1) {
    return '登录没成功：$v1';
  }

  @override
  String get resetTitle => '找回密码';

  @override
  String get atLeast8 => '至少 8 位';

  @override
  String get emailUsedToRegister => '注册时用的邮箱';

  @override
  String get emailForCode => '用来收注册验证码';

  @override
  String get sending => '发送中';

  @override
  String get getCode => '获取验证码';

  @override
  String get changePasswordAndLogin => '改密码并登录';

  @override
  String get registerAndLogin => '注册并登录';

  @override
  String get backToLogin => '返回登录';

  @override
  String get haveAccountLogin => '已有账号，去登录';

  @override
  String get noAccountRegister => '没有账号，去注册';

  @override
  String get forgotPasswordQuestion => '忘记密码？';

  @override
  String get accountCopied => '账号已复制';

  @override
  String get coverUpdated => '封面已换';

  @override
  String coverFailed(String v1) {
    return '换封面失败：$v1';
  }

  @override
  String get saveCover => '保存背景图';

  @override
  String get saveCoverConfirm => '把这张背景图存到相册？';

  @override
  String savedTo(String v1) {
    return '已保存到 $v1';
  }

  @override
  String get changeCover => '换封面';

  @override
  String get addCover => '加封面';

  @override
  String joinedAt(String v1) {
    return '加入于 $v1';
  }

  @override
  String get followingCount => '正在关注';

  @override
  String get followers => '关注者';

  @override
  String get editProfile => '编辑个人资料';

  @override
  String get noPostsYet => '还没有人发帖';

  @override
  String get noPostsHint => '发第一条，把这里开个头';

  @override
  String get loadFailed => '没能拉到内容';

  @override
  String get longAgo => '很久以前';

  @override
  String yearMonth(String v1, String v2) {
    return '$v1 年 $v2 月';
  }

  @override
  String get acceptConfirm => '采纳这条？';

  @override
  String get rejectConfirm => '不做这条？';

  @override
  String get reopenConfirm => '退回待看？';

  @override
  String get replyOptional => '回一句（可选）';

  @override
  String get adminReplyHint => '排期中 / 做不了，原因是……';

  @override
  String get accepted => '已采纳';

  @override
  String get markedWontDo => '已标记不做';

  @override
  String get movedBack => '已退回待看';

  @override
  String get requestsDone => '需求 · 已处理';

  @override
  String requestsCount(String v1) {
    return '需求（$v1）';
  }

  @override
  String get requests => '需求';

  @override
  String get viewPending => '看待看';

  @override
  String get viewDone => '看已处理';

  @override
  String get nothingHandled => '还没处理过';

  @override
  String get noPendingRequests => '没有待看的需求';

  @override
  String replyLine(String v1) {
    return '回复：$v1';
  }

  @override
  String submittedBy(String v1) {
    return '提交人：$v1';
  }

  @override
  String get moveBack => '退回待看';

  @override
  String avatarUpdated(String v1) {
    return '头像已换上 · $v1';
  }

  @override
  String get chooseFromAlbum => '从相册选择';

  @override
  String get compressNote => '自动压到 100KB 上下再上传';

  @override
  String get nicknameRequired => '昵称不能为空';

  @override
  String get handleInvalid => '标识只能用小写字母、数字、下划线，3–16 位';

  @override
  String get editProfileTitle => '编辑资料';

  @override
  String get nickname => '昵称';

  @override
  String get nicknameMax => '最多 20 个字';

  @override
  String get handle => '标识';

  @override
  String get bio => '签名';

  @override
  String get bioHint => '最多 80 个字，可以留空';

  @override
  String get openSource => '开源';

  @override
  String get thanksFriends => '致谢我的朋友们';

  @override
  String get thanksFriendsSub => '这里是他们的账号';

  @override
  String get thirdPartyLicenses => '第三方许可证';

  @override
  String get thirdPartyLicensesSub => '各依赖自带的许可文本';

  @override
  String get gplLicense => 'GPL-3.0 许可证';

  @override
  String get gplLicenseSub => '本项目以 GPL-3.0 发布';

  @override
  String get links => '链接';

  @override
  String get sourceCode => '源代码';

  @override
  String get issues => '问题反馈';

  @override
  String get issuesSub => '发现什么不对，记在这里';

  @override
  String get cantOpenLink => '打不开这个链接';

  @override
  String get reportKeepNote => '这条没问题，关掉举报。';

  @override
  String get reportDeleteFloorNote => '楼层内容会被删掉，删了找不回来。';

  @override
  String get reportDeletePostNote => '整个帖子连同回复一起删掉，删了找不回来。';

  @override
  String get ignoreReportConfirm => '忽略这条举报？';

  @override
  String get deleteContentConfirm => '删掉这条内容？';

  @override
  String get ignored => '已忽略';

  @override
  String get deleted => '已删掉';

  @override
  String reportsCount(String v1) {
    return '举报（$v1）';
  }

  @override
  String get noReports => '没有待处理的举报';

  @override
  String get floor => '楼层';

  @override
  String reportLine(String v1, String v2) {
    return '理由：$v1　举报人：$v2';
  }

  @override
  String galleryReadFailed(String v1) {
    return '相册读不出来：$v1';
  }

  @override
  String albumOpenFailed(String v1) {
    return '这个相册打不开：$v1';
  }

  @override
  String maxSelectImages(String v1) {
    return '最多选 $v1 张';
  }

  @override
  String get pickPhotos => '选择照片';

  @override
  String doneWithCount(String v1) {
    return '完成 ($v1)';
  }

  @override
  String get albumEmpty => '这个相册里没有图片';

  @override
  String get needsAlbumPermission => '需要相册权限才能列出照片';

  @override
  String get noAlbumUsePicker => '这台机器没有相册，用系统的文件选择';

  @override
  String get localThumbsOnly => '只在本机缩略图里挑，不上传整本相册。';

  @override
  String get grantPermission => '去开权限';

  @override
  String get pickAnotherWay => '换个方式选图';

  @override
  String get titleClearer => '标题再写清楚一点';

  @override
  String get requestDuplicate => '这条已经提过了';

  @override
  String get requestSubmitted => '提交好了';

  @override
  String get requestIntro => '想到什么功能，写在这里。管理员会看，采纳了会回一句。';

  @override
  String get requestTitleLabel => '一句话说清要什么';

  @override
  String get requestTitleHint => '比如：帖子支持收藏到不同文件夹';

  @override
  String get requestDetailLabel => '细节（可选）';

  @override
  String get requestDetailHint => '为什么需要、大概怎么用';

  @override
  String get myRequests => '我提过的';

  @override
  String requestCount(String v1) {
    return '$v1 条';
  }

  @override
  String get noRequestsYet => '还没提过';

  @override
  String get statusPending => '待看';

  @override
  String get codeSentCheckEmail => '验证码发出去了，去邮箱里看看';

  @override
  String get emailBound => '绑好了';

  @override
  String get noEmailWarning => '这个账号还没绑邮箱。忘了密码的话，现在只能找管理员重置。';

  @override
  String get emailBoundHint => '已绑定，忘了密码可以自己重置';

  @override
  String get bindEmail => '绑定邮箱';

  @override
  String get changeEmail => '换一个邮箱';

  @override
  String get sendCode => '发送验证码';

  @override
  String get processing => '处理中…';

  @override
  String get bind => '绑定';

  @override
  String get rebind => '换绑';

  @override
  String get titleEmpty => '标题不能空';

  @override
  String get bodyOrImageRequired => '正文或图片至少留一样';

  @override
  String uploadingNewStart(String v1) {
    return '上传新图 0/$v1';
  }

  @override
  String uploadingNewImages(String v1, String v2) {
    return '上传新图 $v1/$v2';
  }

  @override
  String get changesUnsaved => '改动还没保存';

  @override
  String get continueEditing => '继续改';

  @override
  String get leaveWithoutSaving => '不保存，退出';

  @override
  String imageCountShort(String v1, String v2) {
    return '图片 $v1/$v2';
  }

  @override
  String get noImagesYet => '还没有图';

  @override
  String noSearchResult(String v1) {
    return '没搜到「$v1」';
  }

  @override
  String searchResultCount(String v1) {
    return '搜到 $v1 个';
  }

  @override
  String get goLogin => '去登录';

  @override
  String get noIntro => '还没有简介';

  @override
  String get nRepliedPost => '回复了你的帖';

  @override
  String get nRepliedYou => '回复了你';

  @override
  String get nLiked => '赞了你';

  @override
  String get nMentioned => '在帖子里 @ 了你';

  @override
  String get nFeatured => '把你的帖加精了';

  @override
  String get nDeleted => '删了你的内容';

  @override
  String get nNew => '有新消息';

  @override
  String get noticeLoginNeeded => '登录后才能收到通知';

  @override
  String get noticeLoginHint => '去「我的」登录';

  @override
  String get noNotifications => '还没有通知';

  @override
  String get noNotificationsHint => '别人回复你、赞你，会出现在这里';

  @override
  String get reset => '重置';

  @override
  String newPasswordFor(String v1) {
    return '给「$v1」的新密码：';
  }

  @override
  String get copyAndClose => '复制并关闭';

  @override
  String get searchUsername => '搜用户名';

  @override
  String get noEmail => '没绑邮箱';

  @override
  String get manualNeedsAddress => '手动要填地址';

  @override
  String serverOkUsing(String v1) {
    return '通了，当前用 $v1';
  }

  @override
  String connectFailedBody(String v1) {
    return '连不上：$v1';
  }

  @override
  String get ipv6FirstHint => '先试 IPv6，连不上再用 IPv4';

  @override
  String get channelIpv6 => 'IPv6 通道';

  @override
  String get channelIpv4 => 'IPv4 通道';

  @override
  String get enterManually => '自己填地址';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get saveAndTest => '保存并测试';

  @override
  String currentExit(String v1) {
    return '当前出口：$v1';
  }

  @override
  String switchedTo(String v1) {
    return '已切换到 $v1';
  }

  @override
  String accountExpiredRemoved(String v1) {
    return '$v1 的登录已失效，已移除';
  }

  @override
  String get removeAccount => '移除账号';

  @override
  String removeAccountConfirm(String v1) {
    return '从本机移除 $v1？只是退出这台设备，账号和帖子都还在服务器上。';
  }

  @override
  String accountAdded(String v1) {
    return '已添加 $v1';
  }

  @override
  String get noAccounts => '还没有账号';

  @override
  String get addAccount => '添加账号';

  @override
  String get addAccountHint => '登录另一个账号，之后可以随时切回来';

  @override
  String get friendSearchHint => '用户名 / @标识 / 昵称';

  @override
  String get enterName => '写个名字';

  @override
  String get add => '添加';

  @override
  String removeFriendConfirm(String v1) {
    return '把 $v1 拿下来？';
  }

  @override
  String get removeFriendBody => '只是从这页去掉，账号还在。';

  @override
  String get credits => '致谢';

  @override
  String get nobodyYet => '还没有人';

  @override
  String unfollowed(String v1) {
    return '已取消关注 $v1';
  }

  @override
  String followedBack(String v1) {
    return '已回关 $v1';
  }

  @override
  String get fans => '粉丝';

  @override
  String get notFollowingAnyone => '还没关注谁';

  @override
  String get noFans => '还没有粉丝';

  @override
  String get mutual => '互相关注';

  @override
  String get followBack => '回关';

  @override
  String get searchTitleOrBody => '搜标题或内容';

  @override
  String get searchPrompt => '输入关键词，按回车';

  @override
  String get recentSearches => '最近搜索';

  @override
  String totalCount(String v1) {
    return '共 $v1 条';
  }

  @override
  String endTotalCount(String v1) {
    return '到底了，共 $v1 条';
  }

  @override
  String get noFavoritesYet => '还没收藏过帖';

  @override
  String get reportHandling => '举报处理';

  @override
  String get requestHandling => '需求处理';

  @override
  String get noHistoryYet => '还没有浏览记录';

  @override
  String get enterBio => '请输入你的个人签名';

  @override
  String get tapToLogin => '点这里登录';

  @override
  String get general => '综合';

  @override
  String get featured => '精华';

  @override
  String get multiImage => '多图片';

  @override
  String get comments => '评论';

  @override
  String get loginBenefits => '登录后可以发帖、回复、关注吧';

  @override
  String get hot => '热门';

  @override
  String get permIntro => '联网权限安装时已经给了，这里只剩通知和相册需要你点头。';

  @override
  String get network => '联网';

  @override
  String get networkGranted => '安装时自动授予，不用管';

  @override
  String get downloadImage => '下载这张图';

  @override
  String get backToTop => '回到顶部';

  @override
  String get offlineCacheFeed => '连不上服务器，这是上次的缓存';

  @override
  String get fillAddress => '填一下地址';

  @override
  String get fillServerAddress => '填一下服务器地址';

  @override
  String get connect => '连上去';

  @override
  String get themeColorTitle => '主题颜色';

  @override
  String get accentColorHint => '上面的按钮、选中状态、输入框焦点圈都会跟着这条色带走。';

  @override
  String get followWallpaper => '跟随壁纸取色';

  @override
  String get followWallpaperHint => 'Android 12 及以上可用。开启后主题色由系统壁纸决定，下面的色带不起作用。';

  @override
  String get appIconTitle => '应用图标';

  @override
  String get appIconHint =>
      '桌面图标和名字是打包时定死的，这里换的是预先做好的几套。选完桌面要等几秒才变，个别启动器还得重启一下。';

  @override
  String get appIconChanged => '换好了，看桌面';

  @override
  String get appIconUnavailable => '这个平台上换不了图标';

  @override
  String get moreToLoad => '还有更多';

  @override
  String resetPasswordConfirm(String v1) {
    return '把「$v1」的密码换成随机的一串？\n\n原密码会立刻失效。新密码只显示一次，记得发给本人。';
  }

  @override
  String siteNeedsUpdate(Object v1, Object v2) {
    return '这个站点的接口版本是 $v1，当前客户端只认到 $v2。请更新客户端后再用。';
  }

  @override
  String get sitesManage => '站点管理';

  @override
  String get sitesManageHint => '一个入口管多个站，连不上的自动跳过';

  @override
  String get siteAdd => '添加站点';

  @override
  String get siteImportPaste => '粘贴清单';

  @override
  String get siteImportMaster => '从主站拉目录';

  @override
  String get importIt => '导入';

  @override
  String siteImportFailed(String v1) {
    return '读不出清单：$v1';
  }

  @override
  String get siteImportEmpty => '这份清单里没有站点';

  @override
  String siteImportNone(String v1) {
    return '没有可导入的站：$v1';
  }

  @override
  String siteImported(String v1) {
    return '导入 $v1 座站';
  }

  @override
  String siteImportedSkipped(String v1, String v2, String v3) {
    return '导入 $v1 座站，跳过 $v2 条：$v3';
  }

  @override
  String get skipNoUrl => '没有地址';

  @override
  String get skipDuplicateId => 'id 重复';

  @override
  String get skipApiTooNew => '接口版本太新';

  @override
  String get skipBadFormat => '不是清单格式';

  @override
  String get siteEmpty => '还没有站点';

  @override
  String get siteEmptyHint => '填一个地址就能开始，账号和帖子都在对方服务器上。';

  @override
  String get siteLoginSite => '登录站';

  @override
  String get siteCurrentNow => '当前';

  @override
  String get siteUnreachable => '连不上';

  @override
  String get siteSetLogin => '设为登录站';

  @override
  String get siteSwitch => '切换';

  @override
  String get siteProbe => '重新探测';

  @override
  String siteRemoveConfirm(String v1) {
    return '从这台设备移除 $v1？账号和帖子都还在服务器上。';
  }

  @override
  String siteLoginSet(String v1) {
    return '登录站改成 $v1';
  }

  @override
  String get sites => '站点';

  @override
  String get siteMaster => '主站';

  @override
  String get siteSmall => '小站';

  @override
  String get sitePostTo => '发到';

  @override
  String get siteMasterFixed => '主站不能移除';

  @override
  String get siteSpeedTest => '测速';

  @override
  String get siteSpeedRunning => '测速中…';

  @override
  String siteSpeedResult(String v1) {
    return '测速：$v1';
  }

  @override
  String get siteSpeedNone => '都不通';

  @override
  String siteSwitching(String v1) {
    return '正在切到 $v1';
  }

  @override
  String get listSep => '、';

  @override
  String get bannedTitle => '账号已被封禁';

  @override
  String get bannedBody => '这个账号被管理员封了，帖子也发不出去。换个号，或者找站长问原因。';

  @override
  String get posts => '帖子';

  @override
  String get siteBlock => '屏蔽';

  @override
  String get siteUnblock => '取消屏蔽';

  @override
  String get siteBlocked => '已屏蔽';

  @override
  String get siteBlockedDone => '已屏蔽，目录里不再显示这座站';

  @override
  String get siteUnblockedDone => '已取消屏蔽';

  @override
  String get siteCatalogEmpty => '还没有别的站';

  @override
  String get siteCatalogEmptyHint => '在设置里的「站点管理」加一座，或者等主站收录。';

  @override
  String get siteNoPosts => '这座站还没有帖子';

  @override
  String get searchThreads => '帖子';

  @override
  String get searchReplies => '回复';

  @override
  String get searchUsers => '用户';

  @override
  String get dmTitle => '私信';

  @override
  String get dmEmpty => '还没有私信';

  @override
  String get messagesTab => '消息';

  @override
  String get siteMessages => '站内消息';

  @override
  String get pinChat => '置顶';

  @override
  String get unpinChat => '取消置顶';

  @override
  String get muteChat => '免打扰';

  @override
  String get unmuteChat => '取消免打扰';

  @override
  String get markRead => '标为已读';

  @override
  String get deleteChat => '删除该聊天';

  @override
  String get dmEmptyHint => '在别人主页点「发私信」';

  @override
  String get dmEarlier => '加载更早';

  @override
  String get dmSend => '发私信';

  @override
  String get pickFromDevice => '从设备选';

  @override
  String get pickFromCloud => '从云盘选';

  @override
  String get cloudPickEmpty => '云盘里还没有文件';

  @override
  String cloudPickDone(String v1) {
    return '完成（$v1）';
  }

  @override
  String get attachFile => '附件';

  @override
  String attachMax(String v1) {
    return '最多 $v1 个附件';
  }

  @override
  String attachTooBig(String v1) {
    return '文件不能超过 $v1';
  }

  @override
  String attachUploading(String v1) {
    return '正在上传 $v1';
  }

  @override
  String get pasteCredential => '粘贴登录凭证';

  @override
  String get copyCredential => '复制登录凭证';

  @override
  String get copyCredentialHint => '重装或换机后，登录页可粘贴恢复';

  @override
  String get credentialCopied => '凭证已复制';

  @override
  String get credentialHint => '在旧设备「设置 → 复制登录凭证」里复制';

  @override
  String get restore => '恢复';

  @override
  String get credentialInvalid => '凭证无效或已失效';

  @override
  String get restoreWithCredential => '用登录凭证恢复';

  @override
  String myFollowedForums(String v1) {
    return '我关注的 $v1';
  }

  @override
  String allForums(String v1) {
    return '全部 $v1';
  }

  @override
  String forumStats(String v1, String v2) {
    return '$v1 帖 · $v2 关注';
  }

  @override
  String get addFromDevice => '把别的设备上的账号加进这台机器';

  @override
  String get cloudDisk => '云盘';

  @override
  String get recycleBin => '回收站';

  @override
  String get deleteThisFile => '删除这个文件？';

  @override
  String fileUsedByPosts(String v1) {
    return '有 $v1 个帖子正在用它。删掉之后，那些地方会显示「文件已失效」。';
  }

  @override
  String get goesToTrashHint => '文件先进回收站，7 天内还能恢复。空间会立刻还回来。';

  @override
  String get movedToTrash => '已移入回收站';

  @override
  String get notConnectedTapRetry => '没连上，点这里重试';

  @override
  String get nothingUploadedYet => '还没传过东西';

  @override
  String get notFound => '没找到';

  @override
  String get findFile => '找文件';

  @override
  String get bySize => '按大小';

  @override
  String get byTime => '按时间';

  @override
  String usedByPosts(String v1) {
    return '$v1 个帖子在用';
  }

  @override
  String fileCount2(String v1) {
    return '$v1 个文件';
  }

  @override
  String usedSpace(String v1) {
    return '已用 $v1';
  }

  @override
  String usedOfTotal(String v1, String v2) {
    return '$v1 / $v2';
  }

  @override
  String daysLeft(String v1) {
    return '还剩 $v1 天';
  }

  @override
  String hoursLeft(String v1) {
    return '还剩 $v1 小时';
  }

  @override
  String get expiringSoon => '就要清了';

  @override
  String get emptyHere => '空的';

  @override
  String get download => '下载';

  @override
  String get upload => '上传';

  @override
  String uploadingFile2(String v1) {
    return '正在上传 $v1';
  }

  @override
  String get uploadedDone => '传好了';

  @override
  String get uploadCancelled => '上传已取消';

  @override
  String uploadedDoneAll(String v1) {
    return '都传好了，$v1 个';
  }

  @override
  String uploadedFailedAll(String v1) {
    return '$v1 个都没传上去';
  }

  @override
  String uploadedPartly(String v1, String v2) {
    return '$v1 个传好了，$v2 个没成';
  }

  @override
  String get uploadFailedTapRetry => '没传上去，点那一行可以重试';

  @override
  String get uploadWrongAccount => '换过账号了，这条停在这儿。要传到当前账号，点那一行重试。';

  @override
  String get fileTooBigHint => '单个文件别超过 500MB';

  @override
  String cloudRefsWarn(String v1) {
    return '有 $v1 个帖子正在用它。删掉之后，那些地方会显示「文件已失效」。';
  }

  @override
  String get restoredDone => '恢复了';

  @override
  String get cloudUsage => '云盘用量';

  @override
  String get changeQuota => '调整额度';

  @override
  String get quotaMbHint => '额度（MB，留空 = 跟全站默认）';

  @override
  String get quotaSaved => '额度已更新';

  @override
  String get cloudQuotaDefault => '全站默认';

  @override
  String get cloudSection => '云服务';

  @override
  String get cloudSettings => '云服务设置';

  @override
  String get cloudSettingsHint => '下载存哪、下完做什么';

  @override
  String get cloudSettingsIntro => '云盘和帖子里的文件，下载后会存到下面这个位置。要换个地方就在这里改。';

  @override
  String get downloadLocation => '下载位置';

  @override
  String get downloadLocationDefault => '还没改过，用默认的「下载/OpenBBS」';

  @override
  String get downloadLocationReset => '恢复默认位置';

  @override
  String get downloadLocationDefaultHint => '回到「下载/OpenBBS」';

  @override
  String get downloadDirReset => '已恢复默认位置';

  @override
  String get downloadAutoOpen => '下完自动打开';

  @override
  String get downloadAutoOpenHint => '关掉就只存下来，自己去文件夹里找';

  @override
  String get downloadCache => '下载缓存';

  @override
  String downloadCacheUsed(String v1) {
    return '断掉的下载残留 $v1';
  }

  @override
  String get downloadCacheEmpty => '没有残留';

  @override
  String get cacheCleared => '清掉了';

  @override
  String get downloadByBrowser => '网页版的下载位置由浏览器决定，在浏览器自己的设置里改。';

  @override
  String get deleteForever => '彻底删除';

  @override
  String get deleteForeverHint => '删了就找不回来。';

  @override
  String get deletedForever => '已彻底删除';

  @override
  String get downloadedBadge => '已下载';

  @override
  String get downloadingShort => '下载中';

  @override
  String get browseFiles => '手机文件';

  @override
  String get browseFilesHint => '翻手机里的文件，选中直接传';

  @override
  String get pickFromSystem => '系统选择器';

  @override
  String get allFilesAccess => '访问所有文件';

  @override
  String get allFilesWhy => '要翻整个手机的存储，得在系统设置里给这个权限。只用来读你选中的文件，别的不动。';

  @override
  String get allFilesOpen => '去设置里开';

  @override
  String get allFilesDenied => '没拿到访问权限，翻不了手机存储';

  @override
  String get allFilesRetry => '我开好了，再试一次';

  @override
  String get searchThisFolder => '在这个文件夹里找';

  @override
  String get folderEmpty => '这个文件夹是空的';

  @override
  String get noAccessFolder => '进不去，系统限制了';

  @override
  String pickedCount(String v1) {
    return '已选 $v1';
  }

  @override
  String uploadPicked(String v1) {
    return '上传 $v1 个';
  }

  @override
  String uploadingIndexOf(String v1, String v2, String v3) {
    return '正在传 $v1/$v2：$v3';
  }

  @override
  String uploadSomeFailed(String v1, String v2) {
    return '传完 $v1 个，$v2 个没传上去';
  }

  @override
  String get storageRoot => '存储';

  @override
  String get systemFolderHidden => '系统目录（看不到内容）';

  @override
  String get dmWaitReply => '对方还没回关，等他回一句你就能接着发';

  @override
  String get dmNewMessages => '有新消息';

  @override
  String get dmTapToProfile => '点开看资料';

  @override
  String get dmNoChat => '还没聊过，说点什么吧';

  @override
  String get quote => '引用';

  @override
  String get replyRecalled => '该回复已撤回';

  @override
  String get replyRemembered => '两分钟内可以撤回，过了就撤不回了';

  @override
  String get replyImage => '[图片]';

  @override
  String get dmPickImage => '图片';

  @override
  String get dmPickFile => '文件';

  @override
  String get dmAttach => '发送';

  @override
  String get notifyNewDm => '新私信';

  @override
  String notifyNewCount(int n) {
    return '$n 条新消息';
  }

  @override
  String get sysNotify => '消息通知';

  @override
  String get sysNotifyHint => '有新消息时弹一条系统通知';

  @override
  String get sysNotifyOff => '系统通知权限没开，去手机设置里打开';

  @override
  String get bgKeepAlive => '后台保活';

  @override
  String get bgKeepAliveHint => '不豁免电池优化，系统会在后台冻住 App，锁屏后收不到提醒';

  @override
  String get bgKeepAliveOn => '已豁免';

  @override
  String get bgKeepAliveOff => '去设置';

  @override
  String get notifyPerm => '通知权限';

  @override
  String get notifyPermHint => '通知权限没开，系统一条提醒都不会显示';

  @override
  String get notifyPermOn => '已开启';

  @override
  String get notifyPermOff => '未开启';

  @override
  String get notifyPermDenied => '通知权限没开，先去系统里打开';

  @override
  String get notifyTest => '发一条测试通知';

  @override
  String get notifyTestTitle => '测试通知';

  @override
  String get notifyTestBody => '能看到这条，说明通知是通的';

  @override
  String get notifyTestSent => '已发出，看通知栏';

  @override
  String get notifyTestFail => '发送失败';

  @override
  String get noRepliesHint => '说两句，让楼主知道有人看。';

  @override
  String get usernameOrEmail => '用户名或邮箱';

  @override
  String get changePassword => '修改密码';

  @override
  String get currentPassword => '原密码';

  @override
  String get confirmPassword => '再输一次新密码';

  @override
  String get passwordMismatch => '两次输入的新密码不一样';

  @override
  String get passwordChanged => '密码改好了，别的设备得重新登录';

  @override
  String get revokeOtherDevices => '退出其他设备';

  @override
  String get revokedOther => '已退出其他设备';

  @override
  String revokeFailed(String v1) {
    return '没退成：$v1';
  }

  @override
  String get currentPasswordRequired => '先填原密码';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get downloadsPage => '已下载';

  @override
  String get downloadsEmpty => '还没下载过文件';

  @override
  String downloadsCount(Object v1, Object v2) {
    return '$v1 个 · $v2';
  }

  @override
  String get showInFolder => '在文件夹中显示';

  @override
  String get deleteLocalFile => '删除本地文件';

  @override
  String get deleteLocalAsk => '删了手机上就没了，云盘里的还在。';

  @override
  String get localFileGone => '文件不在了';

  @override
  String get removeFromList => '从列表移除';

  @override
  String cantOpenThis(Object v1) {
    return '打不开这个文件：$v1';
  }

  @override
  String get downloadsByBrowser => '网页版的下载归浏览器管，这里列不出来。';

  @override
  String get clearMissingRecords => '清掉不在了的';

  @override
  String get followsHidden => '对方没有公开';

  @override
  String get showFollows => '公开关注和粉丝';

  @override
  String get showFollowsHint => '关掉后别人看不到你的关注和粉丝列表';

  @override
  String get selectMode => '选择';

  @override
  String get selectAll => '全选';

  @override
  String get selectNone => '全不选';

  @override
  String get deleteSelected => '删除所选';

  @override
  String selectedCount(int n) {
    return '已选 $n 个';
  }

  @override
  String deleteSelectedAsk(int n) {
    return '这 $n 个文件会从手机里删掉，云盘里的还在。';
  }

  @override
  String deletedSelected(int n) {
    return '已删 $n 个';
  }

  @override
  String get deleteTaskAsk => '删除这个下载任务吗？';

  @override
  String deleteTasksAskN(int n) {
    return '删除这 $n 个下载任务吗？';
  }

  @override
  String get alsoDeleteFile => '同时删除已下载的文件';

  @override
  String clearedFromList(int n) {
    return '已清 $n 条';
  }

  @override
  String get uiConfigTitle => '界面参数';

  @override
  String get uiConfigHint =>
      '这里改的是卡片高度、边距、字号这类纯视觉的数字，保存后客户端下次拉取就换过来，不用重新发包。\n\n格式是一个 JSON 对象，键名固定（见下方清单），值只接受数字或在允许范围内的取值。键名不认识、数值超范围都会被拒绝，并告诉你是哪一条。留空保存等于全部恢复默认。';

  @override
  String get uiConfigKeys =>
      '可用键：fileCard.height（卡片高度，24~240）、fileCard.maxWidth（宽屏上限，120~2000）、fileCard.compactWidth（私信里的宽度）、fileCard.padV（上下留白）、fileCard.padH（左右留白）、fileCard.radius（圆角）、fileCard.icon（图标大小）、fileCard.nameSize（文件名字号）、fileCard.sizeSize（大小文字字号）、fileCard.gap（图标与文字间距）、fileCard.arrowIcon（右侧图标大小）、threadCard.avatarRadius（头像半径）、threadCard.gap（头像与名字间距）、threadCard.tagSide（角标位置：leftOfTime / rightOfTime / belowTime）。';

  @override
  String get uiConfigSave => '保存';

  @override
  String get uiConfigSaved => '已保存，返回上一页就能看到';

  @override
  String get uiConfigBadJson => '不是合法的 JSON 对象';

  @override
  String get uiConfigDefaults => '填回默认值';

  @override
  String uiConfigRejected(int count, String lines) {
    return '有 $count 条被拒绝：\n$lines';
  }

  @override
  String get today => '今天';

  @override
  String get dmRecall => '撤回';

  @override
  String get dmRecalledMine => '你撤回了一条消息';

  @override
  String get dmRecalledPeer => '对方撤回了一条消息';

  @override
  String get dmRead => '已读';

  @override
  String get saveToCloud => '添加到云盘';

  @override
  String get alreadyInCloud => '该文件已在云盘中';

  @override
  String get addedToCloud => '已添加到云盘';

  @override
  String get dmMulti => '多选';

  @override
  String get dmSearchHint => '搜索聊天记录';

  @override
  String get dmSearchEmpty => '没有匹配的消息';

  @override
  String dmNewBelow(int n) {
    return '$n 条新消息';
  }

  @override
  String dmSelectCount(int n) {
    return '已选 $n 条';
  }

  @override
  String get dmEmoji => '表情';

  @override
  String get saved => '已保存';

  @override
  String get accentIsIdentity => '这个颜色也是你的颜色——私信气泡、头像外圈、楼层都跟着它，别人看得到。';

  @override
  String get undo => '撤销';

  @override
  String get select => '选择';

  @override
  String selectedN(String v1) {
    return '已选 $v1 个';
  }

  @override
  String deleteTheseN(String v1) {
    return '删掉这 $v1 个？';
  }

  @override
  String movedToTrashN(String v1) {
    return '$v1 个已移入回收站';
  }

  @override
  String cloudNoRoom(String v1) {
    return '空间不够了，还剩 $v1';
  }

  @override
  String uploadQueuedN(String v1) {
    return '上传 ·$v1';
  }

  @override
  String moreQueuedN(String v1) {
    return '还有 $v1 个在排队';
  }

  @override
  String get waitingTurn => '排队中';

  @override
  String newRepliesN(String v1) {
    return '有 $v1 条新回复';
  }

  @override
  String get newMessagesBelow => '以下是新消息';

  @override
  String get endpointHint => '两个地址是同一个站。主入口连不上时会自己走备用那条。';

  @override
  String get handleHint => '别人用 @ 找到你；小写字母、数字、下划线，3–16 位';

  @override
  String get profileSavedHint => '改完立刻生效，回主页刷新就能看到。';

  @override
  String get bindEmailWhy => '绑了之后，忘记密码不用找人：登录页点「忘记密码」，收个验证码就能改。';

  @override
  String get newPasswordOnce => '关掉就看不到了。让本人登录后马上改成自己记得的。';

  @override
  String creditsAdminOnly(String v1) {
    return '这份名单只有管理员能改（当前登录：$v1）。';
  }

  @override
  String get permOptionalNote => '不想开的可以一直关着，只是发图时得手动去系统里选。';

  @override
  String get siteAddHint => '填对方给的地址，带不带 http:// 都行';

  @override
  String get siteImportPasteHint => '把 bbs.json 的内容贴进来，一个文件可以有多座站';

  @override
  String get notifyImage => '[图片]';

  @override
  String get transfers => '传输';

  @override
  String get uploadsTab => '上传';

  @override
  String get downloadsTab => '已下载';

  @override
  String get trashFilesTab => '云盘文件';

  @override
  String get trashThreadsTab => '帖子';

  @override
  String get trashEmptyFiles => '回收站里没有文件';

  @override
  String get trashEmptyThreads => '回收站里没有帖子';

  @override
  String get trashKeptHint => '删掉的东西先在这儿放几天，过期才真清。';

  @override
  String get trashThreadHint => '帖子删了也会在这儿留几天，想找回来还来得及。';

  @override
  String get threadBack => '帖子回来了';

  @override
  String get threadPurgeHint => '帖子里的回复、点赞、通知在删的时候就清了，彻底删掉就只剩这一下。';

  @override
  String get restored => '已恢复';

  @override
  String get adminTrash => '管理员回收站';

  @override
  String get adminTrashEmpty => '还没有管理员删掉的东西';

  @override
  String get adminTrashHint => '管理员删掉的帖子和文件，原主人那边看不到，只有这儿能捞回来。';

  @override
  String get allOwners => '全部用户';

  @override
  String get allKinds => '全部类型';

  @override
  String get filter => '筛选';

  @override
  String get uploadsEmpty => '没有在上传的文件';

  @override
  String get uploadsEmptyHint => '选好文件点上传，进度都在这儿看。';

  @override
  String uploadsRunningN(Object v1) {
    return '正在传 v1 个';
  }

  @override
  String uploadsFailedN(Object v1) {
    return 'v1 个没传上去';
  }

  @override
  String uploadsDoneN(Object v1) {
    return '已传完 v1 个';
  }

  @override
  String get clearFinished => '清空已完成';

  @override
  String get uploading => '排队中';

  @override
  String get uploadFailed => '没传上去';

  @override
  String get uploadedOk => '已传完';

  @override
  String get showMangaTab => '显示漫画栏';

  @override
  String get showMangaTabHint => '关掉以后底栏只剩首页、消息、我的';

  @override
  String get bookSources => '外部书源';

  @override
  String get bookSourcesImport => '导入';

  @override
  String get bookSourcesEmpty => '还没导入书源。找一份「阅读」格式的书源 JSON，点导入。';

  @override
  String get bookSourcesBadFile => '这个文件里没读出书源';

  @override
  String get bookSourcesRemove => '删掉这个书源？';

  @override
  String get bookSourcesRemoved => '删了';

  @override
  String bookSourcesImported(int added, int updated, int skipped) {
    return '新增 $added，更新 $updated，跳过 $skipped';
  }
}
