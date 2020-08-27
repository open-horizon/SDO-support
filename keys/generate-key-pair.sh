#!/bin/bash
# This script will generate a Key-Pair for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [encryption-type]

Arguments:
  <encryption-type>  The type of encryption to use when generating owner key pair (ecdsa256, ecdsa384, rsa, or all). Will default to all.

Additional environment variables (that do not usually need to be set):
  SDO_KEY_PWD - The password for your generated keystore. This password must match $containerHome/ocs/config/application.properties/fs.owner.keystore-password
  KEEP_KEY_FILES - set to 'true' to keep all key pairs generated for each type of key (ecdsa256, ecdsa384, rsa). This is for devs who may want to check out each individual file that goes into generating Key pairs.

EndOfMessage
    exit 1
fi

TYPE="${1:-all}"
CERT=""
privateKey=""
KEEP_KEY_FILES=${KEEP_KEY_FILES:-}
SDO_KEY_PWD=${SDO_KEY_PWD:-}


#============================FUNCTIONS=================================

#If the argument passed for this script does not equal one of the encryption types, send error code and exit.
#BY DEFAULT THE TYPE WILL BE SET TO all
if [[ -n "$TYPE" ]] && [[ "$TYPE" != "ecdsa256" ]] && [[ "$TYPE" != "ecdsa384" ]] && [[ "$TYPE" != "rsa" ]] && [[ "$TYPE" != "all" ]]; then
    echo "Error: specified encryption type '$TYPE' is not supported."
    exit 2
fi

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

#This function will create a private key that is needed to create a private keystore. Encryption type passed will decide which command to run for private key creation
function genKey() {
#Check if the folder is already created for the type (In case of multiple runs)
if [[ -d "${TYPE}"Key ]]; then
    cd "${TYPE}"Key
else
    mkdir "${TYPE}"Key && cd "${TYPE}"Key
fi
#Generate a private RSA key.
if [[ $TYPE = "rsa" ]]; then
    echo -e "Generating a "${TYPE}"private key.\n"
    openssl genrsa -out "${TYPE}"private-key.pem 2048 > /dev/null 2>&1
    chk $?
    certGenerator
#Generate a private ecdsa (256 or 384) key.
elif [[ $TYPE = "ecdsa256" ]] || [[ $TYPE = "ecdsa384" ]]; then
    echo -e "Generating a "${TYPE}"private key.\n"
    var2=$(echo $TYPE | cut -f2 -da)
    openssl ecparam -genkey -name secp"${var2}"r1 -out "${TYPE}"private-key.pem > /dev/null 2>&1
    chk $?
    certGenerator
fi
}

#This function will create a key certificate that is needed to create a corresponding public key, as well as a private keystore.
function certGenerator() {
    if [[ -f "${TYPE}"private-key.pem ]]; then
        privateKey=""${TYPE}"private-key.pem"
        CERT=""${TYPE}"cert.crt"
        echo -e "\n"${TYPE}" private key creation: SUCCESS"
        echo '-------------------------------------------------'
#Generate a self-signed certificate from the private key file.
#Your system should launch a text-based questionnaire for you to fill out.
        echo -e "Generating a corresponding certificate.\n"
        ( echo $q1 ; echo $q2 ; echo $q3 ; echo $q4 ; echo $q5 ; echo $q6 ; echo $q7 ) | ( openssl req -x509 -key "$privateKey" -days 365 -out "$CERT" ) > /dev/null 2>&1
        #printf "%s\n""$q1""%s\n""$q2""%s\n""$q3""%s\n""$q4""%s\n""$q5""%s\n""$q6""%s\n""$q7" | openssl req -x509 -key "$privateKey" -days 365 -out "$CERT"
        chk $?
        if [[ -f $CERT  ]]; then
          echo -e "\n"${TYPE}" certificate creation: SUCCESS"
          genKeyStore
        else
          echo "Owner "${TYPE}"Key certificate not found"
          exit
        fi
    else
      echo ""${TYPE}"private-key.pem not found"
      exit
    fi
}

function genKeyStore(){
    # This function is ran after the private key and owner certificate has been created. This function will create a public key to correspond with
    # the owner private key/certificate. After the public key is made it will then place the private key and certificate inside a keystore.
    # Generate a public key from the certificate file
      openssl x509 -pubkey -noout -in $CERT > "${TYPE}"pub-key.pub
      echo '-------------------------------------------------'
      echo "Creating public key..."
      chk $?
      scp "${TYPE}"pub-key.pub ..
      echo -e "\n"${TYPE}" public key creation: SUCCESS"
      echo '-------------------------------------------------'
    # Convert the certificate and private key into ‘PKCS12’ keystore format:
    openssl pkcs12 -export -in $CERT -inkey $privateKey -name "${TYPE}"Owner -out "${TYPE}"key-store.p12 -password pass:"$SDO_KEY_PWD"
    chk $?
    echo -e "Your private keystore has successfully been created. Your keystore alias is: ""${TYPE}"Owner
    echo '-------------------------------------------------'
    scp "${TYPE}"key-store.p12 ..
    cd ..
}

function combineKeys(){
  #This function will combine all private keystores into one, and also concatenate all public keys into one
  if [[ -f "rsakey-store.p12" && "ecdsakey-store.p12" && "ecdsa384key-store.p12" ]]; then
    #Combine all the private keystores into one
    mv rsakey-store.p12 Owner-Private-Keystore.p12
    echo "Combining all keystores in Owner-Private-Keystore.p12"
    echo "Importing keystore rsakey-store.p12 to Owner-Private-Keystore.p12..."
    keytool -importkeystore -destkeystore Owner-Private-Keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore ecdsa256key-store.p12 -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias ecdsa256Owner
    keytool -importkeystore -destkeystore Owner-Private-Keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore ecdsa384key-store.p12 -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias ecdsa384Owner
    #Combine all the public keys into one
    cat ecdsa256pub-key.pub rsapub-key.pub ecdsa384pub-key.pub > Owner-Public-Key.pub
    rm -- ecdsa*.p12 && rm ecdsa*.pub && rm rsapub*

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
    touch Owner-Private-Keystore.p12 Owner-Public-Key.pub && chown user:user Owner-Private-Keystore.p12 Owner-Public-Key.pub
  else
    echo "One or more of the keystores are missing."
    exit
fi
}

function infoCert() {
  echo -e "\nYou are about to be asked to enter information that will be incorporated into your certificate request to generate your key pair for SDO Owner Attestation. What you are about to enter is what is called a Distinguished Name or a DN.
  There are quite a few fields but you can leave some blank. For some fields there will be a default value, If you enter '.', the field will be left blank."
  echo '-------------------------------------------------'
  echo "Country Name (2 letter code) [AU]:" && read q1
  echo "State or Province Name (full name) [Some-State]:" && read q2
  echo "Locality Name (eg, city) []:" && read q3
  echo "Organization Name (eg, company) [Internet Widgits Pty Ltd]:" && read q4
  echo "Organizational Unit Name (eg, section) []:" && read q5
  echo "Common Name (e.g. server FQDN or YOUR name) []:" && read q6
  echo "Email Address []:" && read q7
  echo "Keystore Password:" && read SDO_KEY_PWD
  echo '-------------------------------------------------'
}

#============================MAIN CODE=================================

ensureWeAreUser
infoCert
if [[ -n "$TYPE" ]] && [[ "$TYPE" = "all" ]]; then
  for i in "rsa" "ecdsa256" "ecdsa384"
    do
      TYPE=$i
      genKey
      wait
    done
  combineKeys
else
    genKey
fi


