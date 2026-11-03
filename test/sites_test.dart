import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/site_meta.dart';
import 'package:openbbs/sites.dart';

SiteEntry e(String id, List<String> urls, {bool master = false, String name = ''}) =>
    SiteEntry(id: id, name: name, urls: urls, master: master);

void main() {
  group('地址规整', () {
    test('补协议、去尾斜杠', () {
      expect(normalizeUrl('  bbs.example.com:8080/  '), 'http://bbs.example.com:8080');
      expect(normalizeUrl('https://a.example///'), 'https://a.example');
      expect(normalizeUrl('   '), '');
    });

    test('取主机名', () {
      expect(hostOf('http://1.2.3.4:8080'), '1.2.3.4');
      expect(hostOf('https://ipv6bbs.kalutoex.dpdns.org'), 'ipv6bbs.kalutoex.dpdns.org');
      expect(hostOf(''), '');
    });
  });

  group('v6 优先', () {
    test('三种写法都认', () {
      expect(looksV6('http://[2603:c020::1]:8080'), isTrue);
      expect(looksV6('https://ipv6bbs.example.org'), isTrue);
      expect(looksV6('https://bbs-v6.example.org'), isTrue);
      expect(looksV6('http://1.2.3.4:8080'), isFalse);
      expect(looksV6('https://bbs.example.org'), isFalse);
    });

    test('排到前面，其余不乱序', () {
      final out = orderV6First([
        'https://ipv4bbs.example.org',
        'https://ipv6bbs.example.org',
        'http://1.2.3.4:8080',
        'http://[2603::1]:8080',
      ]);
      expect(out, [
        'https://ipv6bbs.example.org',
        'http://[2603::1]:8080',
        'https://ipv4bbs.example.org',
        'http://1.2.3.4:8080',
      ]);
    });

    test('站点自己排序，不改入参', () {
      final s = e('', ['https://ipv4bbs.x.org', 'https://ipv6bbs.x.org']);
      expect(s.orderedUrls.first, 'https://ipv6bbs.x.org');
      expect(s.urls.first, 'https://ipv4bbs.x.org');
    });
  });

  group('合并站点表', () {
    test('同 id 更新原来那行，位置不动', () {
      final old = [e('a', ['https://a.example']), e('b', ['https://b.example'])];
      final out = mergeSites(old, [
        e('b', ['https://b2.example'], name: 'B 站'),
      ]);
      expect(out.length, 2);
      expect(out[1].id, 'b');
      expect(out[1].name, 'B 站');
      expect(out[1].urls, ['https://b.example', 'https://b2.example']);
    });

    test('没 id 的按地址重叠认', () {
      final old = [e('', ['http://1.2.3.4:8080'])];
      final out = mergeSites(old, [
        e('new', ['http://1.2.3.4:8080', 'http://[2603::1]:8080']),
      ]);
      expect(out.length, 1);
      expect(out.single.id, 'new');
      expect(out.single.urls.length, 2);
    });

    test('都对不上就追加', () {
      final out = mergeSites(
        [e('a', ['https://a.example'])],
        [e('z', ['https://z.example'])],
      );
      expect(out.map((s) => s.id), ['a', 'z']);
    });

    test('登录站唯一，一座都没有时第一座顶上', () {
      final out = mergeSites([
        e('a', ['https://a.example'], master: true),
        e('b', ['https://b.example'], master: true),
      ], []);
      expect(out.where((s) => s.master).length, 1);
      expect(out.first.master, isTrue);

      final none = mergeSites([e('a', ['https://a.example'])], []);
      expect(none.single.master, isTrue);
    });

    test('空地址的行进不来', () {
      final out = mergeSites([], [e('x', const [])]);
      expect(out, isEmpty);
    });

    test('不改入参', () {
      final old = [e('a', ['https://a.example'])];
      mergeSites(old, [e('a', ['https://a2.example'])]);
      expect(old.single.urls, ['https://a.example']);
    });
  });

  group('落盘与读取', () {
    test('往返一致，重复地址只留一条', () {
      final s = e('id1', ['https://a.example', 'https://a.example'], name: '甲');
      final back = SiteEntry.fromJson({
        'id': 'ID1',
        'name': '甲',
        'urls': ['https://a.example', 'https://a.example'],
        'api': 2,
        'master': true,
      });
      expect(back.id, 'id1');
      expect(back.urls, ['https://a.example']);
      expect(back.master, isTrue);
      expect(SiteEntry.fromJson(s.toJson()).key, s.key);
    });

    test('lastOk 不在 urls 里就当没有', () {
      final back = SiteEntry.fromJson({
        'urls': ['https://a.example'],
        'last_ok': 'https://gone.example',
      });
      expect(back.lastOk, isNull);
    });

    test('没有 id 时用首个地址当 key', () {
      expect(e('', ['https://a.example']).key, 'https://a.example');
    });

    test('自述回来补名字和入口', () {
      final s = e('', ['http://1.2.3.4:8080']);
      s.applyMeta(
        const SiteMeta(
          id: 's1',
          name: '一号站',
          url: 'https://bbs.example',
          endpoints: [],
          api: 2,
        ),
      );
      expect(s.id, 's1');
      expect(s.name, '一号站');
      expect(s.urls, ['https://bbs.example']);
      expect(s.api, 2);
    });
  });
}
