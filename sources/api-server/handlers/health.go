// NOTE: This code is typically cloned from GitHub repository
// In production, source code should be in repo/api-server/ directory
package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

// HealthHandler handles health check requests
func HealthHandler(serviceName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		response := map[string]string{
			"status":    "ok",
			"service":   serviceName,
			"timestamp": time.Now().Format(time.RFC3339),
		}

		jsonData, err := json.Marshal(response)
		if err != nil {
			log.Printf("Error marshaling health response: %v", err)
			fmt.Fprint(w, `{"status":"error","message":"internal error"}`)
			return
		}

		fmt.Fprint(w, string(jsonData))
		log.Printf("Health check requested from %s", r.RemoteAddr)
	}
}

