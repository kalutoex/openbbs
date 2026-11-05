// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get retry => 'Retry';

  @override
  String get copy => 'Copy';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get confirm => 'Confirm';

  @override
  String get send => 'Send';

  @override
  String get submit => 'Submit';

  @override
  String get back => 'Back';

  @override
  String get search => 'Search';

  @override
  String get refresh => 'Refresh';

  @override
  String get share => 'Share';

  @override
  String get report => 'Report';

  @override
  String get more => 'More';

  @override
  String get loading => 'Loading…';

  @override
  String get emptyList => 'Nothing here yet';

  @override
  String get noMore => 'No more';

  @override
  String get networkError => 'Network trouble, try again later';

  @override
  String get unknownError => 'Something went wrong';

  @override
  String get retryLater => 'Try again later';

  @override
  String get login => 'Log in';

  @override
  String get logout => 'Log out';

  @override
  String get register => 'Sign up';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get email => 'Email';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get settings => 'Settings';

  @override
  String get about => 'About';

  @override
  String get accounts => 'Accounts';

  @override
  String get friends => 'Friends';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get accentColor => 'Accent color';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get home => 'Home';

  @override
  String get notice => 'Notifications';

  @override
  String get me => 'Me';

  @override
  String get newThread => 'New post';

  @override
  String get title => 'Title';

  @override
  String get body => 'Body';

  @override
  String get publish => 'Publish';

  @override
  String get reply => 'Reply';

  @override
  String get addImage => 'Add image';

  @override
  String get confirmDelete => 'This can\'t be undone. Sure?';

  @override
  String get confirmLogout => 'Log out now?';

  @override
  String get unsavedChanges => 'You have unsaved changes. Leave anyway?';

  @override
  String get errNotConfigured => 'Server address is not set yet';

  @override
  String get errUploadNoUrl => 'Upload returned no path';

  @override
  String errUploadFailed(String reason) {
    return 'Upload failed: $reason';
  }

  @override
  String errBadResponse(int status) {
    return 'Unreadable response from server ($status)';
  }

  @override
  String errRequestFailed(int status) {
    return 'Request failed ($status)';
  }

  @override
  String errDownloadFailed(int status) {
    return 'Download failed ($status)';
  }

  @override
  String get needLogin => 'Log in first';

  @override
  String get forgetIt => 'Never mind';

  @override
  String get follow => 'Follow';

  @override
  String connectFailed(String v1) {
    return 'Can\'t reach the server: $v1';
  }

  @override
  String get myFavorites => 'My favorites';

  @override
  String get browseHistory => 'History';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get menu => 'Menu';

  @override
  String get densityNormal => 'Standard';

  @override
  String get timeline => 'Timeline';

  @override
  String get deleteIt => 'Delete';

  @override
  String get postDeleted => 'Post deleted';

  @override
  String get emailAndCodeRequired => 'Fill in both email and code';

  @override
  String maxImages(String v1) {
    return 'Up to $v1 images';
  }

  @override
  String get imageStillTooBig =>
      'An image was still too big after compression, skipped';

  @override
  String get addImageShort => 'Add image';

  @override
  String get accept => 'Accept';

  @override
  String get wontDo => 'Won\'t do';

  @override
  String get endOfList => 'That\'s all';

  @override
  String get following => 'Following';

  @override
  String get sortUpdated => 'Latest reply';

  @override
  String get sortCreated => 'Latest post';

  @override
  String get connectFailedPlain => 'Can\'t reach the server';

  @override
  String get server => 'Server';

  @override
  String get checkUpdate => 'Check for updates';

  @override
  String uploadFailedWith(String v1) {
    return 'Upload failed: $v1';
  }

  @override
  String get album => 'Album';

  @override
  String get allowed => 'Allowed';

  @override
  String get accountManagement => 'Account management';

  @override
  String get featureRequests => 'Feature requests';

  @override
  String get tapToRetry => 'Tap to retry';

  @override
  String saveFailed(String v1) {
    return 'Couldn\'t save: $v1';
  }

  @override
  String get deleteThreadConfirm =>
      'The post and all its replies disappear. This can\'t be undone.';

  @override
  String get pinned => 'Pinned';

  @override
  String get fillEmailFirst => 'Enter your email first';

  @override
  String get accountSecurity => 'Account security';

  @override
  String get code => 'Code';

  @override
  String get remove => 'Remove';

  @override
  String get ignore => 'Ignore';

  @override
  String get loadMore => 'Load more';

  @override
  String get post => 'Post';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get newPassword => 'New password';

  @override
  String albumFailed(String v1) {
    return 'Can\'t open the album: $v1';
  }

  @override
  String readImageFailed(String v1) {
    return 'Couldn\'t read the image: $v1';
  }

  @override
  String get publishing => 'Publishing…';

  @override
  String get clear => 'Clear';

  @override
  String get saving => 'Saving…';

  @override
  String get editPost => 'Edit post';

  @override
  String get clearAll => 'Clear all';

  @override
  String get tryAgain => 'Try again';

  @override
  String get addPeople => 'Add';

  @override
  String get takeDown => 'Take down';

  @override
  String get permissions => 'Permissions';

  @override
  String get auto => 'Auto';

  @override
  String get manual => 'Manual';

  @override
  String get fontSize => 'Font size';

  @override
  String get listDensity => 'List density';

  @override
  String get feedSort => 'Feed order';

  @override
  String get startTab => 'Start tab';

  @override
  String get sizeSmall => 'Small';

  @override
  String get sizeHuge => 'Extra large';

  @override
  String get sizeLarge => 'Large';

  @override
  String get densityCompact => 'Compact';

  @override
  String get densityLoose => 'Loose';

  @override
  String get chinese => '中文';

  @override
  String get updateChannel => 'Update channel';

  @override
  String get clearCache => 'Clear cache';

  @override
  String get jumpToFloor => 'Jump to floor';

  @override
  String get changed => 'Saved';

  @override
  String get deletePostConfirm => 'Delete this post?';

  @override
  String get edited => 'Edited';

  @override
  String get hueRed => 'Red';

  @override
  String get hueOrangeRed => 'Orange red';

  @override
  String get hueOrange => 'Orange';

  @override
  String get hueAmber => 'Amber';

  @override
  String get hueYellow => 'Yellow';

  @override
  String get hueLime => 'Lime';

  @override
  String get hueGrass => 'Grass';

  @override
  String get hueGreen => 'Green';

  @override
  String get hueTeal => 'Teal';

  @override
  String get hueCyan => 'Cyan';

  @override
  String get hueAzure => 'Azure';

  @override
  String get hueBlue => 'Blue';

  @override
  String get hueIndigo => 'Indigo';

  @override
  String get hueViolet => 'Violet';

  @override
  String get huePurple => 'Purple';

  @override
  String get hueMagenta => 'Magenta';

  @override
  String get huePink => 'Pink';

  @override
  String get huePinkLight => 'Light pink';

  @override
  String get permNotificationWhy =>
      'Pings you when someone replies to or likes your post';

  @override
  String get permPhotosWhy =>
      'Pick images from your album when posting or replying';

  @override
  String get permDeniedForever => 'Denied · turn it on in system settings';

  @override
  String get permRestricted => 'Restricted by the system';

  @override
  String get permAsk => 'Not allowed · tap to ask';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(String v1) {
    return '$v1 min ago';
  }

  @override
  String get yesterday => 'yesterday';

  @override
  String bigNumSuffix(String v1) {
    return '${v1}k';
  }

  @override
  String get am => 'AM';

  @override
  String get pm => 'PM';

  @override
  String postTimeFmt(
    String v1,
    String v2,
    String v3,
    String v4,
    String v5,
    String v6,
  ) {
    return '$v2/$v3/$v1, $v4:$v5 $v6';
  }

  @override
  String get threadSpacing => 'Spacing between posts';

  @override
  String get browseSection => 'Browsing';

  @override
  String get startTabHint => 'Which tab opens first';

  @override
  String get showThumbnails => 'Show thumbnails';

  @override
  String get showThumbnailsHint =>
      'Off means text only in the feed, saves data';

  @override
  String get autoCheckNotice => 'Poll for notifications';

  @override
  String get autoCheckNoticeHint => 'Asks for the unread count once a minute';

  @override
  String get networkSection => 'Network';

  @override
  String get contentSection => 'Content';

  @override
  String get clearSearchHistory => 'Clear search history';

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get permSubtitle => 'Notifications, photos';

  @override
  String get currentAccount => 'Current account';

  @override
  String get noEmailBoundHint =>
      'No email bound yet — a forgotten password means asking an admin';

  @override
  String get webAccessSection => 'Web access';

  @override
  String aboutBrand(String v1) {
    return 'About $v1';
  }

  @override
  String get aboutSubtitle => 'Source, changelog, licenses';

  @override
  String get logoutShort => 'Log out';

  @override
  String get version => 'Version';

  @override
  String get tapToCheckUpdate => 'Tap to check for updates';

  @override
  String get betaChannelHint => 'Beta — only pushed to you';

  @override
  String get stableChannelHint => 'Stable — what everyone runs';

  @override
  String get stableOption => 'Stable　verified';

  @override
  String get betaOption => 'Beta　pushed on every change';

  @override
  String betaVersion(String v1) {
    return 'Beta $v1';
  }

  @override
  String newVersion(String v1) {
    return 'New version $v1';
  }

  @override
  String installOverwrite(String v1) {
    return '$v1, installs over the current version. Login and settings stay.';
  }

  @override
  String get later => 'Later';

  @override
  String get downloadAndInstall => 'Download and install';

  @override
  String get mustUpdate =>
      'This build is too old. Update first to keep using the app.';

  @override
  String get downloading => 'Downloading';

  @override
  String get handedToSystem => 'Handed to the system';

  @override
  String get handedToInstaller =>
      'Handed to the system installer — if nothing happens, allow unknown installs in settings';

  @override
  String downloadFailedWith(String v1) {
    return 'Download failed: $v1';
  }

  @override
  String get primaryEndpoint => 'Primary address';

  @override
  String get backupEndpoint => 'Backup address';

  @override
  String get addressCopied => 'Address copied';

  @override
  String get clearing => 'Clearing…';

  @override
  String get calculating => 'Calculating…';

  @override
  String get cacheEmpty => 'Nothing cached yet';

  @override
  String cacheSize(String v1) {
    return 'Takes $v1';
  }

  @override
  String get cleared => 'Cleared';

  @override
  String clearedAmount(String v1) {
    return 'Cleared $v1';
  }

  @override
  String newerThanServer(String v1, String v2, String v3) {
    return 'You\'re on build $v1, newer than $v2 build $v3. The same signature can\'t install a lower build number over it — uninstall first to go back.';
  }

  @override
  String upToDate(String v1) {
    return 'Already the latest ($v1)';
  }

  @override
  String accountLine(String v1, String v2) {
    return '$v1 · $v2 accounts on this device';
  }

  @override
  String get betaShort => 'beta';

  @override
  String get stableShort => 'stable';

  @override
  String releaseNotes(String v1, String v2) {
    return '$v1\n\n$v2, installs over the current version. Login and settings stay.';
  }

  @override
  String get clearCacheConfirm =>
      'Image and API caches get deleted and re-downloaded next time. Login and settings stay.';

  @override
  String get floorJumpHint => 'Floor number, e.g. 128';

  @override
  String get jump => 'Go';

  @override
  String notReachedFloor(String v1) {
    return 'Not there yet — only at floor $v1';
  }

  @override
  String noSuchFloor(String v1) {
    return 'No floor $v1';
  }

  @override
  String get offlineCached => 'No network — showing what was cached last time';

  @override
  String get pinnedToast => 'Pinned';

  @override
  String get unpinnedToast => 'Unpinned';

  @override
  String get featuredToast => 'Featured';

  @override
  String get unfeaturedToast => 'Unfeatured';

  @override
  String get reportReason => 'Report reason';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Personal attack';

  @override
  String get reportIllegal => 'Illegal content';

  @override
  String get reportFalse => 'False information';

  @override
  String get reportOther => 'Other';

  @override
  String get reportDuplicate => 'Already reported once';

  @override
  String get reportThanks => 'Got it, we\'ll take a look';

  @override
  String get editFloor => 'Edit this floor';

  @override
  String get saySomething => 'Say something…';

  @override
  String get replaceWithPlaceholder => 'Replace with a placeholder?';

  @override
  String get replacePlaceholderConfirm =>
      'Every image in this post and its replies becomes the same placeholder. The originals are gone.';

  @override
  String replacedImages(String v1) {
    return 'Replaced $v1 images';
  }

  @override
  String get deleteFloorConfirm => 'Delete this floor?';

  @override
  String get deleteThreadBody =>
      'The post and all its replies go with it. Can\'t be undone.';

  @override
  String get deleteFloorBody => 'This floor and the replies under it go too.';

  @override
  String get deleteReplyConfirm => 'Delete this reply?';

  @override
  String get cannotUndo => 'Can\'t be undone.';

  @override
  String get onlyAuthorOn => 'Author only';

  @override
  String get onlyAuthorOff => 'Only the author';

  @override
  String jumpToFloorPages(String v1) {
    return 'Jump to floor ($v1 pages)';
  }

  @override
  String get unpin => 'Unpin';

  @override
  String get unfeature => 'Unfeature';

  @override
  String get feature => 'Feature';

  @override
  String get replaceAllImages => 'Replace all images';

  @override
  String get deletePost => 'Delete post';

  @override
  String viewsCount(String v1) {
    return '$v1 views';
  }

  @override
  String get related => 'Related';

  @override
  String repliesCount(String v1) {
    return '$v1 replies';
  }

  @override
  String get noReplies => 'No replies yet';

  @override
  String get favorited => 'Saved';

  @override
  String get unfavorite => 'Remove from saved';

  @override
  String get meShort => 'Me';

  @override
  String replyTo(String v1) {
    return 'Reply to $v1';
  }

  @override
  String get replyHint => 'Write your reply';

  @override
  String get maxNineImages => 'Up to 9 images';

  @override
  String get opAuthor => 'OP';

  @override
  String get copyFullText => 'Copy all';

  @override
  String get copied => 'Copied';

  @override
  String get collapse => 'Collapse';

  @override
  String expandAllReplies(String v1) {
    return 'Show all $v1 replies';
  }

  @override
  String get resumeDraft => 'Continue your draft';

  @override
  String resumeDraftImages(String v1) {
    return 'Continue your draft, with $v1 images';
  }

  @override
  String get discardDraft => 'Discard';

  @override
  String get pickFromAlbum => 'From album';

  @override
  String canAddMore(String v1) {
    return 'Room for $v1 more';
  }

  @override
  String get takePhoto => 'Take a photo';

  @override
  String cameraFailed(String v1) {
    return 'Can\'t open the camera: $v1';
  }

  @override
  String tooManyImages(String v1) {
    return 'Up to $v1 images — the rest were dropped';
  }

  @override
  String get deleteThisImage => 'Remove this image';

  @override
  String uploadingStart(String v1) {
    return 'Uploading images 0/$v1';
  }

  @override
  String uploadingImages(String v1, String v2) {
    return 'Uploading images $v1/$v2';
  }

  @override
  String postFailed(String v1) {
    return 'Couldn\'t post: $v1';
  }

  @override
  String get draftUnsaved => 'This post hasn\'t gone out';

  @override
  String get draftImagesNote =>
      'Images aren\'t kept in drafts — only the title and body';

  @override
  String get saveDraftAndLeave => 'Save draft and leave';

  @override
  String get discardPost => 'Throw this away';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get composeTitle => 'New post';

  @override
  String get composeHint => 'Say something… (@ to mention)';

  @override
  String imageCount(String v1, String v2) {
    return 'Images $v1/$v2';
  }

  @override
  String get dragToReorder => 'Press and drag to reorder';

  @override
  String titleRequiredMaxImages(String v1) {
    return 'Title required · up to $v1 images';
  }

  @override
  String imageCountPrefix(String v1, String v2, String v3) {
    return '$v1/$v2 images · $v3';
  }

  @override
  String bodyLength(String v1) {
    return '$v1 chars';
  }

  @override
  String restoreFailed(String v1) {
    return 'Restore failed: $v1';
  }

  @override
  String codeSendFailed(String v1) {
    return 'Couldn\'t send the code: $v1';
  }

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String passwordChangeFailed(String v1) {
    return 'Couldn\'t change it: $v1';
  }

  @override
  String get fillUserAndPassword => 'Both username and password are required';

  @override
  String loginFailed(String v1) {
    return 'Login failed: $v1';
  }

  @override
  String get resetTitle => 'Reset password';

  @override
  String get atLeast8 => 'At least 8 characters';

  @override
  String get emailUsedToRegister => 'The email you signed up with';

  @override
  String get emailForCode => 'We\'ll send the signup code here';

  @override
  String get sending => 'Sending';

  @override
  String get getCode => 'Get code';

  @override
  String get changePasswordAndLogin => 'Change password and log in';

  @override
  String get registerAndLogin => 'Sign up and log in';

  @override
  String get backToLogin => 'Back to login';

  @override
  String get haveAccountLogin => 'Have an account? Log in';

  @override
  String get noAccountRegister => 'No account? Sign up';

  @override
  String get forgotPasswordQuestion => 'Forgot your password?';

  @override
  String get accountCopied => 'Account copied';

  @override
  String get coverUpdated => 'Cover updated';

  @override
  String coverFailed(String v1) {
    return 'Couldn\'t change the cover: $v1';
  }

  @override
  String get saveCover => 'Save background';

  @override
  String get saveCoverConfirm => 'Save this background to your album?';

  @override
  String savedTo(String v1) {
    return 'Saved to $v1';
  }

  @override
  String get changeCover => 'Change cover';

  @override
  String get addCover => 'Add cover';

  @override
  String joinedAt(String v1) {
    return 'Joined $v1';
  }

  @override
  String get followingCount => 'Following';

  @override
  String get followers => 'Followers';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get noPostsYet => 'Nothing posted yet';

  @override
  String get noPostsHint => 'Be the first to post here';

  @override
  String get loadFailed => 'Couldn\'t load this';

  @override
  String get longAgo => 'A long time ago';

  @override
  String yearMonth(String v1, String v2) {
    return '$v1-$v2';
  }

  @override
  String get acceptConfirm => 'Accept this one?';

  @override
  String get rejectConfirm => 'Mark as won\'t do?';

  @override
  String get reopenConfirm => 'Send back to pending?';

  @override
  String get replyOptional => 'Reply (optional)';

  @override
  String get adminReplyHint => 'Scheduled / can\'t do it, because…';

  @override
  String get accepted => 'Accepted';

  @override
  String get markedWontDo => 'Marked as won\'t do';

  @override
  String get movedBack => 'Back to pending';

  @override
  String get requestsDone => 'Requests · handled';

  @override
  String requestsCount(String v1) {
    return 'Requests ($v1)';
  }

  @override
  String get requests => 'Requests';

  @override
  String get viewPending => 'View pending';

  @override
  String get viewDone => 'View handled';

  @override
  String get nothingHandled => 'Nothing handled yet';

  @override
  String get noPendingRequests => 'No pending requests';

  @override
  String replyLine(String v1) {
    return 'Reply: $v1';
  }

  @override
  String submittedBy(String v1) {
    return 'Submitted by $v1';
  }

  @override
  String get moveBack => 'Back to pending';

  @override
  String avatarUpdated(String v1) {
    return 'Avatar updated · $v1';
  }

  @override
  String get chooseFromAlbum => 'Choose from album';

  @override
  String get compressNote => 'Compressed to around 100 KB before upload';

  @override
  String get nicknameRequired => 'Nickname can\'t be empty';

  @override
  String get handleInvalid =>
      'Lowercase letters, digits and underscore only, 3–16 characters';

  @override
  String get editProfileTitle => 'Edit profile';

  @override
  String get nickname => 'Nickname';

  @override
  String get nicknameMax => 'Up to 20 characters';

  @override
  String get handle => 'Handle';

  @override
  String get bio => 'Bio';

  @override
  String get bioHint => 'Up to 80 characters, can be empty';

  @override
  String get openSource => 'Open source';

  @override
  String get thanksFriends => 'Thanks to my friends';

  @override
  String get thanksFriendsSub => 'Their accounts are here';

  @override
  String get thirdPartyLicenses => 'Third-party licenses';

  @override
  String get thirdPartyLicensesSub =>
      'License texts bundled with each dependency';

  @override
  String get gplLicense => 'GPL-3.0 license';

  @override
  String get gplLicenseSub => 'This project is released under GPL-3.0';

  @override
  String get links => 'Links';

  @override
  String get sourceCode => 'Source code';

  @override
  String get issues => 'Issues';

  @override
  String get issuesSub => 'Anything off? Note it here';

  @override
  String get cantOpenLink => 'Couldn\'t open that link';

  @override
  String get reportKeepNote => 'Nothing wrong here, close the report.';

  @override
  String get reportDeleteFloorNote =>
      'The floor\'s content gets deleted. Can\'t be undone.';

  @override
  String get reportDeletePostNote =>
      'The whole post and its replies get deleted. Can\'t be undone.';

  @override
  String get ignoreReportConfirm => 'Ignore this report?';

  @override
  String get deleteContentConfirm => 'Delete this content?';

  @override
  String get ignored => 'Ignored';

  @override
  String get deleted => 'Deleted';

  @override
  String reportsCount(String v1) {
    return 'Reports ($v1)';
  }

  @override
  String get noReports => 'No reports pending';

  @override
  String get floor => 'Floor';

  @override
  String reportLine(String v1, String v2) {
    return 'Reason: $v1　Reporter: $v2';
  }

  @override
  String galleryReadFailed(String v1) {
    return 'Couldn\'t read the album: $v1';
  }

  @override
  String albumOpenFailed(String v1) {
    return 'Couldn\'t open this album: $v1';
  }

  @override
  String maxSelectImages(String v1) {
    return 'Up to $v1 photos';
  }

  @override
  String get pickPhotos => 'Pick photos';

  @override
  String doneWithCount(String v1) {
    return 'Done ($v1)';
  }

  @override
  String get albumEmpty => 'No photos in this album';

  @override
  String get needsAlbumPermission =>
      'Album permission is needed to list photos';

  @override
  String get noAlbumUsePicker =>
      'No album on this machine — use the system file picker';

  @override
  String get localThumbsOnly =>
      'Picks from on-device thumbnails only, never uploads the whole album.';

  @override
  String get grantPermission => 'Grant permission';

  @override
  String get pickAnotherWay => 'Pick another way';

  @override
  String get titleClearer => 'Make the title clearer';

  @override
  String get requestDuplicate => 'This one is already filed';

  @override
  String get requestSubmitted => 'Submitted';

  @override
  String get requestIntro =>
      'Write down whatever feature you\'re thinking of. Admins read it, and reply when it\'s accepted.';

  @override
  String get requestTitleLabel => 'What you want, in one line';

  @override
  String get requestTitleHint =>
      'e.g. posts can be saved into separate folders';

  @override
  String get requestDetailLabel => 'Details (optional)';

  @override
  String get requestDetailHint => 'Why you need it, roughly how it\'d work';

  @override
  String get myRequests => 'My requests';

  @override
  String requestCount(String v1) {
    return '$v1';
  }

  @override
  String get noRequestsYet => 'None yet';

  @override
  String get statusPending => 'Pending';

  @override
  String get codeSentCheckEmail => 'Code sent — check your inbox';

  @override
  String get emailBound => 'Bound';

  @override
  String get noEmailWarning =>
      'This account has no email bound. If you forget your password, only an admin can reset it.';

  @override
  String get emailBoundHint => 'Bound — you can reset the password yourself';

  @override
  String get bindEmail => 'Bind email';

  @override
  String get changeEmail => 'Change email';

  @override
  String get sendCode => 'Send code';

  @override
  String get processing => 'Processing…';

  @override
  String get bind => 'Bind';

  @override
  String get rebind => 'Rebind';

  @override
  String get titleEmpty => 'Title can\'t be empty';

  @override
  String get bodyOrImageRequired => 'Keep at least a body or an image';

  @override
  String uploadingNewStart(String v1) {
    return 'Uploading new images 0/$v1';
  }

  @override
  String uploadingNewImages(String v1, String v2) {
    return 'Uploading new images $v1/$v2';
  }

  @override
  String get changesUnsaved => 'Changes not saved';

  @override
  String get continueEditing => 'Keep editing';

  @override
  String get leaveWithoutSaving => 'Leave without saving';

  @override
  String imageCountShort(String v1, String v2) {
    return 'Images $v1/$v2';
  }

  @override
  String get noImagesYet => 'No images yet';

  @override
  String noSearchResult(String v1) {
    return 'Nothing for “$v1”';
  }

  @override
  String searchResultCount(String v1) {
    return '$v1 found';
  }

  @override
  String get goLogin => 'Log in';

  @override
  String get noIntro => 'No description';

  @override
  String get nRepliedPost => 'replied to your post';

  @override
  String get nRepliedYou => 'replied to you';

  @override
  String get nLiked => 'liked your post';

  @override
  String get nMentioned => 'mentioned you in a post';

  @override
  String get nFeatured => 'featured your post';

  @override
  String get nDeleted => 'deleted your content';

  @override
  String get nNew => 'New activity';

  @override
  String get noticeLoginNeeded => 'Log in to get notifications';

  @override
  String get noticeLoginHint => 'Log in from “Me”';

  @override
  String get noNotifications => 'No notifications yet';

  @override
  String get noNotificationsHint => 'Replies and likes show up here';

  @override
  String get reset => 'Reset';

  @override
  String newPasswordFor(String v1) {
    return 'New password for “$v1”:';
  }

  @override
  String get copyAndClose => 'Copy and close';

  @override
  String get searchUsername => 'Search username';

  @override
  String get noEmail => 'No email';

  @override
  String get manualNeedsAddress => 'Enter the address manually';

  @override
  String serverOkUsing(String v1) {
    return 'Connected, using $v1';
  }

  @override
  String connectFailedBody(String v1) {
    return 'Can\'t connect: $v1';
  }

  @override
  String get ipv6FirstHint => 'Tries IPv6 first, falls back to IPv4';

  @override
  String get channelIpv6 => 'IPv6 channel';

  @override
  String get channelIpv4 => 'IPv4 channel';

  @override
  String get enterManually => 'Enter it yourself';

  @override
  String get serverAddress => 'Server address';

  @override
  String get saveAndTest => 'Save and test';

  @override
  String currentExit(String v1) {
    return 'Current endpoint: $v1';
  }

  @override
  String switchedTo(String v1) {
    return 'Switched to $v1';
  }

  @override
  String accountExpiredRemoved(String v1) {
    return '$v1\'s login expired and was removed';
  }

  @override
  String get removeAccount => 'Remove account';

  @override
  String removeAccountConfirm(String v1) {
    return 'Remove $v1 from this device? This only logs out here — the account and posts stay on the server.';
  }

  @override
  String accountAdded(String v1) {
    return 'Added $v1';
  }

  @override
  String get noAccounts => 'No accounts yet';

  @override
  String get addAccount => 'Add account';

  @override
  String get addAccountHint => 'Log in to another account, switch back anytime';

  @override
  String get friendSearchHint => 'Username / @handle / nickname';

  @override
  String get enterName => 'Type a name';

  @override
  String get add => 'Add';

  @override
  String removeFriendConfirm(String v1) {
    return 'Remove $v1?';
  }

  @override
  String get removeFriendBody => 'Just off this page — the account stays.';

  @override
  String get credits => 'Credits';

  @override
  String get nobodyYet => 'Nobody yet';

  @override
  String unfollowed(String v1) {
    return 'Unfollowed $v1';
  }

  @override
  String followedBack(String v1) {
    return 'Followed back $v1';
  }

  @override
  String get fans => 'Followers';

  @override
  String get notFollowingAnyone => 'Not following anyone';

  @override
  String get noFans => 'No followers';

  @override
  String get mutual => 'Mutual';

  @override
  String get followBack => 'Follow back';

  @override
  String get searchTitleOrBody => 'Search titles or text';

  @override
  String get searchPrompt => 'Type a keyword and press enter';

  @override
  String get recentSearches => 'Recent';

  @override
  String totalCount(String v1) {
    return '$v1 in total';
  }

  @override
  String endTotalCount(String v1) {
    return 'That\'s all — $v1 in total';
  }

  @override
  String get noFavoritesYet => 'Nothing saved yet';

  @override
  String get reportHandling => 'Reports';

  @override
  String get requestHandling => 'Requests';

  @override
  String get noHistoryYet => 'No history yet';

  @override
  String get enterBio => 'Enter your bio';

  @override
  String get tapToLogin => 'Tap to log in';

  @override
  String get general => 'General';

  @override
  String get featured => 'Featured';

  @override
  String get multiImage => 'Photos';

  @override
  String get comments => 'Comments';

  @override
  String get loginBenefits => 'Log in to post and reply';

  @override
  String get hot => 'Hot';

  @override
  String get permIntro =>
      'Network permission is granted at install — only notifications and photos need a yes here.';

  @override
  String get network => 'Network';

  @override
  String get networkGranted => 'Granted at install, nothing to do';

  @override
  String get downloadImage => 'Download this image';

  @override
  String get backToTop => 'Back to top';

  @override
  String get offlineCacheFeed =>
      'Can\'t reach the server — this is the last cached copy';

  @override
  String get fillAddress => 'Enter an address';

  @override
  String get fillServerAddress => 'Enter the server address';

  @override
  String get connect => 'Connect';

  @override
  String get themeColorTitle => 'Accent color';

  @override
  String get accentColorHint =>
      'Buttons, selections and input focus rings all follow this color band.';

  @override
  String get appIconTitle => 'App icon';

  @override
  String get appIconHint =>
      'The launcher icon is fixed when the app is built; these are the sets shipped with it. The home screen may take a few seconds to refresh.';

  @override
  String get appIconChanged => 'Done — check your home screen';

  @override
  String get appIconUnavailable => 'Not supported on this platform';

  @override
  String get moreToLoad => 'More to come';

  @override
  String resetPasswordConfirm(String v1) {
    return 'Set “$v1”\'s password to a random string?\n\nThe old one stops working at once. The new one is shown only once — send it to them.';
  }

  @override
  String siteNeedsUpdate(Object v1, Object v2) {
    return 'This site speaks API $v1, but this client only supports up to $v2. Update the app to keep using it.';
  }

  @override
  String get sitesManage => 'Sites';

  @override
  String get sitesManageHint =>
      'One app, many sites — unreachable ones are skipped';

  @override
  String get siteAdd => 'Add site';

  @override
  String get siteImportPaste => 'Paste a manifest';

  @override
  String get siteImportMaster => 'Fetch from the master site';

  @override
  String get importIt => 'Import';

  @override
  String siteImportFailed(String v1) {
    return 'Can\'t read the manifest: $v1';
  }

  @override
  String get siteImportEmpty => 'No sites in that manifest';

  @override
  String siteImportNone(String v1) {
    return 'Nothing to import: $v1';
  }

  @override
  String siteImported(String v1) {
    return 'Imported $v1 sites';
  }

  @override
  String siteImportedSkipped(String v1, String v2, String v3) {
    return 'Imported $v1 sites, skipped $v2: $v3';
  }

  @override
  String get skipNoUrl => 'no address';

  @override
  String get skipDuplicateId => 'duplicate id';

  @override
  String get skipApiTooNew => 'API too new';

  @override
  String get skipBadFormat => 'not a manifest';

  @override
  String get siteEmpty => 'No sites yet';

  @override
  String get siteEmptyHint =>
      'Add an address to start — accounts and posts live on that server.';

  @override
  String get siteLoginSite => 'Login site';

  @override
  String get siteCurrentNow => 'Current';

  @override
  String get siteUnreachable => 'unreachable';

  @override
  String get siteSetLogin => 'Set as login site';

  @override
  String get siteSwitch => 'Switch';

  @override
  String get siteProbe => 'Probe again';

  @override
  String siteRemoveConfirm(String v1) {
    return 'Remove $v1 from this device? The account and posts stay on the server.';
  }

  @override
  String siteLoginSet(String v1) {
    return 'Login site is now $v1';
  }

  @override
  String get sites => 'Sites';

  @override
  String get siteMaster => 'Main site';

  @override
  String get siteSmall => 'Sub site';

  @override
  String get sitePostTo => 'Post to';

  @override
  String get siteMasterFixed => 'The main site can\'t be removed';

  @override
  String get siteSpeedTest => 'Speed test';

  @override
  String get siteSpeedRunning => 'Testing…';

  @override
  String siteSpeedResult(String v1) {
    return 'Speed: $v1';
  }

  @override
  String get siteSpeedNone => 'All entries failed';

  @override
  String siteSwitching(String v1) {
    return 'Switching to $v1';
  }

  @override
  String get listSep => ', ';

  @override
  String get bannedTitle => 'Account banned';

  @override
  String get bannedBody =>
      'An admin banned this account, so posts won\'t go through. Use another account or ask the site owner why.';

  @override
  String get posts => 'Posts';

  @override
  String get siteBlock => 'Block';

  @override
  String get siteUnblock => 'Unblock';

  @override
  String get siteBlocked => 'Blocked';

  @override
  String get siteBlockedDone => 'Blocked - hidden from the site list';

  @override
  String get siteUnblockedDone => 'Unblocked';

  @override
  String get siteCatalogEmpty => 'No other sites yet';

  @override
  String get siteCatalogEmptyHint =>
      'Add one in Settings - Sites, or wait for the master site to list it.';

  @override
  String get siteNoPosts => 'No posts on this site yet';

  @override
  String get searchThreads => 'Posts';

  @override
  String get searchReplies => 'Replies';

  @override
  String get searchUsers => 'Users';

  @override
  String get dmTitle => 'Messages';

  @override
  String get dmEmpty => 'No messages yet';

  @override
  String get messagesTab => 'Messages';

  @override
  String get siteMessages => 'Notices';

  @override
  String get pinChat => 'Pin';

  @override
  String get unpinChat => 'Unpin';

  @override
  String get muteChat => 'Mute';

  @override
  String get unmuteChat => 'Unmute';

  @override
  String get markRead => 'Mark as read';

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get dmEmptyHint => 'Tap “Send message” on someone\'s profile';

  @override
  String get dmEarlier => 'Load earlier';

  @override
  String get dmSend => 'Message';

  @override
  String get pickFromDevice => 'From device';

  @override
  String get pickFromCloud => 'From cloud drive';

  @override
  String get cloudPickEmpty => 'Nothing in the cloud drive yet';

  @override
  String cloudPickDone(String v1) {
    return 'Done ($v1)';
  }

  @override
  String get attachFile => 'Attach file';

  @override
  String attachMax(String v1) {
    return 'Up to $v1 files';
  }

  @override
  String attachTooBig(String v1) {
    return 'File must be under $v1';
  }

  @override
  String attachUploading(String v1) {
    return 'Uploading $v1';
  }

  @override
  String get pasteCredential => 'Paste login credential';

  @override
  String get copyCredential => 'Copy login credential';

  @override
  String get copyCredentialHint =>
      'After a reinstall or a new device, paste it on the login page to restore';

  @override
  String get credentialCopied => 'Credential copied';

  @override
  String get credentialHint =>
      'Copy it on the old device under Settings → Copy login credential';

  @override
  String get restore => 'Restore';

  @override
  String get credentialInvalid => 'Credential is invalid or expired';

  @override
  String get restoreWithCredential => 'Restore with a login credential';

  @override
  String myFollowedForums(String v1) {
    return 'Following ($v1)';
  }

  @override
  String allForums(String v1) {
    return 'All ($v1)';
  }

  @override
  String forumStats(String v1, String v2) {
    return '$v1 posts · $v2 followers';
  }

  @override
  String get addFromDevice => 'Bring an account from another device';

  @override
  String get cloudDisk => 'Cloud';

  @override
  String get recycleBin => 'Trash';

  @override
  String get deleteThisFile => 'Delete this file?';

  @override
  String fileUsedByPosts(String v1) {
    return '$v1 posts use this file. Those places will show \"file unavailable\" after you delete it.';
  }

  @override
  String get goesToTrashHint =>
      'The file goes to Trash and can be restored within 7 days. Space is freed right away.';

  @override
  String get movedToTrash => 'Moved to Trash';

  @override
  String get notConnectedTapRetry => 'Not connected. Tap to retry';

  @override
  String get nothingUploadedYet => 'Nothing uploaded yet';

  @override
  String get notFound => 'Not found';

  @override
  String get findFile => 'Find a file';

  @override
  String get bySize => 'By size';

  @override
  String get byTime => 'By time';

  @override
  String usedByPosts(String v1) {
    return 'Used by $v1 posts';
  }

  @override
  String fileCount2(String v1) {
    return '$v1 files';
  }

  @override
  String usedSpace(String v1) {
    return 'Used $v1';
  }

  @override
  String usedOfTotal(String v1, String v2) {
    return '$v1 / $v2';
  }

  @override
  String daysLeft(String v1) {
    return '$v1 days left';
  }

  @override
  String hoursLeft(String v1) {
    return '$v1 hours left';
  }

  @override
  String get expiringSoon => 'About to be cleared';

  @override
  String get emptyHere => 'Empty';

  @override
  String get download => 'Download';

  @override
  String get upload => 'Upload';

  @override
  String uploadingFile2(String v1) {
    return 'Uploading $v1';
  }

  @override
  String get uploadedDone => 'Uploaded';

  @override
  String get fileTooBigHint => 'Keep each file under 500MB';

  @override
  String cloudRefsWarn(String v1) {
    return 'Used by $v1 posts. Deleting it makes those places show that the file is gone.';
  }

  @override
  String get restoredDone => 'Restored';

  @override
  String get cloudUsage => 'Cloud storage';

  @override
  String get changeQuota => 'Change quota';

  @override
  String get quotaMbHint => 'Quota in MB (empty = site default)';

  @override
  String get quotaSaved => 'Quota updated';

  @override
  String get cloudQuotaDefault => 'site default';

  @override
  String get cloudSection => 'Cloud';

  @override
  String get cloudSettings => 'Cloud settings';

  @override
  String get cloudSettingsHint => 'Where downloads go, what happens after';

  @override
  String get cloudSettingsIntro =>
      'Files from the cloud drive and posts are saved to the location below. Change it here.';

  @override
  String get downloadLocation => 'Download location';

  @override
  String get downloadLocationDefault => 'Untouched — using Download/OpenBBS';

  @override
  String get downloadLocationReset => 'Back to default location';

  @override
  String get downloadLocationDefaultHint => 'Returns to Download/OpenBBS';

  @override
  String get downloadDirReset => 'Back to the default location';

  @override
  String get downloadAutoOpen => 'Open when done';

  @override
  String get downloadAutoOpenHint =>
      'Off means it is only saved — open it from your files app';

  @override
  String get downloadCache => 'Download leftovers';

  @override
  String downloadCacheUsed(String v1) {
    return 'Partial downloads, $v1';
  }

  @override
  String get downloadCacheEmpty => 'Nothing left over';

  @override
  String get cacheCleared => 'Cleared';

  @override
  String get downloadByBrowser =>
      'On the web build the browser decides where downloads go — change it in the browser settings.';

  @override
  String get deleteForever => 'Delete permanently';

  @override
  String get deleteForeverHint =>
      'This cannot be undone. It will not stay in Trash either.';

  @override
  String get deletedForever => 'Deleted permanently';

  @override
  String get downloadedBadge => 'Downloaded';

  @override
  String get downloadingShort => 'Downloading';

  @override
  String get browseFiles => 'Files on this phone';

  @override
  String get browseFilesHint => 'Browse the phone and upload what you pick';

  @override
  String get pickFromSystem => 'System picker';

  @override
  String get allFilesAccess => 'Access all files';

  @override
  String get allFilesWhy =>
      'Browsing the whole phone needs this permission. It is only used to read the files you pick.';

  @override
  String get allFilesOpen => 'Open settings';

  @override
  String get allFilesDenied => 'No access, cannot browse storage';

  @override
  String get allFilesRetry => 'Granted, try again';

  @override
  String get searchThisFolder => 'Search in this folder';

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get noAccessFolder => 'Cannot open, blocked by the system';

  @override
  String pickedCount(String v1) {
    return '$v1 selected';
  }

  @override
  String uploadPicked(String v1) {
    return 'Upload $v1';
  }

  @override
  String uploadingIndexOf(String v1, String v2, String v3) {
    return 'Uploading $v1/$v2: $v3';
  }

  @override
  String uploadSomeFailed(String v1, String v2) {
    return '$v1 uploaded, $v2 failed';
  }

  @override
  String get storageRoot => 'Storage';

  @override
  String get systemFolderHidden => 'System folder (contents hidden)';

  @override
  String get dmWaitReply => 'You can send again once they reply';

  @override
  String get dmNewMessages => 'New messages';

  @override
  String get dmTapToProfile => 'Tap for profile';

  @override
  String get dmNoChat => 'No messages yet — say hi';

  @override
  String get quote => 'Quote';

  @override
  String get replyImage => '[image]';

  @override
  String get dmPickImage => 'Photos';

  @override
  String get dmPickFile => 'File';

  @override
  String get dmAttach => 'Send';

  @override
  String get notifyNewDm => 'New message';

  @override
  String notifyNewCount(int n) {
    return '$n new messages';
  }

  @override
  String get sysNotify => 'Message alerts';

  @override
  String get sysNotifyHint =>
      'Show a system notification when a message arrives';

  @override
  String get sysNotifyOff => 'Notifications are blocked in system settings';

  @override
  String get noRepliesHint => 'Be the first to say something.';

  @override
  String get usernameOrEmail => 'Username or email';

  @override
  String get changePassword => 'Change password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get confirmPassword => 'Repeat new password';

  @override
  String get passwordMismatch => 'The new passwords don\'t match';

  @override
  String get passwordChanged =>
      'Password changed. Other devices are signed out.';

  @override
  String get revokeOtherDevices => 'Sign out other devices';

  @override
  String get revokedOther => 'Other devices signed out';

  @override
  String revokeFailed(String v1) {
    return 'Couldn\'t sign out: $v1';
  }

  @override
  String get currentPasswordRequired => 'Enter your current password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';
}
