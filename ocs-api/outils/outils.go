package outils

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

// Utilities for ocs-api

var IsVerbose bool

// A "subclass" of error that also contains the http code that should be sent to the client
type HttpError struct {
	Code int
	Err  error
}

func NewHttpError(code int, errStr string) *HttpError {
	return &HttpError{Code: code, Err: errors.New(errStr)}
}

func (e *HttpError) Error() string {
	return e.Err.Error()
}

// Verify that the request content type is json
func IsValidPostJson(r *http.Request) *HttpError {
	val, ok := r.Header["Content-Type"]

	if !ok || len(val) == 0 || val[0] != "application/json" {
		return NewHttpError(http.StatusBadRequest, "Error: content-type must be application/json)")
	}
	return nil
}

// Parse the json string into the given struct
func ParseJsonString(jsonBytes []byte, bodyStruct interface{}) *HttpError {
	err := json.Unmarshal(jsonBytes, bodyStruct)
	if err != nil {
		return NewHttpError(http.StatusBadRequest, "Error parsing request body json bytes: "+err.Error())
	}
	return nil
}

// Parse the request json body into the given struct
func ReadJsonBody(r *http.Request, bodyStruct interface{}) *HttpError {
	decoder := json.NewDecoder(r.Body)
	err := decoder.Decode(bodyStruct)
	if err != nil {
		return NewHttpError(http.StatusBadRequest, "Error parsing request body: "+err.Error())
	}
	return nil
}

// Response to the client with this code and body
func WriteJsonResponse(httpCode int, w http.ResponseWriter, bodyStruct interface{}) {
	dataJson, err := json.Marshal(bodyStruct)
	if err != nil {
		http.Error(w, "Internal Server Error (could not encode json response)", http.StatusInternalServerError)
		return
	}
	WriteResponse(httpCode, w, dataJson)
}

// Respond to the client with this code and body
func WriteResponse(httpCode int, w http.ResponseWriter, bodyBytes []byte) {
	w.WriteHeader(httpCode) // seems like this has to be before writing the body
	w.Header().Set("Content-Type", "application/json")
	_, err := w.Write(bodyBytes)
	if err != nil {
		Error(err.Error())
	}
}

// Generate a random node token
func GenerateNodeToken() (string, *HttpError) {
	bytes := make([]byte, 22) // 44 hex chars
	_, err := rand.Read(bytes)
	if err != nil {
		return "", NewHttpError(http.StatusInternalServerError, "Error creating random bytes for node token: "+err.Error())
	}
	return hex.EncodeToString(bytes), nil
}

// Convert a space-separated string into a null separated string (with extra null at end)
func MakeExecCmd(execString string) string {
	returnStr := ""
	for _, w := range strings.Fields(execString) {
		returnStr += w + "\x00"
	}
	return returnStr + "\x00"
}

// Initialize the verbose setting
func SetVerbose() {
	v := GetEnvVarWithDefault("VERBOSE", "false")
	if v == "1" || strings.ToLower(v) == "true" {
		IsVerbose = true
	} else {
		IsVerbose = false
	}
}

// Print error msg to stderr
func Verbose(msg string, args ...interface{}) {
	if !IsVerbose {
		return
	}
	if !strings.HasSuffix(msg, "\n") {
		msg += "\n"
	}
	fmt.Printf("Verbose: "+msg, args...)
}

// Print error msg to stderr
func Error(msg string, args ...interface{}) {
	if !strings.HasSuffix(msg, "\n") {
		msg += "\n"
	}
	l := log.New(os.Stderr, "", 0)
	l.Printf("Error: "+msg, args...)
}

// Print error msg to stderr and exit with the specified code
func Fatal(exitCode int, msg string, args ...interface{}) {
	Error(msg, args...)
	os.Exit(exitCode)
}

// Get this environment variable or use this default
func GetEnvVarWithDefault(envVarName, defaultValue string) string {
	envVarValue := os.Getenv(envVarName)
	if envVarValue == "" {
		return defaultValue
	}
	return envVarValue
}

// Returns true if this env var is set
func IsEnvVarSet(envVarName string) bool {
	return os.Getenv(envVarName) != ""
}

// Returns true if this file or dir exists
func PathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// Download a file from a web site (that doesn't require authentication)
func DownloadFile(url, fileName string, perm os.FileMode) error {
	// Set up the request
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Create the file
	newFile, err := os.Create(fileName)
	if err != nil {
		return err
	}
	defer newFile.Close()
	if err := newFile.Chmod(perm); err != nil {
		return err
	}

	// Write the request body to the file. This streams the content straight from the request to the file, so works for large files
	_, err = io.Copy(newFile, resp.Body)
	return err
}
