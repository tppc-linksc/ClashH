// common.go：公共工具函数
package main

import (
	"clashh/core/state"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// homeDir：应用数据目录（全局）
var homeDir = ""

// GetHomeDir：获取应用数据目录
func GetHomeDir() string {
	return homeDir
}

// readFile：读取文件
func readFile(path string) ([]byte, error) {
	return os.ReadFile(path)
}

// getProfilePath：获取配置文件的路径
func getProfilePath(id string) string {
	return filepath.Join(homeDir, "profiles", id+".yaml")
}

// getRawConfigWithId：读取指定配置的 RawConfig
func getRawConfigWithId(id string) *config.RawConfig {
	path := getProfilePath(id)
	bytes, err := readFile(path)
	if err != nil {
		log.Errorln("读取配置失败: %v", err)
		return nil
	}
	raw, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		log.Errorln("解析配置失败: %v", err)
		return nil
	}
	return raw
}

// getExternalProvidersRaw：获取全部外部供应商
func getExternalProvidersRaw() map[string]P.ProxyProvider {
	return tunnel.Providers()
}

// toExternalProvider：转换为对外供应商结构
// 注：ProxyProvider 接口不含 UpdatedAt/SubscriptionInfo，
// 需要时通过类型断言获取（详见 mihomo providerForApi）
func toExternalProvider(p P.ProxyProvider) (*ExternalProvider, error) {
	proxies := []string{}
	for _, proxy := range p.Proxies() {
		proxies = append(proxies, proxy.Name())
	}

	// 供应商类型（ProxyProvider 只有 Proxy 类型）
	providerType := "proxy"
	if p.Type() == P.Rule {
		providerType = "rule"
	}

	vehicleType := ""
	switch p.VehicleType() {
	case P.File:
		vehicleType = "File"
	case P.HTTP:
		vehicleType = "HTTP"
	case P.Compatible:
		vehicleType = "Compatible"
	case P.Inline:
		vehicleType = "Inline"
	}

	return &ExternalProvider{
		Name:        p.Name(),
		Type:        providerType,
		Proxies:     proxies,
		VehicleType: vehicleType,
	}, nil
}

// decorationConfig：装饰配置（覆盖 TUN/DNS 等运行时参数）
func decorationConfig(profileId string, cfg config.RawConfig) *config.RawConfig {
	// 覆盖 TUN 配置：路由由鸿蒙系统管理，关闭 auto-route
	cfg.Tun.Enable = true
	cfg.Tun.AutoRoute = false
	cfg.Tun.AutoDetectInterface = false
	// 用户填写自定义上游 DNS 时覆盖订阅；留空则保留订阅自身的 DNS 配置。
	if servers := parseDnsServers(state.CurrentState.SystemDns); len(servers) > 0 {
		cfg.DNS.Enable = true
		cfg.DNS.NameServer = servers
	}
	return &cfg
}

// applyConfig：应用配置到 mihomo 内核
func applyConfig(rawConfig *config.RawConfig) error {
	// 确保 homeDir 存在
	if err := os.MkdirAll(homeDir, 0o755); err != nil {
		return err
	}

	cfg, err := config.ParseRawConfig(rawConfig)
	if err != nil {
		return err
	}

	executor.ApplyConfig(cfg, true)
	return nil
}

// isInit：内核是否已初始化
var isInit = false

// initHomeDir：初始化 homeDir
func initHomeDir(path string) {
	homeDir = path
	_ = os.MkdirAll(filepath.Join(homeDir, "profiles"), 0o755)
	_ = os.MkdirAll(filepath.Join(homeDir, "geo"), 0o755)
	C.SetHomeDir(homeDir)
	C.SetConfig(filepath.Join(homeDir, "config.yaml"))
}

// 编译期使用 outbound，防止未引用
var _ = outbound.NewDirect
var _ = tunnel.Tunnel
var _ = json.Marshal
