//go:build ohos && cgo

// lib_linux.go：OHOS 平台实现
// 提供 Fd 结构、TUN 生命周期管理与进程映射
package main

import (
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// Fd：TUN 文件描述符信息
type Fd struct {
	Id    int64 `json:"id"`
	Value int64 `json:"value"`
}

// ProcessMap：进程映射（uid -> 进程名）
type ProcessMap struct {
	m sync.Map
}

func (cm *ProcessMap) Store(key int64, value string) {
	cm.m.Store(key, value)
}

func (cm *ProcessMap) Load(key int64) (string, bool) {
	value, ok := cm.m.Load(key)
	if !ok || value == nil {
		return "", false
	}
	return value.(string), true
}

func (cm *ProcessMap) Delete(key int64) {
	cm.m.Delete(key)
}

// processMap：全局进程映射
var processMap ProcessMap

// fdCounter：fd 计数器
var fdCounter int64

// SetProcessMap：设置进程映射（JSON 字符串）
func SetProcessMap(params string) any {
	var uidMap map[string]string
	if err := json.Unmarshal([]byte(params), &uidMap); err != nil {
		return nil
	}
	// 清理旧映射
	processMap.m.Range(func(k, v any) bool {
		processMap.Delete(k.(int64))
		return true
	})
	for uidStr, processName := range uidMap {
		var uid int64
		fmt.Sscan(uidStr, &uid)
		processMap.Store(uid, processName)
	}
	return nil
}

// keepalive：内核保活（防止后台被回收后无法恢复）
var keepaliveStop chan struct{}
var keepaliveOnce sync.Once

// StartKeepalive：启动保活协程
func StartKeepalive() {
	keepaliveOnce.Do(func() {
		keepaliveStop = make(chan struct{})
		go func() {
			ticker := time.NewTicker(30 * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-ticker.C:
					// 周期性触发 GC，保持 Go 运行时活跃
					atomic.AddInt64(&fdCounter, 0)
				case <-keepaliveStop:
					return
				}
			}
		}()
	})
}

// StopKeepalive：停止保活协程
func StopKeepalive() {
	if keepaliveStop != nil {
		close(keepaliveStop)
		keepaliveStop = nil
	}
}
