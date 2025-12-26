// NOTE: This code is typically cloned from GitHub repository
// In production, source code should be in repo/api-server/ directory
package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

// EndpointHandler handles the main service endpoint
func EndpointHandler(serviceName string, endpointName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		response := map[string]string{
			"message": fmt.Sprintf("%s - %s service!", serviceName, endpointName),
			"service": serviceName,
		}

		jsonData, err := json.Marshal(response)
		if err != nil {
			log.Printf("Error marshaling endpoint response: %v", err)
			fmt.Fprint(w, `{"status":"error","message":"internal error"}`)
			return
		}

		fmt.Fprint(w, string(jsonData))
		log.Printf("%s endpoint requested from %s", endpointName, r.RemoteAddr)
	}
}

