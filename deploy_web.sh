#!/bin/bash
# 构建 Flutter Web 并部署到线上论坛的 web 目录。
#
#   ./deploy_web.sh
#
# 构建完有三件事必须做，漏了线上就会出问题：
#   1. canvaskit 里 skwasm/wimp/symbols 是别的渲染器和调试符号，浏览器不请求，
#      每次构建都会重新生成，部署后要删掉（19MB → 9.8MB）。
#   2. flutter_service_worker.js 必须换成自毁版，否则老用户被旧缓存钉住。
#   3. 顺手验一下首页和接口，别让坏版本上去。
set -e
APP=/vol1/1000/data/code/ongoing/openbbs
WEB=/vol1/1000/data/code/ongoing/bbs/server/web
BASE=${1:-https://127.0.0.1:26016}

cd "$APP"
# shellcheck disable=SC1091
source /vol1/1000/data/code/.fenv
# --no-pub：依赖在这里解析不了（镜像缺包体），pub get 单独跑完再来。
# shellcheck disable=SC2086
flutter build web --release --base-href / --no-web-resources-cdn --pwa-strategy=none --no-pub

# 留一份上一版的 main.dart.js。新版上去白屏或接口对不上时，回滚就三步：
#   cp main.dart.js.prev main.dart.js && gzip -9 -f main.dart.js && 刷新
if [ -f "$WEB/main.dart.js" ]; then
  cp -f "$WEB/main.dart.js" "$WEB/main.dart.js.prev"
fi

cp -r build/web/. "$WEB"/

rm -f "$WEB"/canvaskit/skwasm*.js "$WEB"/canvaskit/skwasm*.wasm \
      "$WEB"/canvaskit/wimp*.js "$WEB"/canvaskit/wimp*.wasm \
      "$WEB"/canvaskit/*.symbols

# 字体文件名固定（MaterialIcons-Regular.otf），内容却每版都变。浏览器按名字缓存，
# 名字不变就一年不来问，新代码用到的图标在老字体里没有字形，页面上是白块一块——
# 「web 端有几个图标刷不出来」就是它。把内容指纹塞进文件名，URL 一变旧缓存自然失效。
# FontManifest.json 指向改名后的文件，它本身走 no-cache（见 server/app/main.py）。
python3 - "$WEB" <<'PY'
import hashlib, json, os, re, sys

web = sys.argv[1]
manp = os.path.join(web, 'assets', 'FontManifest.json')
if os.path.isfile(manp):
    man = json.load(open(manp, encoding='utf-8'))
    keep = set()
    for fam in man:
        for f in fam.get('fonts', []):
            rel = f.get('asset') or ''
            src = os.path.join(web, 'assets', rel)
            if not os.path.isfile(src):
                continue
            h = hashlib.sha256(open(src, 'rb').read()).hexdigest()[:8]
            root, ext = os.path.splitext(rel)
            root = re.sub(r'\.[0-9a-f]{8}$', '', root)
            new = f'{root}.{h}{ext}'
            if new != rel:
                os.replace(src, os.path.join(web, 'assets', new))
                f['asset'] = new
            keep.add(os.path.basename(new))
    json.dump(man, open(manp, 'w', encoding='utf-8'), separators=(',', ':'))
    # 上一版留下的带指纹字体，没人引用了，顺手清掉。
    fdir = os.path.join(web, 'assets', 'fonts')
    for name in os.listdir(fdir) if os.path.isdir(fdir) else []:
        if re.search(r'\.[0-9a-f]{8}\.(otf|ttf)$', name) and name not in keep:
            os.remove(os.path.join(fdir, name))
PY

# 自毁 SW：安装即接管，激活时清空所有缓存并注销自己。
cat > "$WEB"/flutter_service_worker.js <<'SW'
self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.registration.unregister(); })
  );
});
SW

# 顺手压一份 .gz：服务端遇到 .gz 直接发，不再现场压。
find "$WEB" -type f \( -name '*.js' -o -name '*.wasm' \) ! -name '*.gz' -exec gzip -9 -k -f {} +

echo "--- 检查"
curl -sk "$BASE/" | grep -q '<title>OpenBBS' && echo "首页 ok"
curl -sk -o /dev/null -w "main.dart.js %{http_code} %{size_download}B\n" -H 'Accept-Encoding: gzip' "$BASE/main.dart.js"
curl -sk -o /dev/null -w "feed %{http_code}\n" "$BASE/api/feed"
du -sh "$WEB"
