// NOTE: This code is typically cloned from GitHub repository
// In production, source code should be in repo/api-server/ directory
package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

// IndexHandler handles the root path and returns JSON response
func IndexHandler(serviceName string, endpointPath string, endpointName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		response := map[string]interface{}{
			"service":      serviceName,
			"status":       "ok",
			"timestamp":    time.Now().Format(time.RFC3339),
			"endpoint":     endpointPath,
			"endpointName": endpointName,
			"message":      "Welcome to " + serviceName,
		}

		jsonData, err := json.Marshal(response)
		if err != nil {
			log.Printf("Error marshaling index response: %v", err)
			http.Error(w, `{"status":"error","message":"internal error"}`, http.StatusInternalServerError)
			return
		}

		w.Write(jsonData)
		log.Printf("Root endpoint requested from %s", r.RemoteAddr)
	}
}

