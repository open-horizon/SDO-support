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
gencmd=""
str="$(openssl version)"

#If the argument passed for this script does not equal one of the encryption keyTypes, send error code and exit.
#BY DEFAULT THE keyType WILL BE SET TO all
if [[ -n $keyType ]] && [[ $keyType != "ecdsa256" ]] && [[ $keyType != "ecdsa384" ]] && [[ $keyType != "rsa" ]] && [[ $keyType != "all" ]]; then
  echo "Error: specified encryption keyType '$keyType' is not supported."
  exit 2
fi
if [[ $OSTYPE == darwin* ]]; then
  if [[ ${str} =~ OpenSSL ]]; then
    echo "Found Homebrew Openssl"
  else
	  echo "You are not using the Homebrew version of OpenSSL. In order to run this script you must be using the Homebrew version of OpenSSL.
	  Go to this website and follow the instructions to set up your OpenSSL environment:
	  https://medium.com/@maxim.mahovik/upgrade-openssl-for-macos-e7a9ed82a76b "
	exit
  fi
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
  done
}

#This function will create a private key that is needed to create a private keystore. Encryption keyType passed will decide which command to run for private key creation
function genKey() {
  local privateKey=""${keyType}"private-key.pem"
  local keyCert=""${keyType}"Cert.crt"
  #Check if the folder is already created for the keyType (In case of multiple runs)
  mkdir -p "${keyType}"Key && pushd "${keyType}"Key >/dev/null || return
  #Generate a private RSA key.
  if [[ $keyType == "rsa" ]]; then
    if [ "$(uname)" == "Darwin" ]; then
      echo "Using macOS, will generate private key and certificate simultaneously."
      gencmd="openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$privateKey" -out "$keyCert""
    else
      echo -e "Generating an "${keyType}" private key."
      openssl genrsa -out "${keyType}"private-key.pem 2048 >/dev/null 2>&1
      chk $? 'Generating a rsa private key.'
    fi
    keyCertGenerator
  #Generate a private ecdsa (256 or 384) key.
  elif [[ $keyType == "ecdsa256" ]] || [[ $keyType == "ecdsa384" ]]; then
    echo -e "Generating an "${keyType}" private key."
    local var2=$(echo $keyType | cut -f2 -da)
    if [ "$(uname)" == "Darwin" ]; then
      echo "Using macOS, will generate private key and certificate simultaneously."
    else
      openssl ecparam -genkey -name secp"${var2}"r1 -out "${keyType}"private-key.pem >/dev/null 2>&1
      chk $? 'Generating an ecdsa private key.'
    fi
    keyCertGenerator
  fi
}

function keyCertGenerator() {
  if [[ -f "${keyType}"private-key.pem ]]; then
    if [ "$(uname)" == "Darwin" ]; then
      rm "${keyType}"private-key.pem
    else
      echo -e ""${keyType}" private key creation: Successful"
      gencmd="openssl req -x509 -key "$privateKey" -days 3650 -out "$keyCert""
    fi
  fi
  #Generate a private key and self-signed certificate.
  #You should have these environment variables set. If they aren't you will be prompted to enter values.
  #!/usr/bin/env bash
  if [ "$(uname)" == "Darwin" ]; then
    if [[ $keyType == "ecdsa256" ]] || [[ $keyType == "ecdsa384" ]]; then
      (
      echo "$COUNTRY_NAME"
      echo "$STATE_NAME"
      echo "$CITY_NAME"
      echo "$COMPANY_NAME"
      echo "$ORG_NAME"
      echo "$YOUR_NAME"
      echo "$EMAIL_NAME"
    ) | openssl req -x509 -nodes -days 3650 -newkey ec:<(openssl genpkey -genparam -algorithm ec -pkeyopt ec_paramgen_curve:P-"${var2}") -keyout "$privateKey" -out "$keyCert" >/dev/null 2>&1
      chk $? 'generating ec certificate'
      if [[ -f "$privateKey" ]]; then
        openssl ec -in ecdsa"${var2}"private-key.pem -out ecdsa"${var2}"private-key.pem >/dev/null 2>&1
        chk $? 'decrypting ec private key for macOS'
      else
        echo "No EC private key found"
      fi
    fi
  fi
  if [[ $keyType == "rsa" ]] || [ "$(uname)" != "Darwin" ]; then
    (
      echo "$COUNTRY_NAME"
      echo "$STATE_NAME"
      echo "$CITY_NAME"
      echo "$COMPANY_NAME"
      echo "$ORG_NAME"
      echo "$YOUR_NAME"
      echo "$EMAIL_NAME"
    ) | $gencmd >/dev/null 2>&1
    chk $? 'generating rsa certificate'
    if [ "$(uname)" == "Darwin" ] && [[ $keyType == "rsa" ]] && [[ -f "$privateKey" ]]; then
        openssl rsa -in "$privateKey" -out "$privateKey" >/dev/null 2>&1
        chk $? 'decrypting rsa private key for macOS'
    fi
  fi

  if [[ -f $keyCert ]] && [[ -f "$privateKey" ]]; then
    echo -e ""${keyType}" Private Key and "${keyType}"Key Certificate creation: Successful"
    genPublicKey
    popd >/dev/null
  else
    echo ""${keyType}" Private Key and "${keyType}"Key Certificate not found"
    exit 2
  fi
}

function genPublicKey() {
  # This function is ran after the private key and owner certificate has been created. This function will create a public key to correspond with
  # the owner private key/certificate. Generate a public key from the certificate file
  openssl x509 -pubkey -noout -in $keyCert >"${keyType}"pub-key.pem
  chk $? 'Creating public key...'
  echo "Generating "${keyType}" public key..."
  if [[ -f "${keyType}"pub-key.pem ]]; then
    echo -e ""${keyType}" public key creation: Successful"
    mv "${keyType}"pub-key.pem ..
  else
    echo -e ""${keyType}" public key creation: Unsuccessful"
    exit 2
  fi
}

function combineKeys() {
  #This function will combine all private keys and certificates into one tarball, then will concatenate all public keys into one
  if [[ -f "rsapub-key.pem" && -f "ecdsa256pub-key.pem" && -f "ecdsa384pub-key.pem" ]]; then
    if [[ -f owner-public-key.pem ]]; then
      rm owner-public-key.pem
    fi
    #adding delimiters for SDO 1.10 pub key format
    echo "," >> rsapub-key.pem && echo "," >> ecdsa256pub-key.pem
    echo "Concatenating Public Key files..."
        #Combine all the public keys into one
    for i in "rsapub-key.pem" "ecdsa256pub-key.pem" "ecdsa384pub-key.pem"
      do
        local keyName=$i
        local removeWord="pub-key.pem"
        keyName=${keyName//$removeWord/}
        #adding delimiters for SDO 1.10 pub key format
        echo ""$keyName":" >key.txt
        cat key.txt $i >> ${ORG_NAME}_${YOUR_NAME}_public-key.pem
      done
    rm -- ecdsa*.pem && rm rsapub* && rm key.txt
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
