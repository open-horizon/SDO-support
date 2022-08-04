#!/bin/bash

# Used to start the FDO Owner and RV service the Horizon management hub (IoT platform/owner) needs.

# Defaults/constants
ownerPortDefault='8042'
rvPortDefault='8040'

workingDir='fdo'
deviceBinaryDir='pri-fidoiot-v1.1.0.2' 
# These can be passed in via CLI args or env vars
ownerApiPort="${1:-$ownerPortDefault}"  # precedence: arg, or tls port, or non-tls port, or default
ownerPort=${HZN_FDO_SVC_URL:-$ownerPortDefault}
ownerExternalPort=${FDO_OWNER_EXTERNAL_PORT:-$ownerPort}
rvPort=${FDO_RV_PORT:-$rvPortDefault}
#VERBOSE='true'   # let it be set by the container provisioner
FDO_SUPPORT_RELEASE=${FDO_SUPPORT_RELEASE:-https://github.com/secure-device-onboard/release-fidoiot/releases/download/v1.1.0.2}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/}

Required environment variables: HZN_EXCHANGE_USER_AUTH, FDO_RV_PORT
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

chkHttp() {
    local exitCode=$1
    local httpCode=$2
    local task=$3
    local dontExit=$4   # set to 'continue' to not exit for this error
    chk $exitCode $task
    if [[ $httpCode == 200 ]]; then return; fi
    echo "Error: http code $httpCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $httpCode
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

###### MAIN CODE ######

if [[ -z "$HZN_EXCHANGE_USER_AUTH" ]]; then
    echo "Error: This environment variable must be set to access Owner services APIs: HZN_EXCHANGE_USER_AUTH"
    exit 0
fi

# Get the other files we need from our git repo, by way of our device binaries tar file
if [[ ! -d $deviceBinaryDir ]]; then
echo "$deviceBinaryDir DOES NOT EXIST"
    deviceBinaryTar="$deviceBinaryDir.tar.gz"
    deviceBinaryUrl="$FDO_SUPPORT_RELEASE/$deviceBinaryTar"
    echo "Removing old PRI tar files, and getting and unpacking $deviceBinaryDir ..."
    rm -rf $workingDir/pri-fidoiot-*   # it is important to only have 1 device binary dir, because the device script does a find to locate device.jar
    mkdir -p $workingDir && cd $workingDir
    httpCode=$(curl -w "%{http_code}" --progress-bar -L -O  $deviceBinaryUrl)
    chkHttp $? $httpCode "getting $deviceBinaryTar"
    tar -zxf $deviceBinaryTar
    cd
fi

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
#make sure Docker daemon is running
sudo chmod 666 /var/run/docker.sock
# If haveged isnt installed, install it !

if ! command haveged --help >/dev/null 2>&1; then
    echo "Haveged is required, installing it"
    sudo apt-get install -y haveged
    chk $? 'installing haveged'
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

if ! command psql --help >/dev/null 2>&1; then
    echo "PostgreSQL is not installed, installing it"
    sudo apt-get install -y postgresql
    chk $? 'installing postgresql'
fi

#zip and unzip are required for editing the manifest file of aio.jar so that it recognizes the postgresql jar
if ! command zip --help >/dev/null 2>&1; then
    echo "zip is not installed, installing it"
    sudo apt-get install -y zip
    chk $? 'installing zip'
fi

if ! command unzip --help >/dev/null 2>&1; then
    echo "unzip is not installed, installing it"
    sudo apt-get install -y unzip
    chk $? 'installing unzip'
fi

#check if database already exists
if ! psql -lqt | cut -d \| -f 1 | grep -qw 'fdo'; then
  #set up database
  sudo -u postgres createdb fdo
  sudo -u postgres psql -c "CREATE USER fdo WITH PASSWORD 'fdo';"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fdo TO fdo;"
fi

#download PostgreSQL JDBC jar
cd fdo/pri-fidoiot-v1.1.0.2/owner/lib
httpCode=$(curl -w "%{http_code}" --progress-bar -L -O  https://jdbc.postgresql.org/download/postgresql-42.4.0.jar)
chkHttp $? $httpCode "getting $deviceBinaryTar"
cd ../../../..

#edit manifest of aio.jar so that it will find the postgresql jar we just downloaded in the lib directory
unzip fdo/pri-fidoiot-v1.1.0.2/owner/aio.jar
chk $? 'unzip'
sed -i -e 's/Class-Path:/Class-Path: lib\/postgresql-42.4.0.jar/' META-INF/MANIFEST.MF
chk $? 'sed classpath of aio.jar manifest'
zip -r fdo/pri-fidoiot-v1.1.0.2/owner/aio.jar org META-INF
chk $? 're-zip'
#clean-up files
rm -r org META-INF
chk $? 'deleting unzipped files'

echo "Using ports: Owner Service: $ownerPort, RV: $rvPort"
##Change from default H2 database to postgresql

# Run key generation script
echo "Running key generation script..."
(cd fdo/pri-fidoiot-v1.1.0.2/scripts && ./keys_gen.sh)
# Replacing component credentials 
(cd fdo/pri-fidoiot-v1.1.0.2/scripts && cp -r creds/. ../)

if [[ "$FDO_DEV" == '1' || "$FDO_DEV" == 'true' ]]; then

    echo "Using local testing configuration, because FDO_DEV=$FDO_DEV"
    #Configuring Owwner services for development, If you are running the local
    #development RV server, then you must disable the port numbers for rv/docker-compose.yml & owner/docker-compose.yml
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

    #configure to use PostgreSQL database
    sed -i -e 's/org.h2.Driver/org.postgresql.Driver/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml driver_class'
    sed -i -e 's/jdbc:h2:tcp:\/\/localhost:8051\/.\/app-data\/emdb/jdbc:postgresql:\/\/localhost:5432\/fdo/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml connection url'
    sed -i -e 's/org.hibernate.dialect.H2Dialect/org.hibernate.dialect.PostgreSQLDialect/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml dialect'
    sed -i -e 's/StandardDatabaseServer/RemoteDatabaseServer/' fdo/pri-fidoiot-v1.1.0.2/owner/service.yml
    chk $? 'sed owner/service.yml database server worker'

    #Configuring local RV server for development
    sed -i -e '/ports:/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    sed -i -e '/- "8040:8040"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    sed -i -e '/- "8041:8041"/ s/./#&/' fdo/pri-fidoiot-v1.1.0.2/rv/docker-compose.yml
    #sed -i -e '/network_mode: host/ s/./#&/' rv/docker-compose.yml
    chk $? 'sed rv/docker-compose.yml'

    #Use HZN_EXCHANGE_USER_AUTH for Owner and RV services API password
    USER_AUTH=$HZN_EXCHANGE_USER_AUTH
    removeWord="apiUser:"
    api_password=${USER_AUTH//$removeWord/}
    sed -i -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/owner/service.env
    sed -i -e 's/api_password=.*/api_password='$api_password'/' fdo/pri-fidoiot-v1.1.0.2/rv/service.env
    #Delete owner and rv service db files here if re-running in a test environment
    #rm fdo/pri-fidoiot-v1.1.0.2/owner/app-data/emdb.mv.db && fdo/pri-fidoiot-v1.1.0.2/rv/app-data/emdb.mv.db

    #override auto-generated DB username and password
    sed -i -e 's/db_user=.*/db_user=fdo/' fdo/pri-fidoiot-v1.1.0.2/owner/service.env
    sed -i -e 's/db_password=.*/db_password=fdo/' fdo/pri-fidoiot-v1.1.0.2/owner/service.env

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
