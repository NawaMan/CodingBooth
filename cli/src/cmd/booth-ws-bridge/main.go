// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// booth-ws-bridge: WebSocket-to-TCP bridge for CodingBooth expose tunnels.
//
// Listens for WebSocket connections on a local port and forwards each
// connection bidirectionally to a TCP target (e.g., a service running
// inside the container). Binary WebSocket frames are used for the data.
//
// Usage:
//
//	booth-ws-bridge -listen :20080 -target 127.0.0.1:8080
package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func main() {
	listenAddr := flag.String("listen", "", "Address to listen on (e.g., :20080)")
	targetAddr := flag.String("target", "", "TCP target to forward to (e.g., 127.0.0.1:8080)")
	flag.Parse()

	if *listenAddr == "" || *targetAddr == "" {
		fmt.Fprintf(os.Stderr, "Usage: booth-ws-bridge -listen <addr> -target <addr>\n")
		os.Exit(1)
	}

	handler := &bridgeHandler{target: *targetAddr}

	server := &http.Server{
		Addr:    *listenAddr,
		Handler: handler,
	}

	// Graceful shutdown on SIGTERM/SIGINT
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
		<-sigCh
		server.Close()
	}()

	log.Printf("booth-ws-bridge: %s -> %s", *listenAddr, *targetAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("listen error: %v", err)
	}
}

type bridgeHandler struct {
	target string
}

func (h *bridgeHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade error: %v", err)
		return
	}
	defer ws.Close()

	tcp, err := net.Dial("tcp", h.target)
	if err != nil {
		log.Printf("dial %s error: %v", h.target, err)
		ws.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "cannot connect to target"))
		return
	}
	defer tcp.Close()

	// WS -> TCP
	done := make(chan struct{}, 2)
	go func() {
		defer func() { done <- struct{}{} }()
		for {
			_, reader, err := ws.NextReader()
			if err != nil {
				return
			}
			if _, err := io.Copy(tcp, reader); err != nil {
				return
			}
		}
	}()

	// TCP -> WS
	go func() {
		defer func() { done <- struct{}{} }()
		buf := make([]byte, 32*1024)
		for {
			n, err := tcp.Read(buf)
			if n > 0 {
				if werr := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()

	<-done
}
