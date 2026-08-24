//go:build (ohos || android) && cgo

// tun.go：TUN 隧道启动
// 使用 mihomo 的 sing_tun 监听系统 VPN 虚拟网卡的文件描述符（fd）
package tun

import (
	"clashh/core/state"
	"net"
	"net/netip"

	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// Props：TUN 启动参数（由 UI 通过 JSON 传入）
type Props struct {
	Fd       int    `json:"fd"`
	Gateway  string `json:"gateway"`
	Gateway6 string `json:"gateway6"`
	Portal   string `json:"portal"`
	Portal6  string `json:"portal6"`
	Dns      string `json:"dns"`
	Dns6     string `json:"dns6"`
}

// Start：启动 TUN 隧道
// fd：系统 VPN 虚拟网卡的文件描述符
// device：网卡名
// stack：协议栈（system/gvisor/mixed）
// dnsHijack：DNS 劫持地址列表
func Start(fd int, device string, stack constant.TUNStack, dnsHijack []string) (*sing_tun.Listener, error) {
	var prefix4 []netip.Prefix
	inet4Prefix4, err := netip.ParsePrefix(state.CurrentState.TunIp)
	if err == nil {
		prefix4 = append(prefix4, inet4Prefix4)
	} else {
		tempPrefix4, err := netip.ParsePrefix(state.DefaultIpv4Address)
		if err != nil {
			log.Errorln("startTUN 解析 IPv4 地址失败: %v", err)
			return nil, err
		}
		prefix4 = append(prefix4, tempPrefix4)
	}

	var prefix6 []netip.Prefix
	if state.CurrentState.Ipv6 {
		tempPrefix6, err := netip.ParsePrefix(state.DefaultIpv6Address)
		if err != nil {
			log.Errorln("startTUN 解析 IPv6 地址失败: %v", err)
			return nil, err
		}
		prefix6 = append(prefix6, tempPrefix6)
	}

	if len(dnsHijack) == 0 {
		dnsHijack = append(dnsHijack, net.JoinHostPort(state.GetDnsServerAddress(), "53"))
	}

	options := LC.Tun{
		Enable:              true,
		Device:              device,
		Stack:               stack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false, // 路由由鸿蒙系统 VPN 管理
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		Inet6Address:        prefix6,
		MTU:                 1400,
		FileDescriptor:      fd, // 直接使用系统 VPN 的 fd
	}

	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		log.Errorln("startTUN 启动失败: %v", err)
		return nil, err
	}
	return listener, nil
}
