//go:build cgo && ohos

// main_cgo.go：Go 内核的 NAPI 入口
// 使用 ohos-napi 库直接把 Go 函数导出为 ArkTS 可调用的 NAPI 接口
//（参照 ClashBox 的 proxy_core/src/flclash/main_cgo.go）

package main

import (
	"clashh/core/state"
	"encoding/json"
	"fmt"
	"strings"

	napi "github.com/likuai2010/ohos-napi"
	"github.com/likuai2010/ohos-napi/entry"
	"github.com/likuai2010/ohos-napi/js"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// ---------------------------------------------------------------------------
// 内核生命周期
// ---------------------------------------------------------------------------

// initClash：初始化内核（设置 homeDir、版本）
func initClash(env js.Env, this js.Value, args []js.Value) any {
	homeDirStr, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	return handleInitClash(homeDirStr)
}

// startTun：启动 TUN 隧道（fd 来自系统 VPN 虚拟网卡）
func startTun(env js.Env, this js.Value, args []js.Value) any {
	tunFd, _ := napi.GetValueInt32(env.Env, args[0].Value)
	return StartTUN(int(tunFd))
}

// stopTun：停止 TUN 隧道
func stopTun(env js.Env, this js.Value, args []js.Value) any {
	StopTun()
	return nil
}

// forceGc：强制 GC
func forceGc(env js.Env, this js.Value, args []js.Value) any {
	handleForceGc()
	return nil
}

// shutdownClash：关闭隧道并释放内核运行状态
func shutdownClash(env js.Env, this js.Value, args []js.Value) any {
	return handleShutdown()
}

// loadConfig：从应用 profiles 目录加载指定配置
func loadConfig(env js.Env, this js.Value, args []js.Value) any {
	profileID, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	raw := getRawConfigWithId(profileID)
	if raw == nil {
		return `{"status":"invalid","error":"配置不存在"}`
	}
	if err := applyConfig(decorationConfig(profileID, *raw)); err != nil {
		return fmt.Sprintf(`{"status":"invalid","error":%q}`, err.Error())
	}
	state.CurrentState.CurrentProfileName = profileID
	return `{"status":"ok"}`
}

// validateConfig：校验配置
func validateConfig(env js.Env, this js.Value, args []js.Value) any {
	paramsString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	promise := env.NewPromise()
	bytes := []byte(paramsString)
	go func() {
		promise.Resolve(handleValidateConfig(bytes))
	}()
	return promise
}

// updateConfig：更新配置
func updateConfig(env js.Env, this js.Value, args []js.Value) any {
	paramsString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	promise := env.NewPromise()
	bytes := []byte(paramsString)
	go func() {
		promise.Resolve(handleUpdateConfig(bytes))
	}()
	return promise
}

// ---------------------------------------------------------------------------
// 数据查询
// ---------------------------------------------------------------------------

// getProxies：获取代理列表
func getProxies(env js.Env, this js.Value, args []js.Value) any {
	return handleGetProxies()
}

// getTraffic：获取实时流量
func getTraffic(env js.Env, this js.Value, args []js.Value) any {
	return handleGetTraffic(true)
}

// getTotalTraffic：获取总流量
func getTotalTraffic(env js.Env, this js.Value, args []js.Value) any {
	return handleGetTotalTraffic(true)
}

// resetTraffic：重置流量统计
func resetTraffic(env js.Env, this js.Value, args []js.Value) any {
	handleResetTraffic()
	return nil
}

// changeProxy：切换代理节点
func changeProxy(env js.Env, this js.Value, args []js.Value) any {
	paramsString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	promise := env.NewPromise()
	handleChangeProxy(paramsString, func(value string) {
		promise.Resolve(value)
	})
	return promise
}

// asyncTestDelay：延迟测试
func asyncTestDelay(env js.Env, this js.Value, args []js.Value) any {
	paramsString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	promise := env.NewPromise()
	handleAsyncTestDelay(paramsString, func(value string) {
		promise.Resolve(value)
	})
	return promise
}

// getConnections：获取连接列表
func getConnections(env js.Env, this js.Value, args []js.Value) any {
	return handleGetConnections()
}

// closeConnections：关闭全部连接
func closeConnections(env js.Env, this js.Value, args []js.Value) any {
	return handleCloseConnections()
}

// closeConnection：关闭指定连接
func closeConnection(env js.Env, this js.Value, args []js.Value) any {
	connectionId, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	return handleCloseConnection(connectionId)
}

// getExternalProviders：获取外部供应商
func getExternalProviders(env js.Env, this js.Value, args []js.Value) any {
	return handleGetExternalProviders()
}

// getVpnOptions：获取 VPN 选项
func getVpnOptions(env js.Env, this js.Value, args []js.Value) any {
	return GetVpnOptions()
}

// getVersion：获取内核版本
func getVersion(env js.Env, this js.Value, args []js.Value) any {
	return fmt.Sprintf(`{"version":%q}`, Version)
}

// getMemory：获取 Go 内存占用
func getMemory(env js.Env, this js.Value, args []js.Value) any {
	result := `{}`
	handleGetMemory(func(value string) {
		result = value
	})
	return result
}

func getRequestList(env js.Env, this js.Value, args []js.Value) any {
	return handleGetRequestList()
}

func clearRequestList(env js.Env, this js.Value, args []js.Value) any {
	handleClearRequestList()
	return nil
}

// setState：设置状态（TUN IP 等）
func setState(env js.Env, this js.Value, args []js.Value) any {
	paramsString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	_ = json.Unmarshal([]byte(paramsString), state.CurrentState)
	return nil
}

// setMode：切换 mihomo 的 rule/global/direct 运行模式
func setMode(env js.Env, this js.Value, args []js.Value) any {
	modeString, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	mode, ok := tunnel.ModeMapping[strings.ToLower(modeString)]
	if !ok {
		return false
	}
	tunnel.SetMode(mode)
	return true
}

// setMixedPort：更新 HTTP/SOCKS5 混合代理端口
func setMixedPort(env js.Env, this js.Value, args []js.Value) any {
	port, _ := napi.GetValueInt32(env.Env, args[0].Value)
	if port < 1024 || port > 65535 {
		return false
	}
	listener.ReCreateMixed(int(port), tunnel.Tunnel)
	return true
}

// ---------------------------------------------------------------------------
// 日志
// ---------------------------------------------------------------------------

// startLog：注册日志回调
func startLog(env js.Env, this js.Value, args []js.Value) any {
	tsfn := env.CreateThreadsafeFunction(args[0], "startLog")
	handleStartLog(func(value string) {
		tsfn.Call(env.ValueOf("startLog"), env.ValueOf(value))
	})
	return nil
}

// stopLog：停止日志回调
func stopLog(env js.Env, this js.Value, args []js.Value) any {
	handleStopLog()
	return nil
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

// startIpc：启动 Unix socket RPC 服务
func startIpc(env js.Env, this js.Value, args []js.Value) any {
	path, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	go startIpcProxy(path)
	return env.ValueOf("")
}

// updateDns：更新系统 DNS
func updateDns(env js.Env, this js.Value, args []js.Value) any {
	dnsList, _ := napi.GetValueStringUtf8(env.Env, args[0].Value)
	promise := env.NewPromise()
	go func() {
		log.Infoln("[DNS] updateDns %s", dnsList)
		state.CurrentState.SystemDns = strings.TrimSpace(dnsList)
		profileID := state.CurrentState.CurrentProfileName
		if profileID != "" {
			raw := getRawConfigWithId(profileID)
			if raw == nil {
				promise.Reject("当前配置不存在")
				return
			}
			if err := applyConfig(decorationConfig(profileID, *raw)); err != nil {
				promise.Reject(err.Error())
				return
			}
		}
		resolver.ClearCache()
		resolver.ResetConnection()
		promise.Resolve(nil)
	}()
	return promise
}

// ---------------------------------------------------------------------------
// 模块注册
// ---------------------------------------------------------------------------

func init() {
	entry.Export("initClash", js.AsCallback(initClash))
	entry.Export("startTun", js.AsCallback(startTun))
	entry.Export("stopTun", js.AsCallback(stopTun))
	entry.Export("forceGc", js.AsCallback(forceGc))
	entry.Export("shutdownClash", js.AsCallback(shutdownClash))
	entry.Export("loadConfig", js.AsCallback(loadConfig))
	entry.Export("validateConfig", js.AsCallback(validateConfig))
	entry.Export("updateConfig", js.AsCallback(updateConfig))
	entry.Export("getTraffic", js.AsCallback(getTraffic))
	entry.Export("getTotalTraffic", js.AsCallback(getTotalTraffic))
	entry.Export("resetTraffic", js.AsCallback(resetTraffic))
	entry.Export("getProxies", js.AsCallback(getProxies))
	entry.Export("changeProxy", js.AsCallback(changeProxy))
	entry.Export("asyncTestDelay", js.AsCallback(asyncTestDelay))
	entry.Export("getConnections", js.AsCallback(getConnections))
	entry.Export("closeConnections", js.AsCallback(closeConnections))
	entry.Export("closeConnection", js.AsCallback(closeConnection))
	entry.Export("getExternalProviders", js.AsCallback(getExternalProviders))
	entry.Export("getVpnOptions", js.AsCallback(getVpnOptions))
	entry.Export("getVersion", js.AsCallback(getVersion))
	entry.Export("getMemory", js.AsCallback(getMemory))
	entry.Export("getRequestList", js.AsCallback(getRequestList))
	entry.Export("clearRequestList", js.AsCallback(clearRequestList))
	entry.Export("setState", js.AsCallback(setState))
	entry.Export("setMode", js.AsCallback(setMode))
	entry.Export("setMixedPort", js.AsCallback(setMixedPort))
	entry.Export("updateDns", js.AsCallback(updateDns))
	entry.Export("startLog", js.AsCallback(startLog))
	entry.Export("stopLog", js.AsCallback(stopLog))
	entry.Export("startIpc", js.AsCallback(startIpc))
}

func main() {}
