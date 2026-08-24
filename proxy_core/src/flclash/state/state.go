//go:build (ohos || android) && cgo

// state.go：内核运行时状态
package state

// 默认 TUN 地址段（与鸿蒙 VPN 配置保持一致）
var DefaultIpv4Address = "172.19.0.1/30"
var DefaultDnsAddress = "172.19.0.2"
var DefaultIpv6Address = "fdfe:dcba:9876::1/126"

// VpnOptions：鸿蒙 VPN 选项（UI 传入）
type VpnOptions struct {
	Enable           bool           `json:"enable"`
	AccessControl    *AccessControl `json:"accessControl"`
	AllowBypass      bool           `json:"allowBypass"`
	SystemProxy      bool           `json:"systemProxy"`
	BypassDomain     []string       `json:"bypassDomain"`
	RouteAddress     []string       `json:"routeAddress"`
	Ipv4Address      string         `json:"ipv4Address"`
	Ipv6Address      string         `json:"ipv6Address"`
	DnsServerAddress string         `json:"dnsServerAddress"`
	Mtu              int            `json:"mtu"`
}

// AccessControl：应用分流控制
type AccessControl struct {
	Mode              string   `json:"mode"`
	AcceptList        []string `json:"acceptList"`
	RejectList        []string `json:"rejectList"`
	IsFilterSystemApp bool     `json:"isFilterSystemApp"`
}

// VpnRawOptions：VPN 原始选项（UI 通过 setState 传入）
type VpnRawOptions struct {
	Enable        bool           `json:"enable"`
	AccessControl *AccessControl `json:"accessControl"`
	AllowBypass   bool           `json:"allowBypass"`
	SystemProxy   bool           `json:"systemProxy"`
	RouteAddress  []string       `json:"routeAddress"`
	Ipv6          bool           `json:"ipv6"`
	BypassDomain  []string       `json:"bypassDomain"`
	Mtu           int            `json:"mtu"`
	OverrideDns   bool           `json:"overrideDns"`
}

// State：内核全局状态
type State struct {
	TunIp     string `json:"tunIp"`
	SystemDns string `json:"dns"`
	VpnRawOptions
	CurrentProfileName string `json:"currentProfileName"`
}

// CurrentState：当前状态实例
var CurrentState = &State{}

// GetIpv6Address：获取 IPv6 地址（未启用返回空串）
func GetIpv6Address() string {
	if CurrentState.Ipv6 {
		return DefaultIpv6Address
	}
	return ""
}

// GetDnsServerAddress：获取 DNS 服务器地址
func GetDnsServerAddress() string {
	return DefaultDnsAddress
}
