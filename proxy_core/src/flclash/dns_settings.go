package main

import "strings"

func parseDnsServers(value string) []string {
	parts := strings.Split(value, ",")
	servers := make([]string, 0, len(parts))
	for _, part := range parts {
		if server := strings.TrimSpace(part); server != "" {
			servers = append(servers, server)
		}
	}
	return servers
}
