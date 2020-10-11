#!/bin/bash
# This script will generate a Key-Pair for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat << EndOfMessage
Usage: ${0##*/} [<encryption-keyType>]

Arguments:
  <encryption-keyType>  The type of encryption to use when generating owner key pair (ecdsa256, ecdsa384, rsa, or all). Will default to all.

Optional Environment Variables:
  COUNTRY_NAME - The country the user resides in. Necessary information for keyCertificate generation.
  STATE_NAME - The state the user resides in. Necessary information for keyCertificate generation.
  CITY_NAME - The city the user resides in. Necessary information for keyCertificate generation.
  ORG_NAME - The organization the user works for. Necessary information for keyCertificate generation.
  COMPANY_NAME - The company the user works for. Necessary information for keyCertificate generation.
  YOUR_NAME - The name of the user. Necessary information for keyCertificate generation.
  EMAIL_NAME - The user's email. Necessary information for keyCertificate generation.

EndOfMessage
  exit 1
fi

keyType="${1:-all}"

#If the argument passed for this script does not equal one of the encryption keyTypes, send error code and exit.
#BY DEFAULT THE keyType WILL BE SET TO all
if [[ -n $keyType ]] && [[ $keyType != "ecdsa256" ]] && [[ $keyType != "ecdsa384" ]] && [[ $keyType != "rsa" ]] && [[ $keyType != "all" ]]; then
  echo "Error: specified encryption keyType '$keyType' is not supported."
  exit 2
fi

#============================FUNCTIONS=================================

chk() {
  local exitCode=$1
  local task=$2
  local dontExit=$3 # set to 'continue' to not exit for this error
  if [[ $exitCode == 0 ]]; then return; fi
  echo "Error: exit code $exitCode from: $task"
  if [[ $dontExit != 'continue' ]]; then
    exit $exitCode
  fi
}

ensureWeAreUser() {
  if [[ $(whoami) == 'root' ]]; then
    echo "Error: must be normal user to run ${0##*/}"
    exit 2
  fi
}

function allKeys() {
  for i in "rsa" "ecdsa256" "ecdsa384"; do
    keyType=$i
    genKey
    wait
  done
}

#This function will create a private key that is needed to create a private keystore. Encryption keyType passed will decide which command to run for private key creation
function genKey() {
  #Check if the folder is already created for the keyType (In case of multiple runs)
  mkdir -p "${keyType}"Key && pushd "${keyType}"Key >/dev/null || return
  #Generate a private RSA key.
  if [[ $keyType == "rsa" ]]; then
    echo -e "Generating a "${keyType}" private key."
    openssl genrsa -out "${keyType}"private-key.pem 2048 >/var/tmp/out 2>&1
    chk $? 'Generating a rsa private key.'
    keyCertGenerator
  #Generate a private ecdsa (256 or 384) key.
  elif [[ $keyType == "ecdsa256" ]] || [[ $keyType == "ecdsa384" ]]; then
    echo -e "Generating an "${keyType}" private key."
    local var2=$(echo $keyType | cut -f2 -da)
    openssl ecparam -genkey -name secp"${var2}"r1 -out "${keyType}"private-key.pem >/dev/null 2>&1
    chk $? 'Generating an ecdsa private key.'
    keyCertGenerator
  fi
}

#This function will create a keyCertificate that is needed to create a corresponding public key, as well as a private keystore.
function keyCertGenerator() {
  if [[ -f "${keyType}"private-key.pem ]]; then
    local privateKey=""${keyType}"private-key.pem"
    local keyCert=""${keyType}"Cert.crt"
    echo -e ""${keyType}" private key creation: Successful"
    #Generate a self-signed certificate from the private key file.
    #You should have these environment variables set. If they aren't you will be prompted to enter values.
    echo -e "Generating a corresponding certificate."
    (
      echo "$COUNTRY_NAME"
      echo "$STATE_NAME"
      echo "$CITY_NAME"
      echo "$COMPANY_NAME"
      echo "$ORG_NAME"
      echo "$YOUR_NAME"
      echo "$EMAIL_NAME"
    ) | (openssl req -x509 -key "$privateKey" -days 365 -out "$keyCert") >/dev/null 2>&1
    chk $? 'generating certificate'
    if [[ -f $keyCert ]]; then
      echo -e ""${keyType}"Key Certificate creation: Successful"
      genPublicKey
      popd >/dev/null
    else
      echo "Owner "${keyType}"Key Certificate not found"
      exit 2
    fi
  else
    echo ""${keyType}"private-key.pem not found"
    exit 2
  fi
}

function genPublicKey() {
  # This function is ran after the private key and owner certificate has been created. This function will create a public key to correspond with
  # the owner private key/certificate. Generate a public key from the certificate file
  openssl x509 -pubkey -noout -in $keyCert >"${keyType}"pub-key.pem
  chk $? 'Creating public key...'
  echo "Generating "${keyType}" public key..."
  mv "${keyType}"pub-key.pem ..
  echo -e ""${keyType}" public key creation: Successful"
}

function combineKeys() {
  #This function will combine all private keys and certificates into one tarball, then will concatenate all public keys into one
  if [[ -f "rsapub-key.pem" && -f "ecdsa256pub-key.pem" && -f "ecdsa384pub-key.pem" ]]; then
    #Combine all the public keys into one
    echo "Concatenating Public Key files..."
    cat ecdsa256pub-key.pem rsapub-key.pem ecdsa384pub-key.pem >owner-public-key.pem
    chk $? 'Concatenating Public Key files...'
    rm -- ecdsa*.pem && rm rsapub*
    #Tar all keys and certs
    tar -czf owner-keys.tar.gz ecdsa256Key ecdsa384Key rsaKey
    chk $? 'Saving all key pairs in a tarball...'
    #removing all files/directories except the ones we need
    rm -rf "rsaKey" "ecdsa256Key" "ecdsa384Key"
  fi
}

function infoKeyCert() {
  #If varaibles are not set, prompt this openssl certificate paragraph
  if [[ -z $COUNTRY_NAME ]] || [[ -z $STATE_NAME ]] || [[ -z $CITY_NAME ]] || [[ -z $ORG_NAME ]] || [[ -z $COMPANY_NAME ]] || [[ -z $YOUR_NAME ]] || [[ -z $EMAIL_NAME ]]; then
    printf "You have to enter information in order to generate a custom self signed certificate as a part of your key pair for SDO Owner Attestation. What you are about to enter is what is called a Distinguished Name or a DN. There are quite a few fields but you can leave some blank. For some fields there will be a default value, If you enter '.', the field will be left blank." && echo
  fi
  #while variables are not set, prompt for whichever variable is not set
  while [[ -z $COUNTRY_NAME ]] || [[ -z $STATE_NAME ]] || [[ -z $CITY_NAME ]] || [[ -z $ORG_NAME ]] || [[ -z $COMPANY_NAME ]] || [[ -z $YOUR_NAME ]] || [[ -z $EMAIL_NAME ]]; do
    if [[ -z $COUNTRY_NAME ]]; then
      echo "Country Name (2 letter code) [AU]:"
      read COUNTRY_NAME && echo
    elif [[ -z $STATE_NAME ]]; then
      echo "State or Province Name (full name) [Some-State]:"
      read STATE_NAME && echo
    elif [[ -z $CITY_NAME ]]; then
      echo "Locality Name (eg, city) []:"
      read CITY_NAME && echo
    elif [[ -z $COMPANY_NAME ]]; then
      echo "Organization Name (eg, company) [Internet Widgits Pty Ltd]:"
      read COMPANY_NAME && echo
    elif [[ -z $ORG_NAME ]]; then
      echo "Organizational Unit Name (eg, section) []:"
      read ORG_NAME && echo
    elif [[ -z $YOUR_NAME ]]; then
      echo "Common Name (e.g. server FQDN or YOUR name) []:"
      read YOUR_NAME && echo
    elif [[ -z $EMAIL_NAME ]]; then
      echo "Email Address []:"
      read EMAIL_NAME && echo
    fi
  done
}

#============================MAIN CODE=================================

infoKeyCert
if [[ -n "$keyType" ]] && [[ "$keyType" == "all" ]]; then
  allKeys
  combineKeys
else
  genKey
fi
echo "Owner Private Key Tarfile and Owner Public Key have been created"
