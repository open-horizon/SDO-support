#!/bin/bash
# This script will extract a tarfile containing all private keys and certs necessary to add the Key-Pairs to our master keystore inside the container for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<owner-keys-tar-file>]

Arguments:
  <owner-keys-tar-file>  A tar file containing the 3 private keys and associated 3 certs

Required environment variables:
  HZN_ORG_ID - The custom org the user chooses. Necessary information to import keystore into our master keystore.

EndOfMessage
    exit 0
fi

if [[ -n "$1" && -f "$1" ]]; then
  TARFILE="$1"
fi

# Grab the owner keystore password from ocs/ocs.env inside the container, to use for import
keypwd="$(grep -E '^ *FS_OWNER_KEYSTORE_PASSWORD=' ocs/ocs.env)"
SDO_KEY_PWD=${keypwd#*FS_OWNER_KEYSTORE_PASSWORD=}

if [[ ! -f $TARFILE ]]; then
    echo "Error: No owner keys tarfile '$TARFILE' found."
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

function untarKeyFiles(){
  #This function unpacks the tar file passed in through the OCS API
  if [[ -n "$TARFILE" && -f "$TARFILE" ]]; then
    tar -xf $TARFILE
    chk $? 'Extracting key pairs from tarball'
  else
    echo "owner-keys.tar.gz is not found"
    exit 1
  fi
}

#This function will take the private key and certificate that has been passed in, and use them to generate a keystore pkcs12 file containing both files.
function genKeyStore(){
  for i in "rsa" "ecdsa256" "ecdsa384"
      do
        # Convert the keyCertificate and private key into ‘PKCS12’ keystore format:
        cd "$i"Key/ && openssl pkcs12 -export -in "$i"Cert.crt -inkey "$i"private-key.pem -name "${HZN_ORG_ID}"_"$i" -out "${HZN_ORG_ID}_$i.p12" -password pass:"$SDO_KEY_PWD"
        chk $? 'Converting private key and cert into keystore'
        cp "${HZN_ORG_ID}_$i.p12" .. && rm -- *
        cd .. && rmdir "$i"Key
      done
}

function insertKeys(){
  #This function will insert all private keystores into the master keystore
  if [[ -f "${HZN_ORG_ID}_$i.p12" ]]; then
    for i in "rsa" "ecdsa256" "ecdsa384"
      do
        #Import custom keystores into the master keystore
        echo "yes" | /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -importkeystore -destkeystore ocs/config/db/v1/creds/owner-keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore "${HZN_ORG_ID}_$i.p12" -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias "${HZN_ORG_ID}"_"$i"
        chk $? "Inserting "${HZN_ORG_ID}_$i.p12" keystore into ocs/config/db/v1/creds/owner-keystore.p12"
      done
    rm -- *.p12
  else
    echo "One or more of the keystores are missing. There should be three keystores of type rsa, ecdsa256, and ecdsa384"
    exit 2
fi
}


#============================MAIN CODE=================================

ensureWeAreUser
untarKeyFiles
genKeyStore
insertKeys
echo "Owner private keys and certificates have been imported."



