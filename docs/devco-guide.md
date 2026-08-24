# DevEco Studio 打开项目 + 无线连接真机指南

> 适用：HarmonyOS NEXT 6.1.0（API 23+）设备（MatePad 12.2 / MatePad mini / 手机）

## 一、用 DevEco Studio 打开 ClashH

### 1. 打开项目

1. 启动 DevEco Studio
2. `File -> Open`，选择 **ClashH 项目根目录**（包含 `build-profile.json5` 的那一层）
3. 等待 Hvigor 同步完成（首次会下载依赖，耐心等待）

### 2. 首次打开可能出现的提示及处理

| 提示 | 处理方式 |
| --- | --- |
| SDK 版本不匹配 | `File -> Project Structure -> SDK` 选择 HarmonyOS 6.1.0（API 23） |
| 缺少签名配置 | 见下方「签名配置」 |
| CMake 警告（未找到 libflclash.so） | 正常，UI 可先跑；编译内核后自动启用 |
| 依赖安装提示 | 点击 Sync Now / 重新同步 |

### 3. 配置签名（真机运行必需）

**方式一：自动签名（推荐，需华为账号）**

1. `File -> Project Structure -> Signing Configs`
2. 勾选 `Automatically generate signature`
3. 登录华为开发者账号（真机测试无需实名认证，侧载签名 14 天有效；实名认证后 180 天）
4. 勾选需要签名的模块（entry / proxy_core），点 Apply

**方式二：手动签名（已有证书）**

在 Signing Configs 中导入 .p12 / .cer / .p7b 证书并配置别名与密码。

> 注意：`build-profile.json5` 中的 `signingConfigs` 为空数组，
> DevEco 自动签名会在此处生成配置，无需手动修改。

### 4. 首次构建

Build -> Build Hap(s)/APP(s) -> Build Hap(s)

如构建通过，`entry/build/default/outputs/default/` 下会生成 `entry-default-signed.hap`。

## 二、无线连接真机（不插 USB）

HarmonyOS NEXT 支持 **HDC（HarmonyOS Device Connector）无线调试**，
DevEco Studio 已内置 hdc 工具，无需安装额外软件。

### 方法 A：DevEco Studio 图形界面（推荐）

1. **平板开启开发者模式**
   `设置 -> 关于平板电脑 -> 连续点击"版本号"7次`
2. **开启无线调试**
   `设置 -> 系统和更新 -> 开发人员选项 -> USB调试（先打开）`
   再打开 `无线调试`（HarmonyOS NEXT 5.0+ 均有此选项）
3. **同一 Wi-Fi**：电脑和平板连接同一局域网
4. **DevEco Studio 连接设备**
   - 顶部菜单 `Tools -> Device Manager`
   - 点 `+` 添加设备，选择 `Wireless`
   - 输入平板的 IP 地址（`设置 -> WLAN -> 当前网络详情` 可查看）
   - 按提示输入配对码（平板上无线调试页面显示 6 位配对码）
5. 连接成功后，DevEco 的设备列表会出现你的平板

### 方法 B：命令行 hdc

```bash
# 查看 hdc 位置（DevEco Studio 内置）
# macOS: /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc

# 1. 平板无线调试页面查看 IP 和端口（如 192.168.1.100:5555）
# 2. 电脑执行（先配对）
hdc tconn 192.168.1.100:5555

# 3. 验证连接
hdc list targets
# 输出应包含 192.168.1.100:5555

# 4. 查看日志（可选）
hdc hilog

# 5. 安装应用（可选，DevEco 通常直接 Run）
hdc install entry/build/default/outputs/default/entry-default-signed.hap

# 6. 断开
hdc tconn 192.168.1.100:5555 --disconnect
```

### 方法 C：先 USB 后无线（兜底）

1. USB 连接平板，允许调试授权
2. DevEco 设备列表确认出现设备
3. 拔掉 USB，平板仍可通过无线调试保持连接（HDC 支持自动切换）

## 三、在真机上运行

1. 设备列表选中平板
2. 点击工具栏 `Run`（绿色三角）
3. 首次运行需要安装 HAP 并授权（注意：VPN 能力在点击「连接」时才请求授权）

## 四、常见问题（FAQ）

### Q1: 无线调试找不到设备？

- 确认电脑和平板在同一局域网
- 关闭平板的 VPN/代理（如果开了）
- 平板开发者选项里重新开关一次无线调试
- 检查防火墙是否拦截（macOS 首次会弹窗，点允许）

### Q2: Run 时报「未配置签名」？

按上文「配置签名」操作自动签名，或检查 `File -> Project Structure -> Signing Configs`。

### Q3: 构建报错 `undefined symbol` / 链接错误？

说明 `libflclash.so` 未编译：

```bash
cd proxy_core/src/flclash
./init_core.sh
./build.sh
```

详见 `docs/build.md`。若暂时不编译内核，UI 仍可运行（内核功能返回占位错误）。

### Q4: 安装了 HAP 但图标不显示？

检查 `AppScope/app.json5` 的 bundleName 是否与签名配置一致，重新签名安装。

### Q5: 启动 VPN 提示「设备不支持」？

确认系统版本为 HarmonyOS NEXT 5.0+（API 12+），6.1.0（API 23）最佳。

## 五、开发调试小技巧

- **实时日志**：DevEco `Log` 面板过滤 `ClashH` 关键字
- **断点调试**：ArkTS 与 C++ 均支持断点（Run -> Debug）
- **布局调试**：DevEco Inspector 查看 UI 树
- **多尺寸适配**：旋转平板或用窗口分屏验证断点切换
