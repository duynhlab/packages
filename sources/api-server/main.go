// NOTE: This code is typically cloned from GitHub repository
// In production, source code should be in repo/api-server/ directory
// Example: git clone https://github.com/org/api-server.git repo/api-server
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"api-server/config"
	"api-server/handlers"
)

func main() {
	// Load configuration from environment variables
	// Systemd loads .properties files via EnvironmentFile directive
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Create HTTP server
	mux := http.NewServeMux()

	// Health check endpoint
	mux.HandleFunc("/health", handlers.HealthHandler(cfg.ServiceName))

	// Main service endpoint
	mux.HandleFunc(cfg.EndpointPath, handlers.EndpointHandler(cfg.ServiceName, cfg.EndpointName))

	// Root endpoint - JSON response
	mux.HandleFunc("/", handlers.IndexHandler(cfg.ServiceName, cfg.EndpointPath, cfg.EndpointName))

	server := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: mux,
	}

	// Graceful shutdown handling
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		log.Println("Shutdown signal received, stopping server...")

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(ctx); err != nil {
			log.Printf("Server shutdown error: %v", err)
		} else {
			log.Println("Server stopped gracefully")
		}
	}()

	log.Printf("Starting %s server on :%s", cfg.ServiceName, cfg.Port)
	log.Printf("Environment: %s", cfg.Env)
	log.Printf("Endpoints available:")
	log.Printf("  GET /        - Root endpoint (JSON)")
	log.Printf("  GET /health  - Health check (JSON)")
	log.Printf("  GET %s    - %s endpoint (JSON)", cfg.EndpointPath, cfg.EndpointName)

	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

