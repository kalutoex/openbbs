# 第 1 段排查报告：接口与数据层

时间：2026-11-05 20:03–20:25
对象：`bbs/server`（线上权威服务端）
方式：线上库只读对账 + 副本实例（127.0.0.1:18080，库 `/tmp/dbg1/forum.db`）做写测试
备份：`data/backups/debug1_20261105_200326.db`（已 `--check` 通过）

## 一句话结论

权限和数据没有穿底，计数与引用全对。查出 1 个真实的 500（未登录打管理接口），1 个潜在分页隐患，8 个体验/健壮性问题。**没有 P0。**

## P1

### 1. 未登录访问管理接口返回 500（已复现）

`_need_admin` 在 api.py 里定义了三次：917、2127、2774。后一份覆盖前一份，而 2774 那份漏了空值判断：

```python
def _need_admin(user):
    if not user["is_admin"]:      # user 为 None 时 TypeError
```

后果：22 个调 `_need_admin` 的接口，**未登录时全部 500**，不是 401/403。

证据：
```
GET /api/admin/users        -> 500
GET /api/admin/cloud/usage  -> 500
TypeError: 'NoneType' object is not subscriptable   (api.py:2775)
```
带普通用户 token 访问是正常的 403，所以不影响安全，只是错误语义错 + 日志噪音 + 客户端会走"服务器错误"分支。

修法：删掉 2774 和 2127 的重复定义，只留 917 那份（`if not user or not user["is_admin"]`）。

### 2. /feed 排序没有 id 兜底（潜在）

```sql
ORDER BY t.is_top DESC, (CASE ...) ASC, t.created_at DESC LIMIT ? OFFSET ?
```
`created_at` 是秒级整数，同秒发的两条帖顺序由 SQLite 内部决定，翻页时可能重复或漏条。
现状：库里没有同秒帖（`GROUP BY created_at HAVING COUNT(*)>1` 为空），所以还没发作。
修法：末尾加 `, t.id DESC`。

## P2

3. **浏览量可刷**：`GET /api/t/{tid}` 每次都 `view_count+1`，未登录也算。35 号帖 2 条回复 58 次浏览。
4. **楼层号会留洞**：顶级楼 `floor_no` 只在新建时分配（`MAX+1`），删楼不重排；楼中楼不占楼层号。现在是 `2,3` 连续，删一条就会出现 `2,4`。
5. **取消赞不撤通知**：`agree` 有新通知去重，但取消点赞后旧通知还留着，点进去帖子里已经没有赞。
6. **附件被静默丢弃**：`_norm_files` 对不存在/无归属的 digest 直接 `continue`，接口仍返回 200。客户端以为附件挂上了，实际入库 `files: []`。
7. **短词搜索全表扫**：`use_fts = len(q) >= 3`，1–2 字走 `LIKE %x%`（trigram 索引吃不到）。当前 21 帖无感，帖子多了会慢。
8. **threads 缺 user_id 索引**：用户页、我的帖子按 `user_id` 查是全表扫。现有索引只覆盖 `updated_at`。
9. **验证码接口的清理语句不提交**：`password_code` / `account_email_code` 里 `DELETE FROM email_sends WHERE created_at < now-86400` 没有 `c.commit()`，每次都被回滚——旧发送记录永远清不掉。功能无损。
10. **超长输入静默截断**：标题 120、正文 20000 直接切片，不报 400。客户端不知道被截了。

## 已验证通过

鉴权与越权
- 未登录：发帖 401、收藏 401、`/me` 返回 `{"user": null}` 不崩
- 普通用户：查 admin 403、重置他人密码 403、改他人帖 403、删他人帖 403

边界
- 不存在的帖 404、给不存在帖回复 404、点赞不存在对象 404
- 空标题 / 空内容 400，`kind` 非法 400
- `page=-5` 钳到 1，`page=99999` 返回空列表

数据一致性（线上库，只读）
- `reply_count` / `agree_count` 与真实行数：0 处不一致
- 10 类孤儿引用（回复→帖、赞→目标、通知→用户/帖、收藏、历史、关注、账本→用户/帖、私信→线程）全为 0
- 重复赞、重复收藏、重复用户名、重复 handle、重复 uid、空标题：全 0

功能正确性（副本库，写入测试）
- 点赞幂等：连点两次 = 赞/取消，计数与 likes 行数一致
- 自赞、自回复自己：不产生通知
- `parent_id` 指向不存在的楼：降级成普通楼（floor 3）
- 删帖级联：likes、favorites、notifications、replies、replies_fts 全部清空
- FTS：改帖后旧词搜不到（0），新词搜得到（1）；trigram 分词正常，中文 3 字可命中
- 图片白名单：`https://evil.example/a.png` 被丢，只留 `/img/...`
- 模板层无 `|safe`，标题里的 `<script>` 原样返回但不会执行

## 未覆盖

- 注册并发同名（有唯一索引，预期 500 而非 409，未实测）
- `_ensure_shadow` 并发首次建影子行（理论上有竞争）
- 邮件验证码全链路（需要真发信）
- 静态资源与部署相关项（第 5 段）

## 建议动手顺序

1. `_need_admin` 去重（1 行改动，风险最低）
2. `/feed` 加 `t.id DESC`
3. threads 加 `user_id` 索引
4. 其余按需，属体验层
