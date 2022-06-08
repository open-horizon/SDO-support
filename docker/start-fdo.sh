#!/bin/bash

# Used to start the FDO Owner and RV service the Horizon management hub (IoT platform/owner) needs.

# Defaults/constants
ownerPortDefault='8042'
rvPortDefault='8040'
manufactPortDefault='8039'

# These can be passed in via CLI args or env vars
ownerApiPort="${1:-$ownerPortDefault}"  # precedence: arg, or tls port, or non-tls port, or default
ownerPort=${FDO_OWNER_PORT:-$ownerPortDefault}
ownerExternalPort=${FDO_OWNER_EXTERNAL_PORT:-$ownerPort}
manufacturerPort=${FDO_MANUFACT_PORT:-$manufactPortDefault}
rvPort=${FDO_RV_PORT:-$rvPortDefault}
#VERBOSE='true'   # let it be set by the container provisioner

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<owner-api-port>]

Environment variables that can be used instead of CLI args: FDO_OWNER_PORT
Required environment variables: HZN_EXCHANGE_URL, HZN_FSS_CSSURL
Recommended environment variables: HZN_MGMT_HUB_CERT (unless the mgmt hub uses http or a CA-trusted certificate), SDO_KEY_PWD (unless using sample key files)
Additional environment variables: FDO_RV_PORT, FDO_MANUFACT_PORT, FDO_OWNER_EXTERNAL_PORT, EXCHANGE_INTERNAL_URL, VERBOSE
EndOfMessage
    exit 1
fi


# Only echo this if VERBOSE is 1 or true
verbose() {
    if [[ "$VERBOSE" == '1' || "$VERBOSE" == 'true' ]]; then
        echo 'Verbose:' "$*"
    fi
}

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

isDockerComposeAtLeast() {
    : ${1:?}
    local minVersion=$1
    if ! command -v docker-compose >/dev/null 2>&1; then
        return 1   # it is not even installed
    fi
    # docker-compose is installed, check its version
    lowerVersion=$(echo -e "$(docker-compose version --short)\n$minVersion" | sort -V | head -n1)
    if [[ $lowerVersion == $minVersion ]]; then
        return 0   # the installed version was >= minVersion
    else
        return 1
    fi
}

# # If postgres isn't installed, do that
# if ! command -v postgres --version 2>&1; then
#     if [[ $(whoami) != 'root' ]]; then
#         echo "Error: docker is not installed, but we are not root, so can not install it for you. Exiting"
#         exit 2
#     fi
#     echo "Postgres is required, installing it..."
#     apt-get install -y postgresql postgresql-contrib
#     sudo apt install postgresql-client-common
#     chk $? 'installing postgres'
# fi

if [[ -z "$HZN_EXCHANGE_USER_AUTH" ]]; then
    echo "Error: This environment variable must be set to access Owner services APIs: HZN_EXCHANGE_USER_AUTH"
    exit 0
fi

# If haveged isnt installed, install it !
sudo apt-get install haveged
# If docker isn't installed, do that
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required, installing it..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    chk $? 'adding docker repository key'
    add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    chk $? 'adding docker repository'
    apt-get install -y docker-ce docker-ce-cli containerd.io
    chk $? 'installing docker'
fi

# If docker-compose isn't installed, or isn't at least 1.21.0 (when docker-compose.yml version 2.4 was introduced), then install/upgrade it
# For the dependency on 1.21.0 or greater, see: https://docs.docker.com/compose/release-notes/
minVersion=1.21.2
if ! isDockerComposeAtLeast $minVersion; then
    if [[ -f '/usr/bin/docker-compose' ]]; then
        echo "Error: Need at least docker-compose $minVersion. A down-level version is currently installed, preventing us from installing the latest version. Uninstall docker-compose and rerun this script."
        exit 2
    fi
    echo "docker-compose is not installed or not at least version $minVersion, installing/upgrading it..."
    # Install docker-compose from its github repo, because that is the only way to get a recent enough version
    curl --progress-bar -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chk $? 'downloading docker-compose'
    chmod +x /usr/local/bin/docker-compose
    chk $? 'making docker-compose executable'
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    chk $? 'linking docker-compose to /usr/bin'
fi

echo "Using ports: Owner Service: $ownerPort, RV: $rvPort"
##Change from default H2 databse to postgresql


# Run key generation script
echo "Running key generation script..."
(cd fdo/pri-fidoiot-v1.1.0.2/scripts && ./keys_gen.sh)
# Replacing component credentials 
(cd fdo/pri-fidoiot-v1.1.0.2/scripts && cp -r creds/. ../)


if [[ "$FDO_DEV" == '1' || "$FDO_DEV" == 'true' ]]; then

    echo "Using local testing configuration, because FDO_DEV=$FDO_DEV"
    #Configuring Owwner services for development
    sed -i -e '/ports:/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/owner/docker-compose.yml
    chk $? 'sed ports for owner/docker-compose.yml'
    sed -i -e '/- "8042:8042"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/owner/docker-compose.yml
    chk $? 'sed 8042 for owner/docker-compose.yml'
    sed -i -e '/- "8043:8043"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/owner/docker-compose.yml
    chk $? 'sed 8043 for owner/docker-compose.yml'

    #Disabling https for development/testing purposes
    sed -i -e '/- org.fidoalliance.fdo.protocol.StandardOwnerSchemeSupplier/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml'
    sed -i -e 's/#- org.fidoalliance.fdo.protocol.HttpOwnerSchemeSupplier/- org.fidoalliance.fdo.protocol.HttpOwnerSchemeSupplier/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml'

    #Configuring local RV server for development
    sed -i -e '/ports:/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    sed -i -e '/- "8040:8040"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    sed -i -e '/- "8041:8041"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    #sed -i -e '/network_mode: host/ s/./#&/' rv/docker-compose.yml
    chk $? 'sed rv/docker-compose.yml'


sed -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/device/service.yml

sed -e 's/di-url: http.*/di-url: 'localhost'/' fdo/pri-fidoiot-v1.1.0.2/device/service.yml


    sed -e '/network_mode: host/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/manufacturer/docker-compose.yml
    chk $? 'sed manufacturer/docker-compose.yml'

    #Use HZN_EXCHANGE_USER_AUTH for Owner and RV services API password
    USER_AUTH=$HZN_EXCHANGE_USER_AUTH
    removeWord="apiUser:"
    api_password=${USER_AUTH//$removeWord/}
    sed -i -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/owner/service.env
    sed -i -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/rv/service.env
    sed -i -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/manufacturer/service.env

    #Delete owner and rv service db files here if re-running in a test environment
    #rm fdo/pri-fidoiot-v1.1.0.2/owner/app-data/emdb.mv.db && fdo/pri-fidoiot-v1.1.0.2/rv/app-data/emdb.mv.db
    
else

    #Comment out network_mode: host for Owner services. Need TLS work
    sed -i -e '/network_mode: host/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/owner/docker-compose.yml
    #Postgresql substitution in docker-compose.yml

fi



# Run all of the services
echo "Starting owner service..."
#(cd owner && java -jar aio.jar)
(cd fdo/pri-fidoiot-v1.1.0.2/owner && docker-compose up --build  -d) 

echo "Starting rendezvous service..."
#(cd rv && java -jar aio.jar)
(cd fdo/pri-fidoiot-v1.1.0.2/rv && docker-compose up --build  -d)  
