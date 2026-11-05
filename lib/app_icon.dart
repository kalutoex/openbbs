import 'app_icon_io.dart'
    if (dart.library.js_interop) 'app_icon_web.dart' as impl;

/// 一套可选图标。
class AppIconOption {
  const AppIconOption(this.key, this.label);

  /// 跟 AndroidManifest.xml 里的 Icon* 别名、assets/icons 的文件名一致。
  final String key;

  /// 设置页上显示的名字。
  final String label;
}

/// 顺序无所谓，但每个 key 都必须在清单里有一条 activity-alias。
/// 加图标：tool/gen_app_icons.py 的 COLORS、清单的 alias、这里的列表，三处一起改。
const appIconOptions = <AppIconOption>[
  AppIconOption('mint', '薄荷'),
  AppIconOption('blue', '蓝'),
  AppIconOption('purple', '紫'),
  AppIconOption('pink', '粉'),
  AppIconOption('coral', '珊瑚'),
  AppIconOption('red', '红'),
  AppIconOption('lime', '青柠'),
  AppIconOption('steel', '灰'),
];

/// 设置页里画预览用的图，8 套都打进包里。
String appIconAsset(String key) => 'assets/icons/icon_$key.png';

/// 桌面图标和名字是编译期写死在清单里的，运行时改不了，
/// 安卓侧预先声明了 8 个别名，这里做的只是切换启用哪一个。
/// 换完桌面不会立刻变，启动器刷新要几秒，有的还得重启桌面。
bool get canChangeAppIcon => impl.supported;

Future<String> currentAppIcon() => impl.currentAppIcon();

Future<void> setAppIcon(String key) => impl.setAppIcon(key);
