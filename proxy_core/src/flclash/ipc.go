// ipc.go：Unix socket RPC 服务
// 提供第二个通信通道：除 NAPI 直调外，也支持 socket 模式（调试/解耦）
package main

import (
	"clashh/core/state"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
)

// ClashRpcType：RPC 方法枚举（与 ArkTS 侧 RpcMethod 一致）
type ClashRpcType int

const (
	QueryTrafficNow ClashRpcType = iota
	QueryTunnelState
	QueryTrafficTotal
	QueryProxyGroup
	QueryProviders
	ChangeProxy
	HealthCheck
	UpdateProvider
	UploadProvider
	QueryConnections
	CloseConnection
	ClearConnections
	Load
	StartClash
	StopClash
	ValidConfig
	Reset
	GetCountryCode
	UpdateGeoData
	RegisterOnMessage
	GetRequestList
	ClearRequestList
	SetLogObserver
	StopLogObserver
	VpnOptions
	SetOptionState
	GetVpnRunTime
	VpnConfigInited
	SetNetInterfaces
	DownloadConfig
	SetSystemDns
	HealthCheckAll
	HealthCheckBatch
	GetVersion
	GetMemory
)

// RpcRequest：RPC 请求
type RpcRequest struct {
	Key    int          `json:"key"`
	Method ClashRpcType `json:"method"`
	Params []any        `json:"params"`
}

// RpcResult：RPC 响应
type RpcResult struct {
	Key    int          `json:"key"`
	Method ClashRpcType `json:"method"`
	Result string       `json:"result"`
	Error  string       `json:"error"`
}

// fileExists：文件是否存在
func fileExists(filename string) bool {
	_, err := os.Stat(filename)
	return !os.IsNotExist(err)
}

// startIpcProxy：启动 Unix socket RPC 服务
func startIpcProxy(path string) {
	// 清理残留 socket 文件
	if fileExists(path) {
		if err := os.Remove(path); err != nil {
			log.Println("ipc_go 清理失败:", err)
			return
		}
	}

	listener, err := net.Listen("unix", path)
	if err != nil {
		log.Println("ipc_go 监听失败:", err)
		return
	}
	defer listener.Close()
	log.Println("ipc_go 服务已启动:", path)

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println("ipc_go Accept 错误:", err)
			continue
		}
		go handleConnection(conn)
	}
}

// handleConnection：处理单个连接
func handleConnection(conn net.Conn) {
	defer conn.Close()

	buffer := make([]byte, 10240)
	n, err := conn.Read(buffer)
	if err != nil {
		log.Println("ipc_go 读取失败:", err)
		return
	}

	request := RpcRequest{}
	if err := json.Unmarshal(buffer[:n], &request); err != nil {
		log.Println("ipc_go 解析失败:", err)
		return
	}

	handleRemoteRequest(request, func(rr RpcResult) {
		res, _ := json.Marshal(rr)
		_, _ = conn.Write(append(res, []byte("EOF")...))
	})
}

// handleRemoteRequest：分发 RPC 请求
func handleRemoteRequest(request RpcRequest, fn func(RpcResult)) {
	ret := RpcResult{
		Key:    request.Key,
		Method: request.Method,
	}

	switch request.Method {
	case QueryTrafficNow:
		ret.Result = handleGetTraffic(true)
	case QueryTrafficTotal:
		ret.Result = handleGetTotalTraffic(true)
	case QueryProxyGroup:
		ret.Result = handleGetProxies()
	case QueryConnections:
		ret.Result = handleGetConnections()
	case CloseConnection:
		if len(request.Params) > 0 {
			id, _ := request.Params[0].(string)
			handleCloseConnection(id)
		}
		ret.Result = `{"status":"ok"}`
	case ClearConnections:
		handleCloseConnections()
		ret.Result = `{"status":"ok"}`
	case ChangeProxy:
		if len(request.Params) >= 2 {
			group, _ := request.Params[0].(string)
			proxy, _ := request.Params[1].(string)
			handleChangeProxy(fmt.Sprintf(`{"group-name":%q,"proxy-name":%q}`, group, proxy), func(v string) {
				ret.Result = v
				fn(ret)
			})
			return
		}
		ret.Result = `{"status":"invalid"}`
	case HealthCheck:
		if len(request.Params) > 0 {
			name, _ := request.Params[0].(string)
			handleAsyncTestDelay(fmt.Sprintf(`{"proxy-name":%q}`, name), func(v string) {
				ret.Result = v
				fn(ret)
			})
			return
		}
		ret.Result = `{"delay":-1}`
	case QueryProviders:
		ret.Result = handleGetExternalProviders()
	case VpnOptions:
		ret.Result = GetVpnOptions()
	case ValidConfig:
		if len(request.Params) > 0 {
			content, _ := request.Params[0].(string)
			ret.Result = handleValidateConfig([]byte(content))
		}
	case StartClash:
		ret.Result = `{"status":"ok"}`
	case StopClash:
		handleShutdown()
		ret.Result = `{"status":"ok"}`
	case Load:
		if len(request.Params) > 0 {
			profileId, _ := request.Params[0].(string)
			raw := getRawConfigWithId(profileId)
			if raw != nil {
				if err := applyConfig(decorationConfig(profileId, *raw)); err == nil {
					state.CurrentState.CurrentProfileName = profileId
					ret.Result = `{"status":"ok"}`
				} else {
					ret.Error = err.Error()
				}
			} else {
				ret.Error = "配置不存在"
			}
		}
	case GetVersion:
		ret.Result = fmt.Sprintf(`{"version":%q}`, Version)
	case SetOptionState:
		if len(request.Params) > 0 {
			content, _ := request.Params[0].(string)
			_ = json.Unmarshal([]byte(content), state.CurrentState)
		}
		ret.Result = `{"status":"ok"}`
	case SetSystemDns:
		ret.Result = `{"status":"ok"}`
	case GetMemory:
		handleGetMemory(func(v string) {
			ret.Result = v
			fn(ret)
		})
		return
	default:
		ret.Error = "不支持的方法: " + fmt.Sprint(request.Method)
	}
	fn(ret)
}
