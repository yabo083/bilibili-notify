# bilibili-notify 本地 hotfix 备份（bren9np 生产实例）

本仓库（`yabo083/bilibili-notify`，fork 自 `Akokk0/bilibili-notify`）的分支 `koishi-hotfixes`
存放 bren9np Koishi 实例上长期运行的一组本地补丁。**上游没有这些改动**，重装依赖会全部丢失，
所以在此留一份可重放的备份。

## 部署形态（决定了补丁的打法）

实例：`bren9np:/root/.koishi/data/instances/default`
本地包仓库：`/root/.koishi/local-packages/*.tgz`
实例 `package.json` 用 `file:../../../local-packages/<pkg>-<ver>-<hash12>.tgz` 声明依赖，
文件名带内容哈希（npm 按 `name@version` 缓存 tarball 内容，同名同版本会装回旧字节）。

补丁是**对 npm 发布产物（`lib/index.cjs` / `lib/index.mjs`）的直接修改**，不是源码级补丁 ——
上游只发布编译产物，没有随包发布对应源码。因此本仓库以 unified diff 形式保存，并用
`apply.sh` 从 npm 基线重放。

## 补丁清单

| # | 包 | hotfix 版本 | 基线（npm） | 改动 |
|---|---|---|---|---|
| 01 | `koishi-plugin-bilibili-notify` | `5.0.0-alpha.5-hotfix.2` | `5.0.0-alpha.5` | 新增私聊二维码登录命令 `bili login`：`validateQrLoginSession()` 校验（限主人私聊 + 配置的平台）、订阅 `bilibili-notify/login-status-report` 事件、扫码后提示确认、成功/失败各回一条；登录触发改为直接调用 `beginLogin()` |
| 02 | `@bilibili-notify/api` | `0.2.0-alpha.2-hotfix.15` | `0.2.0-alpha.2` | 登录保活三件套（见下节） |
| 03 | `@bilibili-notify/push` | `2.0.0-alpha.1-hotfix.1` | `2.0.0-alpha.1` | master 可达性启动虚警：改为 2s 间隔、最多 90s 的有界轮询（onebot 反向 WS 实测 6~10s 才上线，固定 10s 单次判定必误报）；删掉发送私信前的 `refreshMasterReachability()` 拦截 |
| 04 | `@bilibili-notify/image` | `0.0.1-alpha.2-hotfix.1` | `0.0.1-alpha.2` | 图片预取改用 `undici.Agent({ connect: { family: 4 } })` 强制 IPv4（hdslb 解析到 IPv6 时 Node 侧连不通，头像/封面被替换成透明占位）；超时 10s → 20s |
| 05 | `@bilibili-notify/live` | `0.1.0-alpha.9-hotfix.0` | `0.1.0-alpha.9` | 弹幕连接预检被风控（-352）时不再回退「直接建连」，改为稍后重试；把预检拿到的 `token` / `host` / `port` 透传给 `startListen()`，避免二次请求再吃 -352 |

## 登录保活（补丁 02）的三个要点

1. **手工 Cookie 头注入**：`axios-cookiejar-support@5` 的 peer 范围是 `tough-cookie ^4 || ^5`，
   而实例装的是 `tough-cookie 6`，导致 jar **静默捕获不到任何 Set-Cookie**。补丁在
   `client.interceptors.request` 里用 `jar.getCookieStringSync(url)` 手动写 `Cookie` 头。
2. **刷新响应手工导入认证 cookie**：`addLoginCookiesFromSetCookie(headers, tag)` 只取
   `DedeUserID / DedeUserID__ckMd5 / SESSDATA / bili_jct / sid`。B 站约每 3 天翻一次
   `cookie/info` 的 `refresh=true`，`confirm/refresh` 会作废旧会话 —— 不导入新 cookie 就等于
   自杀式登出（这是历史上「每 3 天必掉线」的根因）。
3. **拿不到新凭据就不 confirm**：刷新响应里没有 `SESSDATA` 或 `bili_jct` 时直接 throw，跳过
   `confirm/refresh`，让旧会话继续活着等下轮重试；刷新成功后再用 `getCookieInfo` 复核一次才落盘。

### 已知缺口：hotfix.16 未落地

2026-09-14 曾做过 hotfix.16（`latestRefreshToken`：定时器每轮重新读取最新的 refresh_token，
避免闭包持有被作废的旧 token 导致第二轮回 `-101`），但 2026-09-25 的依赖重装把它覆盖回 hotfix.15，
当前生产包与 `tarballs/02-*.tgz` 都是 **hotfix.15，不含 `latestRefreshToken`**（`grep -c latestRefreshToken` = 0）。
生产实例自 2026-10 起长期未掉线，因此暂未重放；若再次出现「一次成功刷新后、约 72 小时回 -101」，
应优先补这个修复。

## 上游对照（截至 2026-10-31）

- 补丁 03 已被上游 `@bilibili-notify/push@2.0.0-alpha.2` 覆盖（改用 `recheckMasterReachability()` 在
  `login-added` / `login-updated` 事件复检，比轮询干净）。
- 补丁 05 的动机被上游 `@bilibili-notify/api@0.2.0-alpha.3` 从根上解决（`getDanmuInfo` 改走 `wbiGet` 签名）。
- 补丁 04 **上游始终没有**（bundle 里 `family: 4` 零命中），升级任何版本都必须重放。
- 补丁 02 上游用「fetch + 自研 `BiliCookieJar` 逐跳捕获」换了一套实现（`api@0.2.0-alpha.4`），
  但**没有第 3 点的保险丝**：刷新成功路径直接 `getCSRF()` → `confirm/refresh`，jar 未拿到新 cookie 时
  `getCSRF()` 取到的是仍有效的旧 `bili_jct`，照样 confirm → 作废旧会话。
- 上游 `koishi-plugin-bilibili-notify@5.2.1` 是 **Koishi 4 上的最后一版**，且改为自包含 bundle
  （`dependencies` 只有 `jsdom`，内联全部 `@bilibili-notify/*`）—— 升级它会绕过本仓库的补丁 02。

## 依赖钉住的 semver 事实

`0.2.0-alpha.2-hotfix.15` 的 prerelease 段解析为 `['alpha', '2-hotfix', 15]`，其中 `2-hotfix` 是
字母数字标识符，优先级**高于**数字标识符 `4`。因此该版本满足所有 `^0.2.0-alpha.N` 范围，
`@bilibili-notify/dynamic` / `live` 等声明 `^0.2.0-alpha.4` 的包不会把 api 顶掉。
（实例 yarn.lock 已把 `^0.2.0-alpha.2` / `^0.2.0-alpha.3` / `^0.2.0-alpha.4` / `file:` 四个描述符
归并成同一个 locator。）

## 重放

```sh
./apply.sh              # 全部
./apply.sh 02           # 只重放 api 补丁
```

脚本会：从 npm 下载基线版本 → 解包 → 应用对应 `.patch` → `npm pack` 产出
`<pkg>-<ver>-<hash12>.tgz`（与生产实例同一种命名），并打印 sha256。

`tarballs/` 目录下是本仓库备份时刻生产实例**实际在用**的那几个 tarball，可直接使用。

## 恢复生产（示例，api 补丁）

```sh
scp tarballs/02-*.tgz bren9np:/root/.koishi/local-packages/
ssh bren9np 'cd /root/.koishi/data/instances/default \
  && sed -i "s|\"@bilibili-notify/api\": .*|\"@bilibili-notify/api\": \"file:../../../local-packages/<新文件名>.tgz\",|" package.json \
  && rm -rf node_modules/@bilibili-notify/api \
  && npm install --no-audit --no-fund \
  && systemctl restart koishi'
```

注意：`rm -rf` 之前先单独跑一次 `npm install`，确认实例依赖树健康 —— 若 lockfile 里存在
integrity 与实际 tarball 不符的 `file:` 依赖，整个安装会以 `EINTEGRITY` 失败，被删掉的包装不回来。
