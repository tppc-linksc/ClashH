// hub.go：内核功能处理器
// 每个 handle* 函数对应一个 NAPI 导出或 RPC 方法
package main

import (
	"clashh/core/state"
	tuncore "clashh/core/tun"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// ---------------------------------------------------------------------------
// 内核生命周期
// ---------------------------------------------------------------------------

// handleInitClash：初始化内核
func handleInitClash(homeDirStr string) bool {
	if homeDirStr == "" {
		return false
	}
	initHomeDir(homeDirStr)
	isInit = true
	log.Infoln("ClashH 内核初始化完成，homeDir=%s", homeDirStr)
	return true
}

// handleValidateConfig：校验配置
func handleValidateConfig(bytes []byte) string {
	// 解析并校验 YAML 配置
	_, err := config.Parse(bytes)
	if err != nil {
		return fmt.Sprintf(`{"status":"invalid","error":%q}`, err.Error())
	}
	return `{"status":"valid"}`
}

// handleUpdateConfig：更新配置并重载内核
func handleUpdateConfig(bytes []byte) string {
	var params GenerateConfigParams
	if err := json.Unmarshal(bytes, &params); err != nil {
		return fmt.Sprintf(`{"status":"invalid","error":%q}`, err.Error())
	}

	raw := params.Config
	raw.Tun.Enable = true
	raw.Tun.AutoRoute = false
	raw.Tun.AutoDetectInterface = false

	if err := applyConfig(&raw); err != nil {
		return fmt.Sprintf(`{"status":"invalid","error":%q}`, err.Error())
	}
	return `{"status":"valid"}`
}

// handleShutdown：关闭内核
func handleShutdown() bool {
	StopTun()
	executor.Shutdown()
	isInit = false
	return true
}

// handleForceGc：强制回收内存
func handleForceGc() {
	runtime.GC()
}

// ---------------------------------------------------------------------------
// TUN 隧道
// ---------------------------------------------------------------------------

// tunListener：当前 TUN 监听器
var tunListener *sing_tun.Listener

// StartTUN：启动 TUN 隧道
func StartTUN(fd int) bool {
	tunLock.Lock()
	defer tunLock.Unlock()

	// 启动 TUN
	listener, err := tuncore.Start(fd, "tun0", constant.TunSystem, []string{})
	if err != nil {
		log.Errorln("启动 TUN 失败: %v", err)
		return false
	}
	tunListener = listener
	state.CurrentState.TunIp = state.DefaultIpv4Address
	log.Infoln("TUN 隧道已启动，fd=%d", fd)
	return true
}

// StopTun：停止 TUN 隧道
func StopTun() {
	tunLock.Lock()
	defer tunLock.Unlock()
	if tunListener != nil {
		_ = tunListener.Close()
		tunListener = nil
		log.Infoln("TUN 隧道已停止")
	}
}

// GetVpnOptions：获取 VPN 选项（供 UI 配置系统 VPN）
func GetVpnOptions() string {
	options := map[string]any{
		"enable":      true,
		"ipv4Address": state.DefaultIpv4Address,
		"dnsServer":   state.GetDnsServerAddress(),
		"ipv6":        state.CurrentState.Ipv6,
		"mtu":         1400,
		"routes":      []string{"0.0.0.0/0"},
	}
	data, _ := json.Marshal(options)
	return string(data)
}

// ---------------------------------------------------------------------------
// 数据查询
// ---------------------------------------------------------------------------

// handleGetProxies：获取代理列表（JSON）
func handleGetProxies() string {
	// adapter.Proxy 自带 MarshalJSON，可完整输出代理组的 now/all、节点历史与能力信息。
	data, _ := json.Marshal(map[string]any{
		"proxies": tunnel.Proxies(),
		"mode":    tunnel.Mode().String(),
	})
	return string(data)
}

// handleChangeProxy：切换代理节点
func handleChangeProxy(data string, fn func(string)) {
	var params ChangeProxyParams
	if err := json.Unmarshal([]byte(data), &params); err != nil ||
		params.GroupName == nil || params.ProxyName == nil {
		fn(`{"status":"invalid","error":"参数错误"}`)
		return
	}
	// 切换代理组节点
	proxy := tunnel.Proxies()[*params.GroupName]
	if proxy == nil {
		fn(fmt.Sprintf(`{"status":"invalid","error":%q}`, "代理组不存在: "+*params.GroupName))
		return
	}
	selector, ok := proxy.Adapter().(outboundgroup.SelectAble)
	if !ok {
		fn(fmt.Sprintf(`{"status":"invalid","error":%q}`, "不是可切换的代理组: "+*params.GroupName))
		return
	}
	if err := selector.Set(*params.ProxyName); err != nil {
		fn(fmt.Sprintf(`{"status":"invalid","error":%q}`, err.Error()))
		return
	}
	fn(`{"status":"ok"}`)
}

// handleAsyncTestDelay：延迟测试
func handleAsyncTestDelay(data string, fn func(string)) {
	var params TestDelayParams
	if err := json.Unmarshal([]byte(data), &params); err != nil {
		fn(`{"delay":-1}`)
		return
	}
	proxy := tunnel.Proxies()[params.ProxyName]
	if proxy == nil {
		fn(`{"delay":-1}`)
		return
	}
	url := params.TestUrl
	if url == "" {
		url = "http://www.gstatic.com/generate_204"
	}
	go func() {
		delay, err := proxy.URLTest(context.Background(), url, nil)
		if err != nil {
			fn(`{"delay":-1}`)
			return
		}
		fn(fmt.Sprintf(`{"delay":%d}`, delay))
	}()
}

// handleGetTraffic：获取实时流量
func handleGetTraffic(onlyProxy bool) string {
	up, down := statistic.DefaultManager.Now()
	data, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(data)
}

// handleGetTotalTraffic：获取总流量
func handleGetTotalTraffic(onlyProxy bool) string {
	up, down := statistic.DefaultManager.Total()
	data, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(data)
}

// handleResetTraffic：重置流量统计
func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

// handleGetConnections：获取连接列表
func handleGetConnections() string {
	snapshot := statistic.DefaultManager.Snapshot()
	data, _ := json.Marshal(snapshot)
	return string(data)
}

// handleCloseConnections：关闭全部连接
func handleCloseConnections() bool {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
	return true
}

// handleCloseConnection：关闭指定连接
func handleCloseConnection(connectionId string) bool {
	if c := statistic.DefaultManager.Get(connectionId); c != nil {
		_ = c.Close()
	}
	return true
}

// ---------------------------------------------------------------------------
// 供应商（订阅）
// ---------------------------------------------------------------------------

// handleGetExternalProviders：获取全部供应商
func handleGetExternalProviders() string {
	providers := getExternalProvidersRaw()
	result := make([]*ExternalProvider, 0, len(providers))
	for _, p := range providers {
		item, err := toExternalProvider(p)
		if err == nil {
			result = append(result, item)
		}
	}
	data, _ := json.Marshal(result)
	return string(data)
}

// ---------------------------------------------------------------------------
// 日志
// ---------------------------------------------------------------------------

// logCallback：日志回调
var logCallback func(value string)

const maxRequestList = 1000

var requestList []statistic.Tracker
var requestLock sync.RWMutex

func init() {
	statistic.DefaultRequestNotify = func(tracker statistic.Tracker) {
		requestLock.Lock()
		defer requestLock.Unlock()
		requestList = append(requestList, tracker)
		if len(requestList) > maxRequestList {
			requestList = append([]statistic.Tracker(nil), requestList[len(requestList)-maxRequestList:]...)
		}
	}
}

// handleStartLog：注册日志回调
func handleStartLog(fn func(value string)) {
	logCallback = fn
	log.Infoln("日志回调已注册")
}

// handleStopLog：停止日志回调
func handleStopLog() {
	logCallback = nil
}

func handleGetRequestList() string {
	requestLock.RLock()
	defer requestLock.RUnlock()
	data, _ := json.Marshal(requestList)
	return string(data)
}

func handleClearRequestList() {
	requestLock.Lock()
	requestList = nil
	requestLock.Unlock()
}

// logObserver：日志观察者（供 mihomo log 库回调）
func logObserver(level log.LogLevel, payload string) {
	if logCallback == nil {
		return
	}
	msg := Message{
		Type:    strings.ToLower(level.String()),
		Payload: payload,
	}
	data, _ := json.Marshal(msg)
	logCallback(string(data))
}

// handleGetMemory：获取内存占用
func handleGetMemory(fn func(value string)) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	fn(fmt.Sprintf(`{"inuse":%.1f}`, float64(m.Alloc)/(1024*1024)))
}

// 全局锁
var tunLock sync.Mutex

// 编译期引用 hub 包（启动 external controller 能力）
var _ = hub.WithExternalController
var _ = os.Getenv
