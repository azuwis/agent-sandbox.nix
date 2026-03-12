package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

func loadAllowlist(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var domains []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		domains = append(domains, strings.ToLower(line))
	}
	return domains, sc.Err()
}

func isAllowed(host string, allowlist []string) bool {
	host = strings.ToLower(host)
	for _, d := range allowlist {
		if host == d || strings.HasSuffix(host, "."+d) {
			return true
		}
	}
	return false
}

func hostOnly(addr string) string {
	h, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return h
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: sandbox-proxy <allowlist-file>")
		os.Exit(1)
	}
	allowlist, err := loadAllowlist(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "load allowlist:", err)
		os.Exit(1)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Fprintln(os.Stderr, "listen:", err)
		os.Exit(1)
	}
	fmt.Println(ln.Addr().(*net.TCPAddr).Port)
	os.Stdout.Sync()

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(conn, allowlist)
	}
}

func handle(conn net.Conn, allowlist []string) {
	defer conn.Close()
	br := bufio.NewReader(conn)
	req, err := http.ReadRequest(br)
	if err != nil {
		return
	}

	if req.Method == http.MethodConnect {
		host := hostOnly(req.Host)
		if !isAllowed(host, allowlist) {
			fmt.Fprintf(os.Stderr, "%s blocked: %s\n", time.Now().Format(time.RFC3339), req.Host)
			fmt.Fprintf(conn, "HTTP/1.1 403 Forbidden\r\n\r\n")
			return
		}
		upstream, err := net.Dial("tcp", req.Host)
		if err != nil {
			fmt.Fprintf(conn, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
			return
		}
		defer upstream.Close()
		fmt.Fprintf(conn, "HTTP/1.1 200 Connection Established\r\n\r\n")
		go io.Copy(upstream, conn)
		io.Copy(conn, upstream)
	} else {
		host := hostOnly(req.Host)
		if !isAllowed(host, allowlist) {
			fmt.Fprintf(os.Stderr, "%s blocked: %s\n", time.Now().Format(time.RFC3339), req.Host)
			fmt.Fprintf(conn, "HTTP/1.1 403 Forbidden\r\n\r\n")
			return
		}
		if req.URL.Host == "" {
			req.URL.Host = req.Host
		}
		if req.URL.Scheme == "" {
			req.URL.Scheme = "http"
		}
		resp, err := http.DefaultTransport.RoundTrip(req)
		if err != nil {
			fmt.Fprintf(conn, "HTTP/1.1 502 Bad Gateway\r\n\r\n")
			return
		}
		defer resp.Body.Close()
		resp.Write(conn)
	}
}
