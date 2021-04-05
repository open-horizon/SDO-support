#!/bin/bash
# This script will migrate sdo 1.8 formatted owner public keys to the new sdo 1.9+ format for owner public keys.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} <1.8-public-key-file>

Arguments:
  <1.8-public-key-file>  A file containing the 3 public keys concatenated in SDO v1.8 format

EndOfMessage
    exit 0
fi


if [[ -z "$1" || ! -f "$1" ]]; then
    echo "Error: Owner public keys file not specified or does not exist: $1"
    exit 1
fi
PubKeys="$1"


function migrateKeys() {

#Splitting first 4 lines of owner-public-key 1.8 file into ecdsa256 file
  (head -4 > ecdsa256pub-key.pem; cat > rest.pem) < $PubKeys
#Splitting next 9 lines of owner-public-key 1.8 file into rsa file and the rest in ecdsa356
  (head -9 > rsapub-key.pem; cat > ecdsa384pub-key.pem) < rest.pem
  echo "," >> ecdsa256pub-key.pem && echo "," >> rsapub-key.pem
    echo "Concatenating Public Key files..."
    for i in "rsapub-key.pem" "ecdsa256pub-key.pem" "ecdsa384pub-key.pem"
      do
        local keyName=$i
        local removeWord="pub-key.pem"
        keyName=${keyName//$removeWord/}
        #adding (type) delimiters for SDO 1.9+ pub key format
        echo ""$keyName":" >key.txt
        cat key.txt $i >> 2owner-public-key.pem
      done
    rm -- ecdsa*.pem && rm rsapub* && rm key.txt && rm rest.pem
    if [[ -d "newPubKey" ]]; then
          rm -rf newPubKey
    fi
    mkdir newPubKey && mv 2owner-public-key.pem newPubKey/owner-public-key.pem
    echo "Newly migrated public key can be found in newPubKey directory"
  }

#============================MAIN CODE=================================
migrateKeys
