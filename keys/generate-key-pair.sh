#!/bin/bash
# This script will generate a Key-Pair for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<encryption-keyType>]

Arguments:
  <encryption-keyType>  The type of encryption to use when generating owner key pair (ecdsa256, ecdsa384, rsa, or all). Will default to all.

Required environment variables:
  SDO_KEY_PWD - The password for your generated keystore. This password must be passed into run-sdo-owner-services.sh in order to be mounted to $containerHome/ocs/config/application.properties/fs.owner.keystore-password
  countryName - The country the user resides in. Necessary information for keyCertificate generation.
  cityName - The city the user resides in. Necessary information for keyCertificate generation.
  orgName - The organization the user works for. Necessary information for keyCertificate generation.
  emailName - The user's email. Necessary information for keyCertificate generation.
  ownerName - Part of the alias you will use for owner key pairs

Additional environment variables (that do not usually need to be set):
  KEEP_KEY_FILES - set to 'true' to keep all key pairs generated for each type of key (ecdsa256, ecdsa384, rsa). This is for devs who may want to check out each individual file that goes into generating Key pairs.

EndOfMessage
    exit 1
fi

keyType="${1:-all}"
keyCert=""
privateKey=""
KEEP_KEY_FILES=${KEEP_KEY_FILES:-}


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
    local dontExit=$3   # set to 'continue' to not exit for this error
    if [[ $exitCode == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $exitCode
    fi
}

ensureWeAreUser() {
    if [[ $(whoami) = 'root' ]]; then
        echo "Error: must be normal user to run ${0##*/}"
        exit 2
    fi
}

function allKeys() {
  for i in "rsa" "ecdsa256" "ecdsa384"
    do
      keyType=$i
      genKey
      wait
    done
}

#This function will create a private key that is needed to create a private keystore. Encryption keyType passed will decide which command to run for private key creation
function genKey() {
#Check if the folder is already created for the keyType (In case of multiple runs)
    mkdir -p "${keyType}"Key && cd "${keyType}"Key
#Generate a private RSA key.
if [[ $keyType = "rsa" ]]; then
    echo -e "Generating a "${keyType}"private key.\n"
    openssl genrsa -out "${keyType}"private-key.pem 2048 >out 2>&1
    chk $? 'Generating rsa private key.'
    keyCertGenerator
#Generate a private ecdsa (256 or 384) key.
elif [[ $keyType = "ecdsa256" ]] || [[ $keyType = "ecdsa384" ]]; then
    echo -e "Generating a "${keyType}"private key.\n"
    local var2=$(echo $keyType | cut -f2 -da)
    openssl ecparam -genkey -name secp"${var2}"r1 -out "${keyType}"private-key.pem >out 2>&1
    chk $? 'Generating ecdsa private key.'
    keyCertGenerator
fi
}

#This function will create a keyCertificate that is needed to create a corresponding public key, as well as a private keystore.
function keyCertGenerator() {
  if [[ -f "${keyType}"private-key.pem ]]; then
    local privateKey=""${keyType}"private-key.pem"
    local keyCert=""${keyType}"Cert.crt"
    echo -e "\n"${keyType}" private key creation: SUCCESS"
    echo '-------------------------------------------------'
    #Generate a self-signed certificate from the private key file.
    #You should have these environment variables set.
    echo -e "Generating a corresponding certificate.\n"
    ( echo $countryName ; echo "." ; echo $cityName ; echo $orgName ; echo "." ; echo "." ; echo $emailName ) | ( openssl req -x509 -key "$privateKey" -days 365 -out "$keyCert" ) >certInfo.txt 2>&1
    chk $? 'generating certificate'
    if [[ -f $keyCert  ]]; then
      echo -e "\n"${keyType}"Key Certificate creation: SUCCESS"
      genKeyStore
    else
      echo "Owner "${keyType}"Key Certificate not found"
      exit 2
    fi
  else
    echo ""${keyType}"private-key.pem not found"
    exit 2
  fi
}

function genKeyStore(){
  # This function is ran after the private key and owner certificate has been created. This function will create a public key to correspond with
  # the owner private key/certificate. After the public key is made it will then place the private key and certificate inside a keystore.
  # Generate a public key from the certificate file
  openssl x509 -pubkey -noout -in $keyCert > "${keyType}"pub-key.pem
  chk $? 'Creating public key...'
  echo '-------------------------------------------------'
  echo "Creating public key..."
  cp "${keyType}"pub-key.pem ..
  echo -e "\n"${keyType}" public key creation: SUCCESS"
  echo '-------------------------------------------------'
  if [[ -z "$ownerName" ]]; then
    echo "ownerName is not set"
    exit 1
  fi
  # Convert the keyCertificate and private key into ‘PKCS12’ keystore format:
  openssl pkcs12 -export -in $keyCert -inkey $privateKey -name "${keyType}""${ownerName}" -out "${keyType}"key-store.p12 -password pass:"$SDO_KEY_PWD"
  chk $? 'Converting private key and cert into keystore'
  echo -e "Your private keystore has successfully been created. Your keystore alias is: ""${keyType}""${ownerName}"
  echo '-------------------------------------------------'
  cp "${keyType}"key-store.p12 ..
  cd ..
}

function combineKeys(){
  #This function will combine all private keystores into one, and also concatenate all public keys into one
  if [[ -f "rsakey-store.p12" && "ecdsakey-store.p12" && "ecdsa384key-store.p12" ]]; then
    #Combine all the private keystores into one
    mv rsakey-store.p12 Owner-Private-Keystore.p12
    echo "Combining all keystores in Owner-Private-Keystore.p12"
    echo "Importing keystore rsakey-store.p12 to Owner-Private-Keystore.p12..."
    keytool -importkeystore -destkeystore Owner-Private-Keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore ecdsa256key-store.p12 -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias ecdsa256"${ownerName}"
    keytool -importkeystore -destkeystore Owner-Private-Keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore ecdsa384key-store.p12 -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias ecdsa384"${ownerName}"
    #Combine all the public keys into one
    cat ecdsa256pub-key.pem rsapub-key.pem ecdsa384pub-key.pem > Owner-Public-Key.pem
    rm -- ecdsa*.p12 && rm ecdsa*.pem && rm rsapub*
    if [[ "$KEEP_KEY_FILES" == '1' || "$KEEP_KEY_FILES" == 'true' ]]; then
      echo "Saving all key pairs, because KEEP_KEY_FILES=$KEEP_KEY_FILES"
    else
      echo "Cleaning up key files..."
      #removing all key files except the ones we pass
      for i in "rsa" "ecdsa256" "ecdsa384"
        do
          rm "$i"Key/*
          rmdir "$i"Key
          chk $? 'cleaning up key files...'
        done
fi
    chown user:user Owner-Private-Keystore.p12 Owner-Public-Key.pem
  else
    echo "One or more of the keystores are missing. There should be three keystores of type rsa, ecdsa256, and ecdsa384"
    exit 2
fi
}

function checkPass() {
  #Will check if the SDO_KEY_PWD has already been set, and if SDO_KEY_PWD meets length requirements
 if [[ -z "$SDO_KEY_PWD" ]]; then
    echo "SDO_KEY_PWD is not set"
    exit 1
  elif [[ -n "$SDO_KEY_PWD" ]] && [[ ${#SDO_KEY_PWD} -lt 6 ]]; then
        echo "SDO_KEY_PWD not long enough. Needs at least 6 characters"
        exit 1
  fi
}

function infoKeyCert() {
#You have to enter information in order to generate a custom self signed certificate as a part of your key pair for SDO Owner Attestation. What you are about to enter is what is called a Distinguished Name or a DN.
#There are quite a few fields but you can leave some blank. For some fields there will be a default value, If you enter '.', the field will be left blank."
  : ${countryName:?} ${cityName:?} ${orgName:?} ${emailName:?} ${ownerName:?}
  checkPass
  echo '-------------------------------------------------'
}

#============================MAIN CODE=================================

ensureWeAreUser
infoKeyCert
if [[ -n "$keyType" ]] && [[ "$keyType" = "all" ]]; then
  allKeys
  combineKeys
else
    genKey
fi


