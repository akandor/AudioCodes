# SBCNat.sh
# Bash Shell script for checking current Public IP compare it to the one configured
# in the AudioCodes SBC and change it if needed.
#
# Can be run in a cron job.
# chmod +x SBCNat.sh
# 0 0 * * * /path/to/SBCNat.sh -i <SBC-IP-Adress> -u <Username> -p <Password> -s <srcPortStart> -e <srcPortEnd> -x <NAT Index> -f <Source Interface>
# (example every day at 12am)
#
# Version 1.0.0 (Build 1.0.0-2024-03-07)
# 
# AT
#
#######################################################################################################################################################

#######################################################################################################################################################
#                                                                                                                                                     #
# Dependencies:                                                                                                                                       #
#                                                                                                                                                     #
# JQ and CURL                                                                                                                                         #
# apt-get install jq, curl on Debian-based systems or brew install jq, curl on macOS with Homebrew                                                    #
#                                                                                                                                                     #
#######################################################################################################################################################

#!/bin/bash

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set Variables
LF=$'\r\n'
dependencies=("jq" "curl")

# Check for dependencies
for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo -e "${RED}Error: $dependency is not installed. Please install it. (e.g., apt-get install $dependency on Debian-based systems or brew install $dependency on macOS with Homebrew)${NC}"
        exit 1
    fi
done

# Function to display usage and exit with an error
usage() {
    echo -e "${YELLOW}Usage: $0 -i <SBC-IP-Adress> -u <Username> -p <Password> -s <srcPortStart> -e <srcPortEnd> -x <NAT Index> -f <Source Interface>${NC}"
    exit 1
}

# Parse command line options
while getopts ":i:u:p:s:e:f:x:" opt; do
    case "$opt" in
        i) ipAdress="$OPTARG";;
        u) username="$OPTARG";;
        p) password="$OPTARG";;
        s) srcPortStart="$OPTARG";;
        e) srcPortEnd="$OPTARG";;
        x) natIndex="$OPTARG";;
        f) sourceInterface="$OPTARG";;
        *) usage;;
    esac
done

# Check if mandatory arguments are provided
if [ -z "$ipAdress" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$srcPortStart" ] || [ -z "$srcPortEnd" ] || [ -z "$natIndex" ] || [ -z "$sourceInterface" ]; then
    echo -e "${RED}Error: Mandatory arguments are missing.${NC}"
    usage
fi

# Get Public IP Adress
mypublicip=$(dig @resolver1.opendns.com myip.opendns.com +short)
if [ -z "$mypublicip" ]; then
    echo -e "${RED}Error: Could not get public ip.${NC}"
    exit
fi

# Read INI File from SBC
fullini=$(curl -s -X GET --user ${username}:${password} http://${ipAdress}/api/v1/files/cliScript)

# Extract IP address using grep and awk
rawTargetIPString=$(echo "$fullini" | grep -oE 'target-ip-address "([0-9]{1,3}\.){3}[0-9]{1,3}"' | head -1 | awk '{print $2}')
targetIPString="${rawTargetIPString//\"}"

# Check if the IPs are different
if [ "$targetIPString" != "$mypublicip" ]; then
    echo -e "${YELLOW}New Public IP found!${NC}"

    # Create INI File Body
    cliData="configure network${LF}nat-translation ${natIndex}${LF}src-interface-name \"${sourceInterface}\"${LF}target-ip-address \"$mypublicip\"${LF}src-start-port \"$srcPortStart\"${LF}src-end-port \"$srcPortEnd\"${LF}activate"
    boundary=$(uuidgen)
    bodyLines="--$boundary${LF}Content-Disposition: form-data; name=\"file\"; filename=\"file.txt\"${LF}Content-Type: application/octet-stream${LF}${LF}$cliData${LF}--$boundary--$LF"
    body=$(printf "%s$LF" "${bodyLines[@]}")

    changeIP=$(curl -s -X PUT http://${ipAdress}/api/v1/files/cliScript/incremental --user ${username}:${password} -H "Content-Type: multipart/form-data; boundary=$boundary" --data-binary "$body")

    # Get Status from curl command
    statusString=$(echo "$changeIP" | jq -r '.status')
    if [ "$statusString" == "success" ]; then
        echo -e "${GREEN}New public ip successfully uploaded to SBC.${NC}"
        echo -e "${YELLOW}Saving configuration now.${NC}"
        saveConfig=$(curl -s -X POST -u ${username}:${password} -d "" http://${ipAdress}/api/v1/actions/saveConfiguration)
        echo -e "${GREEN}All Done!${NC}"
    else
        echo -e "${RED}There was an error:${NC}"
        echo "$changeIP" | jq -r '.output'
    fi
else
    echo -e "${GREEN}No new public IP. Nothing to do. :-)${NC}"
fi