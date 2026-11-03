import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/site_meta.dart';

void main() {
  group('清单校验三条规则', () {
    test('缺地址丢弃', () {
      final keep = SiteMeta.parseManifest({
        'sites': [
          {'id': 'a', 'name': '有地址', 'url': 'https://a.example', 'api': 2},
          {'id': 'b', 'name': '没地址', 'api': 2},
          {
            'id': 'c',
            'name': '只有空入口',
            'endpoints': [
              {'note': 'x'},
            ],
            'api': 2,
          },
        ],
      });
      expect(keep.map((e) => e.id), ['a']);
    });

    test('id 去重，先到先得', () {
      final dropped = <Map<String, String>>[];
      final keep = SiteMeta.parseManifest({
        'sites': [
          {'id': 'dup', 'name': '一', 'url': 'https://1.example', 'api': 2},
          {'id': 'dup', 'name': '二', 'url': 'https://2.example', 'api': 2},
        ],
      }, dropped: dropped);
      expect(keep.single.name, '一');
      expect(dropped.single['reason'], 'duplicate_id');
    });

    test('版本过高禁入，老版本放行', () {
      final dropped = <Map<String, String>>[];
      final keep = SiteMeta.parseManifest({
        'sites': [
          {'id': 'new', 'name': '太新', 'url': 'https://n.example', 'api': 99},
          {'id': 'old', 'name': '老站', 'url': 'https://o.example', 'api': 1},
          {'id': 'now', 'name': '当前', 'url': 'https://c.example', 'api': 2},
        ],
      }, dropped: dropped);
      expect(keep.map((e) => e.id), ['old', 'now']);
      expect(dropped.single['reason'], 'api_too_new');
    });

    test('没有 id 的条目也留着，交给上层标未登记', () {
      final keep = SiteMeta.parseManifest({
        'sites': [
          {'name': '没 id', 'url': 'https://x.example', 'api': 2},
        ],
      });
      expect(keep.single.id, '');
      expect(keep.single.url, 'https://x.example');
    });
  });

  group('自述解析', () {
    test('/meta 与 bbs.json 的单条都能吃', () {
      final a = SiteMeta.fromJson({
        'id': 'kalutoex',
        'name': '时间線',
        'url': 'https://bbs.example',
        'api': 2,
        'capabilities': ['meta', 'sites'],
        'endpoints': [
          {'url': 'https://bbs.example', 'note': '主入口'},
          {'url': 'https://v4.example', 'note': 'IPv4'},
        ],
      })!;
      expect(a.id, 'kalutoex');
      expect(a.has('sites'), isTrue);
      expect(a.has('nope'), isFalse);
      expect(a.urls, ['https://bbs.example', 'https://v4.example']);

      final b = SiteMeta.fromBody(
        '{"schema":1,"sites":[{"id":"x","name":"X","url":"https://x.example","api":2}]}',
      )!;
      expect(b.id, 'x');
    });

    test('兼容老字段名 site_id / base_url', () {
      final m = SiteMeta.fromJson({
        'site_id': 'abc',
        'base_url': 'https://old.example',
        'api': 1,
      })!;
      expect(m.id, 'abc');
      expect(m.url, 'https://old.example');
    });

    test('版本比较按整数，不按字符串', () {
      const m = SiteMeta(api: 10);
      expect(m.tooNew, isTrue);
      const ok = SiteMeta(api: 2);
      expect(ok.tooNew, isFalse);
    });
  });
}
