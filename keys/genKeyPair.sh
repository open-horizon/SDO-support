#!/bin/bash
# This script will generate a Key-Pair for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [encryption-type]

Arguments:
  <encryption-type>  The type of encryption to use when generating owner key pair (ecdsa256, ecdsa384, rsa). Will default to all

EndOfMessage
    exit 1
fi

TYPE="${1:-all}"
CERT=""
privateKey=""

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
    openssl genrsa -out "${TYPE}"private-key.pem 2048
    chk $?
    certGenerator
#Generate a private ecdsa (256 or 384) key.
elif [[ $TYPE = "ecdsa256" ]] || [[ $TYPE = "ecdsa384" ]]; then
    var2=$(echo $TYPE | cut -f2 -da)
    openssl ecparam -genkey -name secp"${var2}"r1 -out "${TYPE}"private-key.pem
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
        echo -e "___________________________\n"
#Generate a self-signed certificate from the private key file.
#Your system should launch a text-based questionnaire for you to fill out.
        echo -e "Generating a corresponding certificate. It will ask you to input information that is OPTIONAL\n"
        echo -e "___________________________\n"
        openssl req -x509 -key "$privateKey" -days 365 -out "$CERT"
        chk $?
        genKeyStore
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
      chk $?
      echo "\n"
      echo "Your public key has been created"
      scp "${TYPE}"pub-key.pub ..
      echo -e "___________________________\n"
      echo -e "\nGenerating a PRIVATE KEYSTORE. You will need to create a password of atleast 6 characters ( Use '123456' for testing ) \n"
    # Convert the certificate and private key into ‘PKCS12’ keystore format:
    openssl pkcs12 -export -in $CERT -inkey $privateKey -name "${TYPE}"Owner -out "${TYPE}"key-store.p12
    chk $?
    echo -e "___________________________\n"
    echo -e "Your private keystore has successfully been created. Your keystore alias is: ""${TYPE}"Owner
    scp "${TYPE}"key-store.p12 ..
    cd ..
}

function combineKeys(){
  #This function will combine all private keystores into one, and also concatenate all public keys into one
  if [[ -f "rsakey-store.p12" && "ecdsa256key-store.p12" && "ecdsa384key-store.p12" ]]; then
    echo "key store"
    #Combine all the private keystores into one
    keytool -importkeystore -destkeystore rsakey-store.p12 -deststorepass '123456' -srckeystore ecdsa256key-store.p12 -srcstorepass '123456' -srcstoretype PKCS12 -alias ecdsa256Owner
    keytool -importkeystore -destkeystore rsakey-store.p12 -deststorepass '123456' -srckeystore ecdsa384key-store.p12 -srcstorepass '123456' -srcstoretype PKCS12 -alias ecdsa384Owner
    #Combine all the public keys into one
    cat ecdsa256pub-key.pub rsapub-key.pub ecdsa384pub-key.pub > OWNERpub-key.pub
    mv rsakey-store.p12 Owner-Private-Keystore.p12
    rm -- ecdsa*.p12 && rm ecdsa*.pub && rm rsapub*
    touch Owner-Private-Keystore.p12 OWNERpub-key.pub && chown user:user Owner-Private-Keystore.p12 OWNERpub-key.pub
  else
    echo "One or more of the keystores are missing."
    exit
fi
}

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


