package data

// Data for OCS Config Files -------------------
// Is there a better way to handle this?

var PsiJson = `[
  {
    "module": "sdo_sys",
    "msg": "maxver",
    "value": "1"
  }
]`

// this one is optional, that's why it is separate
var SviJson1 = `
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-crt_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.crt",
    "enc": "base64"
  },`

var SviJson2 = `
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-cfg_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.cfg",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "apt-repo-public-key_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "apt-repo-public.key",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-sh_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.sh",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-wrapper-sh_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install-wrapper.sh",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "exec",
    "valueLen": -1,
    "valueId": "`

// need to put the uuid between these 2

var SviJson3 = `_exec",
    "enc": "base64"
  }
`

var AgentInstallWrapper = `#!/bin/sh

# The primary purpose of this wrapper is to be able to invoke agent-install.sh in the SDO context and log all of its stdout/stderr

# Verify the number of args is what we are handling below
numRequiredArgs=4
if [ $# -ne $numRequiredArgs ]; then
    echo "Error: expected $numRequiredArgs arguments and received $#"
    exit 2
fi

echo "$0 starting..."

# This script has a 2nd purpose in the native client case: when run inside the docker sdo container, copy the downloaded files to outside the container
if [ -f /target/boot/inside-sdo-container ]; then
    # Copy all of the downloaded files (including ourselves) to /target/boot, which is mounted from host /var/horizon/sdo-native
    echo "Copying downloaded files to /target/boot: $(ls | tr "\n" " ")"
    # need to exclude a few files and dirs, so copy with find
    find . -maxdepth 1 -type f ! -name inside-sdo-container ! -name linux-client ! -name run_csdk_sdo.sh -exec cp -p -t /target/boot/ {} +
    if [ $? -ne 0 ]; then echo "Error: can not copy downloaded files to /target/boot"; fi
    # The <device-uuid>_exec file is not actually saved to disk, so recreate it (with a fixed name)
    echo "/bin/sh agent-install-wrapper.sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" \"$8\" " > /target/boot/device_exec
    chmod +x /target/boot/device_exec
    echo "Created /target/boot/device_exec: $(cat /target/boot/device_exec)"
    exit
    # now the sdo container will exit, then our owner-boot-device script will find the files and run them
fi

mkdir -p /var/sdo
logFile=/var/sdo/agent-install.log
echo "Logging all output to $logFile"

# When SDO transfers agent-install.sh to the device, it does not make it executable
chmod 755 agent-install.sh

# If tee is installed, use it so the output can go to both stdout/stderr and the log file
if command -v tee >/dev/null 2>&1; then
    # Note: the individual arg variables need to be listed like this and quoted to handle spaces in an arg
    # "bash agent-install.sh -i " + aptRepo + " -t " + aptChannel + " -j apt-repo-public.key -d " + uuid.String() + ":" + nodeToken
    exec ./agent-install.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" 2>&1 | tee $logFile
else
    exec ./agent-install.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" 2>&1 > $logFile
fi
#exit 2   # it only gets here if exec failed
`
