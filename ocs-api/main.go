package main

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/open-horizon/SDO-support/ocs-api/data"
	"github.com/open-horizon/SDO-support/ocs-api/outils"
)

/*
REST API server to configure the SDO OCS (Owner Companion Service) DB files for import a voucher and setting up horizon files for device boot.
*/

// These global vars are necessary because the handler functions are not given any context
var OcsDbDir string
var GetVoucherRegex = regexp.MustCompile(`^/api/vouchers/([^/]+)$`)
var CurrentOrgId string
var CurrentExchangeUrl string         // the external url, that the device needs
var CurrentExchangeInternalUrl string // will default to CurrentExchangeUrl
var CurrentCssUrl string              // the external url, that the device needs
var CurrentPkgsFrom string            // the argument to the agent-install.sh -i flag

type CfgVarsStruct struct {
	HZN_EXCHANGE_URL      string `json:"HZN_EXCHANGE_URL"`      // the external URL of the exchange (how devices should reach it)
	EXCHANGE_INTERNAL_URL string `json:"EXCHANGE_INTERNAL_URL"` // optional: how ocs-api should contact the exchange. Will default to HZN_EXCHANGE_URL
	HZN_FSS_CSSURL        string `json:"HZN_FSS_CSSURL"`
	HZN_ORG_ID            string `json:"HZN_ORG_ID"`
}
type Config struct {
	CfgVars CfgVarsStruct `json:"cfgVars"`
	Crt     []byte        `json:"crt"` // making it type []byte will automatically base64 decode the json value
}

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
	if err := os.MkdirAll(OcsDbDir+"/v1/devices", 0750); err != nil {
		outils.Fatal(3, "could not create directory %s: %v", OcsDbDir+"/v1/devices", err)
	}
	if err := os.MkdirAll(OcsDbDir+"/v1/values", 0750); err != nil {
		outils.Fatal(3, "could not create directory %s: %v", OcsDbDir+"/v1/values", err)
	}

	// Create all of the common config files, if we have the necessary env vars to do so
	if httpErr := createConfigFiles(nil); httpErr != nil {
		outils.Fatal(3, "creating common config files, HTTP code: %d, error: %s", httpErr.Code, httpErr.Error())
	}

	//http.HandleFunc("/", rootHandler)
	http.HandleFunc("/api/", apiHandler)

	outils.Verbose("Listening on port %s and using ocs db %s", port, OcsDbDir)
	log.Fatal(http.ListenAndServe(":"+port, nil))
} // end of main

// API route dispatcher
func apiHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("Handling %s ...", r.URL.Path)
	if r.Method == "GET" && r.URL.Path == "/api/version" {
		getVersionHandler(w, r)
		// this route is disabled because penetration testing deemed this a security exposure, because you can cause this service to do arbitrary DNS lookups
		//} else if r.Method == "POST" && r.URL.Path == "/api/config" {
		//	postConfigHandler(w, r)
	} else if matches := GetVoucherRegex.FindStringSubmatch(r.URL.Path); r.Method == "GET" && len(matches) >= 2 { // GET /api/vouchers/{device-id}
		getVoucherHandler(matches[1], w, r)
	} else if r.Method == "GET" && r.URL.Path == "/api/vouchers" {
		getVouchersHandler(w, r)
	} else if r.Method == "POST" && (r.URL.Path == "/api/vouchers" || r.URL.Path == "/api/voucher") { //todo: backward compat until we update hzn voucher import
		postVoucherHandler(w, r)
	} else if r.Method == "POST" && (r.URL.Path == "/api/rereadagentinstall") {
		postRereadAgentInstallHandler(w, r)
	} else if r.Method == "POST" && (r.URL.Path == "/api/keys") {
		postImportKeysHandler(w, r)
	} else {
		http.Error(w, "Route "+r.URL.Path+" not found", http.StatusNotFound)
	}
}

// Route Handlers --------------------------------------------------------------------------------------------------

//============= GET /api/version =============
// Returns the ocs-api version (in plain text, not json)
func getVersionHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("GET /api/version ...")

	// Send voucher to client
	w.WriteHeader(http.StatusOK) // seems like this has to be before writing the body
	_, err := w.Write([]byte(OCS_API_VERSION))
	if err != nil {
		outils.Error(err.Error())
	}
}

//============= POST /api/config =============
//!!!!!!!! Not being used!!! See note in apiHandler()
// Sets ocs-api configuration that is not specific to any specific device
func postConfigHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("POST /api/config ...")

	// Authentication for this REST API is based on the *current* config, not the new config
	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, OcsDbDir+"/v1/values/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	if httpErr := outils.IsValidPostJson(r); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	// Parse the request body
	config := Config{}
	if httpErr := outils.ReadJsonBody(r, &config); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}
	if config.CfgVars.HZN_EXCHANGE_URL == "" || config.CfgVars.HZN_FSS_CSSURL == "" || config.CfgVars.HZN_ORG_ID == "" { // config.Crt and config.CfgVars.EXCHANGE_INTERNAL_URL are allowed to be empty
		http.Error(w, "Error: one of the required fields is missing in the request body", http.StatusBadRequest)
		return
	}

	// Create all of the common config files
	if httpErr := createConfigFiles(&config); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	w.WriteHeader(http.StatusOK)
}

//============= GET /api/vouchers/{device-id} =============
// Reads/returns an already imported voucher
func getVoucherHandler(deviceUuid string, w http.ResponseWriter, r *http.Request) {
	outils.Verbose("GET /api/vouchers/%s ...", deviceUuid)

	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, OcsDbDir+"/v1/values/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	// Read voucher.json from the db
	voucherFileName := OcsDbDir + "/v1/devices/" + deviceUuid + "/voucher.json"
	voucherBytes, err := ioutil.ReadFile(filepath.Clean(voucherFileName))
	if err != nil {
		http.Error(w, "Error reading "+voucherFileName+": "+err.Error(), http.StatusBadRequest)
		return
	}

	// Send voucher to client
	outils.WriteResponse(http.StatusOK, w, voucherBytes)
}

//============= GET /api/vouchers =============
// Reads/returns an already imported voucher
func getVouchersHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("GET /api/vouchers ...")

	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, OcsDbDir+"/v1/values/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	// Read the v1/devices/ directory in the db
	vouchersDirName := OcsDbDir + "/v1/devices"
	files, err := ioutil.ReadDir(filepath.Clean(vouchersDirName))
	if err != nil {
		http.Error(w, "Error reading "+vouchersDirName+" directory: "+err.Error(), http.StatusBadRequest)
		return
	}

	vouchers := []string{}
	for _, file := range files {
		if file.IsDir() {
			vouchers = append(vouchers, file.Name())
		}
	}

	// Send voucher to client
	outils.WriteJsonResponse(http.StatusOK, w, vouchers)
}

//============= POST /api/vouchers =============
// Imports a voucher (can be called again for an existing voucher and will update/overwrite)
func postVoucherHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("POST /api/vouchers ...")

	valuesDir := OcsDbDir + "/v1/values"
	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, valuesDir+"/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	// If all of the common config files didn't get created at startup, tell them
	if !outils.PathExists(valuesDir+"/agent-install.cfg") || !outils.PathExists(valuesDir+"/agent-install.sh") { // agent-install.crt is optional
		http.Error(w, "Error: not all of the common config files were created in the OCS DB at startup. Have your admin restart the service with all of the necessary input.", http.StatusBadRequest)
		return
	}

	if httpErr := outils.IsValidPostJson(r); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
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
	if httpErr := outils.ParseJsonString(bodyBytes, &voucher); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	// Get, decode, and convert the device uuid
	uuid, err := uuid.FromBytes(voucher.Oh.Guid)
	if err != nil {
		http.Error(w, "Error converting GUID to UUID: "+err.Error(), http.StatusBadRequest)
		return
	}
	outils.Verbose("POST /api/vouchers: device UUID: %s", uuid.String())

	// Put the voucher in the OCS DB
	deviceDir := OcsDbDir + "/v1/devices/" + uuid.String()
	if err := os.MkdirAll(deviceDir, 0750); err != nil {
		http.Error(w, "could not create directory "+deviceDir+": "+err.Error(), http.StatusInternalServerError)
		return
	}
	fileName := deviceDir + "/voucher.json"
	outils.Verbose("POST /api/vouchers: creating %s ...", fileName)
	if err := ioutil.WriteFile(filepath.Clean(fileName), bodyBytes, 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Create the device download file (svi.json) and psi.json
	fileName = deviceDir + "/svi.json"
	outils.Verbose("POST /api/vouchers: creating %s ...", fileName)
	sviJson1 := ""
	if outils.PathExists(valuesDir + "/agent-install.crt") {
		sviJson1 = data.SviJson1
	}
	sviJson := "[" + sviJson1 + data.SviJson2 + uuid.String() + data.SviJson3 + "]"
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(sviJson), 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}
	fileName = deviceDir + "/psi.json"
	outils.Verbose("POST /api/vouchers: creating %s ...", fileName)
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(data.PsiJson), 0644); err != nil {
		http.Error(w, "could not create "+fileName+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Generate a node token
	nodeToken, httpErr := outils.GenerateNodeToken()
	if httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	// Create exec file
	//aptRepo := "http://pkg.bluehorizon.network/linux/ubuntu"
	//aptChannel := "testing"
	//execCmd := outils.MakeExecCmd("/bin/sh agent-install-wrapper.sh -i " + aptRepo + " -t " + aptChannel + " -j apt-repo-public.key -a " + uuid.String() + ":" + nodeToken)
	execCmd := outils.MakeExecCmd("/bin/sh agent-install-wrapper.sh -i " + CurrentPkgsFrom + " -a " + uuid.String() + ":" + nodeToken)
	fileName = OcsDbDir + "/v1/values/" + uuid.String() + "_exec"
	outils.Verbose("POST /api/vouchers: creating %s ...", fileName)
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(execCmd), 0644); err != nil {
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

//============= POST /api/rereadagentinstall =============
// Causes our service to get agent-install.sh again (to pick up any changes to it)
func postRereadAgentInstallHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("POST /api/rereadagentinstall ...")

	valuesDir := OcsDbDir + "/v1/values"
	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, valuesDir+"/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	// Reread agent-install.sh
	fileName := valuesDir + "/agent-install.sh"
	if httpErr := getAgentInstallScript(fileName); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	w.WriteHeader(http.StatusOK)
}

//============= POST /api/keys =============
// Receives in the body a tar file containing the owner's private keys and certificates. Imports them into our keystore.
// This allows sdo-owner-services to read vouchers intended for them, and to securely communicate with their devices booting up.
func postImportKeysHandler(w http.ResponseWriter, r *http.Request) {
	outils.Verbose("POST /api/keys ...")

	valuesDir := OcsDbDir + "/v1/values"
	if authenticated, httpErr := outils.ExchangeAuthenticate(r, CurrentExchangeInternalUrl, CurrentOrgId, valuesDir+"/agent-install.crt"); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	} else if !authenticated {
		http.Error(w, "invalid exchange credentials provided", http.StatusUnauthorized)
		return
	}

	// Verify content type
	if httpErr := outils.IsValidPostBinary(r); httpErr != nil {
		http.Error(w, httpErr.Error(), httpErr.Code)
		return
	}

	// Create directory we are putting the file in
	tarFileDir := "tmp" // in the current dir (home dir)
	if err := os.MkdirAll(tarFileDir, 0750); err != nil {
		http.Error(w, "could not create directory "+tarFileDir+": "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Create a writer that will write the request body to the tar file
	tarFilePath := tarFileDir + "/owner-keys.tar.gz"
	f, err := os.Create(tarFilePath)
	if err != nil {
		http.Error(w, "could not create file "+tarFilePath+": "+err.Error(), http.StatusInternalServerError)
		return
	}
	fileWriter := bufio.NewWriter(f)
	_, err = fileWriter.ReadFrom(r.Body)
	if err != nil {
		http.Error(w, "could not read request body: "+err.Error(), http.StatusInternalServerError)
		f.Close()
		return
	}
	fileWriter.Flush()
	f.Close()

	// Run the script that will import the tar file keys
	outils.Verbose("Running command: ./import-owner-private-keys.sh %s", tarFilePath)
	stdOut, stdErr, err := outils.RunCmd("./import-owner-private-keys.sh", tarFilePath)
	if err != nil {
		http.Error(w, "error running import-owner-private-keys.sh: "+err.Error(), http.StatusBadRequest) // this includes stdErr
		return
	} else {
		if len(stdErr) > 0 { // with shell scripts there can be error msgs in stderr even though the exit code was 0
			outils.Verbose("stderr from import-owner-private-keys.sh: %s", string(stdErr))
		}
		outils.Verbose(string(stdOut))
	}

	w.WriteHeader(http.StatusCreated)
}

//============= Non-Route Functions =============

// Create the common (not device specific) config files. Can be called during startup (config == nil)
func createConfigFiles(config *Config) *outils.HttpError {
	// Note: this function is currently only called with a nil config at startup, because the POST /api/config route has been disabled
	valuesDir := OcsDbDir + "/v1/values"
	var fileName, dataStr string

	// Create agent-install.crt and its name file
	var crt []byte
	if config != nil {
		crt = config.Crt // the (now disabled) POST /api/config route
	} else if outils.IsEnvVarSet("HZN_MGMT_HUB_CERT") {
		// during startup
		var err error
		crt, err = base64.StdEncoding.DecodeString(os.Getenv("HZN_MGMT_HUB_CERT"))
		if err != nil {
			outils.Verbose("Base64 decoding HZN_MGMT_HUB_CERT was unsuccessful (%s), using it as not encoded ...", err.Error())
			// Note: supposedly we could instead use this regex to check for base64 encoding: ^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$
			crt = []byte(os.Getenv("HZN_MGMT_HUB_CERT"))
			//return outils.NewHttpError(http.StatusBadRequest, "could not base64 decode HZN_MGMT_HUB_CERT: "+err.Error())
		}
	}
	if len(crt) > 0 {
		fileName = valuesDir + "/agent-install.crt"
		outils.Verbose("Creating %s ...", fileName)
		if err := ioutil.WriteFile(filepath.Clean(fileName), crt, 0644); err != nil {
			return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
		}

		fileName = valuesDir + "/agent-install-crt_name"
		outils.Verbose("Creating %s ...", fileName)
		dataStr = "agent-install.crt"
		if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(dataStr), 0644); err != nil {
			return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
		}
	}

	// Create agent-install.cfg and its name file
	if config != nil {
		CurrentExchangeUrl = config.CfgVars.HZN_EXCHANGE_URL
		if config.CfgVars.EXCHANGE_INTERNAL_URL != "" {
			CurrentExchangeInternalUrl = config.CfgVars.EXCHANGE_INTERNAL_URL
		} else {
			CurrentExchangeInternalUrl = CurrentExchangeUrl //default
		}
		CurrentCssUrl = config.CfgVars.HZN_FSS_CSSURL
		CurrentOrgId = config.CfgVars.HZN_ORG_ID
	} else if outils.IsEnvVarSet("HZN_EXCHANGE_URL") && outils.IsEnvVarSet("HZN_FSS_CSSURL") && outils.IsEnvVarSet("HZN_ORG_ID") {
		CurrentExchangeUrl = os.Getenv("HZN_EXCHANGE_URL")
		// CurrentExchangeInternalUrl is not needed for the device config file, only for ocs-api exchange authentication
		if outils.IsEnvVarSet("EXCHANGE_INTERNAL_URL") {
			CurrentExchangeInternalUrl = os.Getenv("EXCHANGE_INTERNAL_URL")
		} else {
			CurrentExchangeInternalUrl = CurrentExchangeUrl // default
		}
		CurrentCssUrl = os.Getenv("HZN_FSS_CSSURL")
		CurrentOrgId = os.Getenv("HZN_ORG_ID")
	}
	if CurrentExchangeUrl != "" && CurrentCssUrl != "" && CurrentOrgId != "" {
		fileName = valuesDir + "/agent-install.cfg"
		outils.Verbose("Creating %s ...", fileName)
		dataStr = "HZN_EXCHANGE_URL=" + CurrentExchangeUrl + "\nHZN_FSS_CSSURL=" + CurrentCssUrl + "\nHZN_ORG_ID=" + CurrentOrgId + "\n"
		if len(crt) > 0 {
			// only add this if we actually created the agent-install.crt file above
			dataStr += "HZN_MGMT_HUB_CERT_PATH=agent-install.crt\n"
		}
		if err := ioutil.WriteFile(fileName, []byte(dataStr), 0644); err != nil {
			return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
		}
		outils.Verbose("Will be configuring devices to use config:\n%s", dataStr)
	}

	fileName = valuesDir + "/agent-install-cfg_name"
	outils.Verbose("Creating %s ...", fileName)
	dataStr = "agent-install.cfg"
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(dataStr), 0644); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
	}

	// Get and create agent-install.sh and its name file
	fileName = valuesDir + "/agent-install.sh"
	if httpErr := getAgentInstallScript(fileName); httpErr != nil {
		return httpErr
	}

	fileName = valuesDir + "/agent-install-sh_name"
	outils.Verbose("Creating %s ...", fileName)
	dataStr = "agent-install.sh"
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(dataStr), 0644); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
	}

	// Create agent-install-wrapper.sh and its name file
	fileName = valuesDir + "/agent-install-wrapper.sh"
	outils.Verbose("Creating %s ...", fileName)
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(data.AgentInstallWrapper), 0750); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
	}

	fileName = valuesDir + "/agent-install-wrapper-sh_name"
	outils.Verbose("Creating %s ...", fileName)
	dataStr = "agent-install-wrapper.sh"
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(dataStr), 0644); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
	}

	CurrentPkgsFrom = os.Getenv("SDO_GET_PKGS_FROM")
	if CurrentPkgsFrom == "" {
		CurrentPkgsFrom = "https://github.com/open-horizon/anax/releases/latest/download" // default
	}
	outils.Verbose("Will be configuring devices to get horizon packages from %s", CurrentPkgsFrom)
	// try to ensure they didn't give us a bad value for SDO_GET_PKGS_FROM
	if !strings.HasPrefix(CurrentPkgsFrom, "https://github.com/open-horizon/anax/releases") && !strings.HasPrefix(CurrentPkgsFrom, "css:") {
		outils.Warning("Unrecognized value specified for SDO_GET_PKGS_FROM: %s", CurrentPkgsFrom)
		// continue, because maybe this is a value for the agent-install.sh -i flag that we don't know about yet
	}

	// Download and create apt-repo-public.key and its name file
	/*future: support getting horizon pkgs from an APT or RPM repo
	url := "http://pkg.bluehorizon.network/bluehorizon.network-public.key"
	fileName = valuesDir + "/apt-repo-public.key"
	outils.Verbose("Downloading %s to %s ...", url, fileName)
	if err := outils.DownloadFile(url, fileName, 0644); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not download "+url+" to "+fileName+": "+err.Error())
	}

	fileName = valuesDir + "/apt-repo-public-key_name"
	outils.Verbose("Creating %s ...", fileName)
	dataStr = "apt-repo-public.key"
	if err := ioutil.WriteFile(filepath.Clean(fileName), []byte(dataStr), 0644); err != nil {
		return outils.NewHttpError(http.StatusInternalServerError, "could not create "+fileName+": "+err.Error())
	}
	*/

	return nil
}

// Reads or rereads agent-install.sh from the location they told us to get it from. Used in POST /api/rereadagentinstall
func getAgentInstallScript(destFileName string) *outils.HttpError {
	if outils.PathExists("./agent-install.sh") {
		// agent-install.sh was mounted into our container by the person starting it
		outils.Verbose("agent-install.sh was mounted into the container, copying it...")
		if httpErr := outils.CopyFile("./agent-install.sh", destFileName, 0750); httpErr != nil {
			return httpErr
		}
	} else {
		url := os.Getenv("AGENT_INSTALL_URL")
		if url == "" {
			url = "https://github.com/open-horizon/anax/releases/latest/download/agent-install.sh" // the default
		}
		outils.Verbose("Downloading %s to %s ...", url, destFileName)
		if err := outils.DownloadFile(url, destFileName, 0750); err != nil { //todo: i think we also need to look inside the file and check if the 1st line begins with 404
			return outils.NewHttpError(http.StatusInternalServerError, "could not download "+url+" to "+destFileName+": "+err.Error())
		}
	}
	return nil
}
