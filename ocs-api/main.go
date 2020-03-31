package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"regexp"

	"github.com/google/uuid"
	"github.com/open-horizon/SDO-support/ocs-api/data"
	"github.com/open-horizon/SDO-support/ocs-api/outils"
)

/*
REST API server to configure the SDO OCS (Owner Companion Service) DB files for import a voucher and setting up horizon files for device boot.
*/

// These global vars are necessary because the handler functions are not given any context
var OcsDbDir string

var GetVoucherRegex = regexp.MustCompile(`^/api/voucher/([^/]+)$`)

//var GetVoucherRegex = regexp.MustCompile(`^/api/voucher/(.+)$`)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: ./ocs-api <port> <ocs-db-path>")
		os.Exit(1)
	}

	// Process cmd line args and env vars
	port := os.Args[1]
	OcsDbDir = os.Args[2]
	outils.SetVerbose()

	// Ensure we can get to the db, and create the necessary subdirs, if necessary
	if err := os.MkdirAll(OcsDbDir+"/v1/devices", 0755); err != nil {
		outils.Fatal(3, "could not create directory %s: %v", OcsDbDir+"/v1/devices", err)
	}
	if err := os.MkdirAll(OcsDbDir+"/v1/values", 0755); err != nil {
		outils.Fatal(3, "could not create directory %s: %v", OcsDbDir+"/v1/values", err)
	}

	//http.HandleFunc("/", rootHandler)
	http.HandleFunc("/api/", apiHandler)

	outils.Verbose("Listening on port %s and using ocs db %s", port, OcsDbDir)
	log.Fatal(http.ListenAndServe(":"+port, nil))
} // end of main

// API route dispatcher
func apiHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("Handling %s ...", r.URL.Path)
	//outils.Verbose("FindString: %s.", GetVoucherRegex.FindString(r.URL.Path))
	if matches := GetVoucherRegex.FindStringSubmatch(r.URL.Path); r.Method == "GET" && len(matches) >= 2 {
		getVoucherHandler(matches[1], w, r)
	} else if r.Method == "POST" && r.URL.Path == "/api/voucher" {
		postVoucherHandler(w, r)
	} else {
		http.Error(w, "Route "+r.URL.Path+" not found", http.StatusNotFound)
	}
}

// Route Handlers --------------------------------------------------------------------------------------------------

//============= GET /api/voucher/{device-id} =============
// Reads an already imported voucher
func getVoucherHandler(deviceUuid string, w http.ResponseWriter, r *http.Request) {
	outils.Verbose("GET /api/voucher/%s ...", deviceUuid)

	// Read voucher.json from the db
	voucherFileName := OcsDbDir + "/v1/devices/" + deviceUuid + "/voucher.json"
	//if _, err := os.Stat(voucherFileName); err != nil {
	//	http.Error(w, "Error reading "+voucherFileName+": "+err.Error(), http.StatusBadRequest)
	//	return
	//}
	voucherBytes, err := ioutil.ReadFile(voucherFileName)
	if err != nil {
		http.Error(w, "Error reading "+voucherFileName+": "+err.Error(), http.StatusBadRequest)
		return
	}

	// Send voucher to client
	outils.WriteResponse(http.StatusOK, w, voucherBytes)
}

//============= POST /api/voucher =============
// Imports a voucher (can be called again for an existing voucher and will update/overwrite)
func postVoucherHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("POST /api/voucher ...")

	if err := outils.IsValidPostJson(r); err != nil {
		http.Error(w, err.Error(), err.Code)
		return
	}

	// Parse the request body
	type OhStruct struct {
		Guid []byte `json:"g"` // making it type []byte will automatically base64 decode the json value
	}
	type Voucher struct {
		Oh OhStruct `json:"oh"`
	}

	voucher := Voucher{}
	bodyBytes, err := ioutil.ReadAll(r.Body) // we need the body in 2 forms, but can only read it once, so get it as bytes
	if err != nil {
		http.Error(w, "Error reading the request body: "+err.Error(), http.StatusBadRequest)
		return
	}
	if err := outils.ParseJsonString(bodyBytes, &voucher); err != nil {
		http.Error(w, err.Error(), err.Code)
		return
	}

	// Get, decode, and convert the device uuid
	uuid, err := uuid.FromBytes(voucher.Oh.Guid)
	if err != nil {
		http.Error(w, "Error converting GUID to UUID: "+err.Error(), http.StatusBadRequest)
		return
	}
	outils.Verbose("POST /api/voucher: device UUID: %s", uuid.String())

	// Put the voucher in the OCS DB
	deviceDir := OcsDbDir + "/v1/devices/" + uuid.String()
	if err := os.MkdirAll(deviceDir, 0755); err != nil {
		http.Error(w, "could not create directory "+deviceDir+": "+err.Error(), http.StatusInternalServerError)
		return
	}
	fileName := deviceDir + "/voucher.json"
	outils.Verbose("POST /api/voucher: creating %s ...", fileName)
	if err := ioutil.WriteFile(fileName, bodyBytes, 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Create the device download file (svi.json) and psi.json
	fileName = deviceDir + "/svi.json"
	outils.Verbose("POST /api/voucher: creating %s ...", fileName)
	sviJson := data.SviJson1 + uuid.String() + data.SviJson2
	if err := ioutil.WriteFile(fileName, []byte(sviJson), 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}
	fileName = deviceDir + "/psi.json"
	outils.Verbose("POST /api/voucher: creating %s ...", fileName)
	if err := ioutil.WriteFile(fileName, []byte(data.PsiJson), 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Generate a node token
	nodeToken, httpErr := outils.GenerateNodeToken()
	if err != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	// Create exec file
	//todo: remove user creds when anax issue 1614 is implemented
	userCreds := outils.GetEnvVarWithDefault("HZN_EXCHANGE_USER_AUTH", "")
	if userCreds == "" {
		http.Error(w, "HZN_EXCHANGE_USER_AUTH not set", http.StatusInternalServerError)
		return
	}
	aptRepo := "http://pkg.bluehorizon.network/linux/ubuntu"
	aptChannel := "testing"
	execCmd := outils.MakeExecCmd("bash agent-install.sh -i " + aptRepo + " -t " + aptChannel + " -j apt-repo-public.key -u " + userCreds + " -d " + uuid.String() + ":" + nodeToken + "")
	fileName = OcsDbDir + "/v1/values/" + uuid.String() + "_exec"
	outils.Verbose("POST /api/voucher: creating %s ...", fileName)
	if err := ioutil.WriteFile(fileName, []byte(execCmd), 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Send response to client
	respBody := map[string]interface{}{
		"deviceUuid": uuid.String(),
		"nodeToken":  nodeToken,
	}
	outils.WriteJsonResponse(http.StatusCreated, w, respBody)
}
