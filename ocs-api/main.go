package main

import (
	//"encoding/hex"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/google/uuid"
)

/*
REST API server to configure the SDO OCS (Owner Companion Service) DB files for import a voucher and setting up horizon files for device boot.
*/

// These global vars are necessary because the handler functions are not given any context
var IsVerbose bool

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: ./ocs-api <port> <ocs-db-path>")
		os.Exit(1)
	}

	// Process cmd line args and env vars
	port := os.Args[1]
	ocsDbDir := os.Args[2]
	SetVerbose()

	//http.HandleFunc("/", rootHandler)
	http.HandleFunc("/api/", apiHandler)

	Verbose("Listening on port %s and using ocs db %s", port, ocsDbDir)
	log.Fatal(http.ListenAndServe(":"+port, nil))
} // end of main

// API route dispatcher
func apiHandler(w http.ResponseWriter, r *http.Request) {
	//Verbose("Handling %s ...", r.URL.Path)
	if r.Method == "GET" && r.URL.Path == "/api/voucher" {
		getVoucherHandler(w, r)
	} else if r.Method == "POST" && r.URL.Path == "/api/voucher" {
		postVoucherHandler(w, r)
	} else {
		http.Error(w, "Route "+r.URL.Path+" not found", http.StatusNotFound)
	}
}

// Route Handlers --------------------------------------------------------------------------------------------------

// Called for GET /api/voucher route
func getVoucherHandler(w http.ResponseWriter, r *http.Request) {
	Verbose("GET /api/voucher ...")
	WriteJsonResponse(http.StatusOK, w, map[string]interface{}{
		"msg": "here",
	})
}

// Called for POST /api/voucher route
func postVoucherHandler(w http.ResponseWriter, r *http.Request) {
	Verbose("POST /api/voucher ...")

	if err := IsValidPostJson(r); err != nil {
		http.Error(w, err.Error(), err.Code)
		return
	}

	type OhStruct struct {
		Guid []byte `json:"g"` // making it type []byte will automatically base64 decode the json value
	}
	type Voucher struct {
		Oh OhStruct `json:"oh"`
	}

	voucher := Voucher{}
	if err := ReadJsonBody(r, &voucher); err != nil {
		http.Error(w, err.Error(), err.Code)
		return
	}

	// Get, decode, and convert the device uuid
	uuid, err := uuid.FromBytes(voucher.Oh.Guid)
	if err != nil {
		http.Error(w, "Error converting GUID to UUID: "+err.Error(), http.StatusBadRequest)
		return
	}
	Verbose("POST /api/voucher: device UUID: %s", uuid.String())

	// Generate a node token
	nodeToken, httpErr := GenerateNodeToken()
	if err != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	//w.WriteHeader(http.StatusCreated)
	respBody := map[string]interface{}{
		"deviceUuid": uuid.String(),
		"nodeToken":  nodeToken,
	}
	WriteJsonResponse(http.StatusCreated, w, respBody)
}

// Utilities -------------------

// A "subclass" of error that also contains the http code that should be sent to the client
type HttpError struct {
	Err  error
	Code int
}

func NewHttpError(code int, errStr string) *HttpError {
	return &HttpError{Err: errors.New(errStr), Code: code}
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

	w.WriteHeader(httpCode) // seems like this has to be before writing the body
	w.Header().Set("Content-Type", "application/json")
	_, err = w.Write(dataJson)
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
