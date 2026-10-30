# 更新记录

本文件记录每次发布的变更内容与涉及文件。格式：问题 → 原因 → 处理 → 影响文件。

## 2026-10-30

### 1. 代理页底部内容被悬浮 Dock 遮挡

- **问题**：代理页滚动到底部时，最后 1~2 个节点被底部悬浮 Dock 压住。
- **原因**：`Index.ets` 的 `HdsTabs` 开启了 `barOverlap(true)`，TabContent 会延伸到悬浮 Dock 之下；代理页滚动区只给了 12vp 内边距。
- **处理**：新增 `DOCK_BOTTOM_INSET = 104`（barHeight 52 + 底部边距 8 + 材质渐变余量），滚动内容底部内边距改为该值，与配置页列表保持一致。
- **文件**：`entry/src/main/ets/pages/ProxyPage.ets`

### 2. 配置改名后列表与详情页仍显示旧名称

- **问题**：配置页修改名称并保存后，返回列表仍是旧名称；再次进入编辑页名称也未更新。
- **原因**：`ForEach` 的 key 只用了 `p.uid`。改名后数组里是新对象但 key 不变，ArkUI 判定「无变化」复用旧节点；同时列表项捕获的旧 `Profile` 对象被 `openProfile()` 直接用于回填。
- **处理**：key 改为 `uid:name:desc:url:updated`；`openProfile()` 改为按 uid 从 `this.profiles` 取最新对象。
- **文件**：`entry/src/main/ets/pages/ConfigurationPage.ets`

### 3. 订阅配置导致全部节点超时（内核没有可用 DNS）

- **问题**：同一份机场订阅在 iOS（Shadowrocket）可用，在 ClashH 里所有节点测速超时。
- **原因**：该订阅 YAML 带 `dns.enable: false`，且 19 个节点的 server 全是域名（无 IP）。旧逻辑「配置里有 dns 段就原样尊重」，导致内核没有可用 DNS；TUN 又把 53 端口整体劫持给这个被禁用的 DNS，节点域名全部解析失败 → 整页超时。
- **处理**：新增 `hasUsableDns()`（必须 `enable === true` 且 `nameserver` 非空才算可用）。不可用则整段替换为内置 DNS（fake-ip + 国内 DoH + `proxy-server-nameserver`）；可用时也补全缺失的 `proxy-server-nameserver`，避免节点域名解析绕回隧道自身。
- **文件**：`entry/src/main/ets/entryability/ClashVpnAbility.ets`

### 4. 分享链接导入丢失 `allowInsecure`（机场自签证书全部握手失败）

- **问题**：扫码/分享链接导入的机场节点，vless 全部超时。
- **原因**：转换器只给 trojan 处理了 `allowInsecure`，vless/vmess 完全忽略。机场常用「借用域名做 SNI + 自签证书」，丢掉该开关后内核严格校验证书，TLS 握手直接失败。
- **处理**：新增 `isInsecure()`（兼容 `allowInsecure` / `allow_insecure` / `insecure`）与 `tlsServername()`（`sni` → `peer` 回退），在 vless / vmess / trojan / hysteria / hysteria2 上统一生效。
- **验证**：同一份订阅转换后 19 个节点全部生成 `skip-cert-verify: true`；用 mihomo 实测，修复前 14 个 vless 全部失败，修复后大多恢复（90~780ms）。
- **文件**：`entry/src/main/ets/service/ShareLinkParser.ets`

### 5. 测速结束仍显示 `--`，切换 Tab 后才出现数字

- **问题**：点击延迟测试（尤其是组头的「测速」）后 loading 结束，节点仍显示 `--`，需切到别的 Tab 再回来才更新。
- **原因**：`ClashClient.request` 默认超时 5000ms，而内核单节点测速上限是 30s、批量按 8 个一批串行，整组必然在 5s 被客户端判超时；旧代码又完全丢弃 RPC 返回值，只依赖测速后立刻回查 `/proxies` 的 `history`，此时内核还没测完，拿到空数组后页面再无刷新。
- **处理**：
  - ViewModel 新增 `delays: Record<string, number>`，用 RPC 返回值直接回填；
  - 单节点超时 35s，批量按 `max(40s, 轮数 × 32s + 8s)`；
  - 批量测速期间每 1.2s 轮询 `queryGroups()`，实现边测边显示；
  - 页面新增 `@State delays`（每次拷贝成新对象触发重建），`delayValue()` 本地结果优先、history 兜底；
  - 离开页面 / 页面销毁时停止轮询。
- **文件**：`entry/src/main/ets/viewmodel/ProxyViewModel.ets`、`entry/src/main/ets/pages/ProxyPage.ets`

### 6. 内核测速超时参数未生效

- **问题**：`HealthCheck` 请求里的 `timeout` 字段被解析后没有使用，不可达节点会一直卡到内核默认超时。
- **处理**：`handleAsyncTestDelay` 改用 `context.WithTimeout`，默认 5s。
- **备注**：该改动位于 `libflclash.so`，需要重新编译内核后才生效；未重编时客户端超时已放宽兜住。
- **文件**：`proxy_core/src/flclash/hub.go`

### 7. 测试与工程

- 新增 `ShareLinkParser` 回归用例（vless 的 `allowInsecure`、trojan 的 `peer` 作 SNI）。
- `.gitignore` 补充 `entry/.test/`、`proxy_core/.test/`、`.workbuddy/`。
- **文件**：`entry/src/test/List.test.ets`、`.gitignore`

### 附：Mac 端 Clash Verge 全部 Timeout 的原因（非本项目代码）

同一订阅在 Verge 里 21 个节点全部 Timeout，排查结论：订阅自带的 `dns.fallback` 指向国内不可达的境外 DoH（`doh.dns.sb`、`dns.twnic.tw`、`tls://8.8.4.4`），而节点域名都解析到境外 IP，必然触发 fallback，四个服务器串行超时十几秒，导致解析失败。在 Verge 的全局扩展配置 `profiles/Merge.yaml` 中加 `dns: { fallback: [] }` 后恢复，18 个真实节点全部可测通。此前未暴露是因为旧节点为 IP 直连，不需要域名解析。
