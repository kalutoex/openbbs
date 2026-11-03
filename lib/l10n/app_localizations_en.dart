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
  String get forums => 'Forums';

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
}
