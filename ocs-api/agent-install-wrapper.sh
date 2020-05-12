#!/bin/bash

# The primary purpose of this wrapper is to be able to invoke agent-install.sh in the SDO context and log all of its stdout/stderr

logFile=/tmp/agent-install.log
echo "Logging all output to $logFile"

# Verify the number of args is what we are handling below
numRequiredArgs=8
if [[ $# -ne $numRequiredArgs ]]; then
    echo "Error: expected $numRequiredArgs arguments and received $#"
    exit 2
fi

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
exit 2   # it only gets here if exec failed
