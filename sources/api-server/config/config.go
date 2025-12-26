// NOTE: This code is typically cloned from GitHub repository
// In production, source code should be in repo/api-server/ directory
// Example: git clone https://github.com/org/api-server.git repo/api-server
package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds all configuration for the API server
// All values are read from environment variables loaded by systemd via EnvironmentFile
type Config struct {
	// Service configuration
	Port          string // GO_PORT - Port to listen on (e.g., "8080")
	ServiceName   string // GO_SERVICE_NAME - Name of the service (e.g., "user-api")
	EndpointPath  string // GO_ENDPOINT_PATH - Endpoint path (e.g., "/user")
	EndpointName  string // GO_ENDPOINT_NAME - Endpoint name (e.g., "user")
	Env           string // GO_ENV - Environment (e.g., "production", "development")
	LoggerFile    string // LOGGER_FILE_NAME - Log file name

	// Redis configuration (from shared config)
	RedisAddr     string // REDIS_ADDR - Redis address (e.g., "localhost:6379")
	RedisPassword string // REDIS_PASSWORD - Redis password
	RedisDB       int    // REDIS_DB - Redis database number
	RedisUseSSL   bool   // REDIS_USE_SSL - Whether to use SSL for Redis
}

// Load reads configuration from environment variables
// Systemd loads .properties files via EnvironmentFile directive
// This function only reads from environment variables (no file loading)
func Load() (*Config, error) {
	cfg := &Config{
		Port:          getEnv("GO_PORT", "8080"),
		ServiceName:   getEnv("GO_SERVICE_NAME", ""),
		EndpointPath:  getEnv("GO_ENDPOINT_PATH", ""),
		EndpointName:  getEnv("GO_ENDPOINT_NAME", ""),
		Env:           getEnv("GO_ENV", "production"),
		LoggerFile:    getEnv("LOGGER_FILE_NAME", ""),
		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
		RedisDB:       getEnvAsInt("REDIS_DB", 0),
		RedisUseSSL:   getEnvAsBool("REDIS_USE_SSL", false),
	}

	// Validate required fields
	if cfg.ServiceName == "" {
		return nil, fmt.Errorf("GO_SERVICE_NAME is required")
	}
	if cfg.EndpointPath == "" {
		return nil, fmt.Errorf("GO_ENDPOINT_PATH is required")
	}
	if cfg.EndpointName == "" {
		return nil, fmt.Errorf("GO_ENDPOINT_NAME is required")
	}

	return cfg, nil
}

// getEnv retrieves an environment variable or returns a default value
func getEnv(key string, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists && value != "" {
		// Remove quotes if present (properties files may have quotes)
		if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
			return value[1 : len(value)-1]
		}
		return value
	}
	return defaultValue
}

// getEnvAsBool retrieves an environment variable as a boolean
func getEnvAsBool(key string, defaultValue bool) bool {
	valStr := getEnv(key, "")
	if valStr == "" {
		return defaultValue
	}
	if val, err := strconv.ParseBool(valStr); err == nil {
		return val
	}
	return defaultValue
}

// getEnvAsInt retrieves an environment variable as an integer
func getEnvAsInt(key string, defaultValue int) int {
	valStr := getEnv(key, "")
	if valStr == "" {
		return defaultValue
	}
	if val, err := strconv.Atoi(valStr); err == nil {
		return val
	}
	return defaultValue
}

