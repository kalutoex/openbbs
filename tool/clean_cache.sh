#!/usr/bin/env bash
# 清构建缓存。只删能重建的东西，源码、产物、归档一概不碰。
#
# 出包变慢多半是这两处堆起来的：
#   build/test_cache      flutter test 的 kernel 缓存，跑几十次测试能到七八百兆
#   .dart_tool/flutter_build  增量编译中间产物，改得多就攒得多
# 清完第一次构建要重编一遍前端（约两分钟），之后就回快的那一档。

set -euo pipefail
cd "$(dirname "$0")/.."

before=$(du -sm . 2>/dev/null | cut -f1)

rm -rf build/test_cache
rm -rf .dart_tool/flutter_build
rm -rf android/.gradle android/app/build

after=$(du -sm . 2>/dev/null | cut -f1)
echo "项目 ${before}M -> ${after}M"
echo "清完了。下次构建会全量编一次前端，之后就快了。"
