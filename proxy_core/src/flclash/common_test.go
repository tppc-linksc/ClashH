package main

import (
	"reflect"
	"testing"
)

func TestParseDnsServers(t *testing.T) {
	want := []string{"1.1.1.1", "https://dns.example/dns-query"}
	got := parseDnsServers(" 1.1.1.1, , https://dns.example/dns-query ")
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("parseDnsServers() = %#v, want %#v", got, want)
	}
}

func TestParseDnsServersEmpty(t *testing.T) {
	if got := parseDnsServers(" , "); len(got) != 0 {
		t.Fatalf("parseDnsServers() = %#v, want empty", got)
	}
}
