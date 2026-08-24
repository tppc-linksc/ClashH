// constant.go：Go 侧参数结构定义
package main

import (
	"time"

	"github.com/metacubex/mihomo/config"
)

// ConfigExtendedParams：配置增强参数（来自 UI）
type ConfigExtendedParams struct {
	IsPatch      bool              `json:"is-patch"`
	IsCompatible bool              `json:"is-compatible"`
	SelectedMap  map[string]string `json:"selected-map"`
	TestURL      *string           `json:"test-url"`
	OverrideDns  bool              `json:"override-dns"`
}

// GenerateConfigParams：生成配置参数
type GenerateConfigParams struct {
	ProfileId string               `json:"profile-id"`
	Config    config.RawConfig     `json:"config"`
	Params    ConfigExtendedParams `json:"params"`
}

// ChangeProxyParams：切换节点参数
type ChangeProxyParams struct {
	GroupName *string `json:"group-name"`
	ProxyName *string `json:"proxy-name"`
}

// TestDelayParams：单节点测速参数
type TestDelayParams struct {
	ProxyName string `json:"proxy-name"`
	Timeout   int64  `json:"timeout"`
	TestUrl   string `json:"test-url"`
}

// TestDelayBatchParams：批量测速参数
type TestDelayBatchParams struct {
	ProxyNames []string `json:"proxy-names"`
	Timeout    int64    `json:"timeout"`
	TestURL    string   `json:"test-url"`
}

// Message：推送消息（日志/事件）
type Message struct {
	Type    string `json:"type"`
	Payload string `json:"payload"`
}

// ExternalProvider：外部供应商（订阅）
type ExternalProvider struct {
	Name             string            `json:"name"`
	Type             string            `json:"type"`
	Proxies          []string          `json:"proxies"`
	VehicleType      string            `json:"vehicleType"`
	UpdatedAt        string            `json:"updatedAt"`
	SubscriptionInfo *SubscriptionInfo `json:"subscriptionInfo,omitempty"`
}

// SubscriptionInfo：订阅用户信息
type SubscriptionInfo struct {
	Upload   int64 `json:"upload"`
	Download int64 `json:"download"`
	Total    int64 `json:"total"`
	Expire   int64 `json:"expire"`
}

// ExternalProviders：供应商列表（支持排序）
type ExternalProviders []ExternalProvider

func (a ExternalProviders) Len() int           { return len(a) }
func (a ExternalProviders) Less(i, j int) bool { return a[i].Name < a[j].Name }
func (a ExternalProviders) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }

// DelayHistory：延迟历史（来自 mihomo）
type DelayHistory struct {
	Time  time.Time `json:"time"`
	Delay int       `json:"delay"`
}

// ProxyItem：代理节点（来自 mihomo）
type ProxyItem struct {
	Name         string         `json:"name"`
	Type         string         `json:"type"`
	Alive        bool           `json:"alive"`
	UDP          bool           `json:"udp"`
	XUDP         bool           `json:"xudp"`
	TFO          bool           `json:"tfo"`
	MPTCP        bool           `json:"mptcp"`
	SMUX         bool           `json:"smux"`
	History      []DelayHistory `json:"history"`
	Now          string         `json:"now,omitempty"`
	All          []string       `json:"all,omitempty"`
	Hidden       bool           `json:"hidden,omitempty"`
	Icon         string         `json:"icon,omitempty"`
	TestUrl      string         `json:"testUrl,omitempty"`
	ProviderName string         `json:"providerName,omitempty"`
}

// Version 由 build.sh 根据仓库内 mihomo 提交在链接阶段注入。
var Version = "development"
