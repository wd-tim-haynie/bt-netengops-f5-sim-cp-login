#!/bin/bash
#version 1.1

# For testing - should remain commented for production use since these parameters can be passed by the F5 external monitor
#USERNAME=test-username
#PASSWORD=test-password

# Get IP and port from automatically passed arguments 1 and 2, convert IP from IPv6 compatible format to IPv4, this is standard behavior for F5 external monitors
IP=`echo ${1} | sed 's/::ffff://'`
PORT=${2}

# Define your URL
URL_PREFIX="https://${IP}:${PORT}"
URI=/guest/auth_login.php
URL="${URL_PREFIX}${URI}"

# Find and remove old cookie files
find /tmp -name "`basename ${0}`.${IP}_${PORT}_*.cookie" -type f -delete > /dev/null 2>&1

# Define the name of a temporary file to store the cookies
cookie_file="/tmp/`basename ${0}`.${IP}_${PORT}_$$.cookie"

# Define a function to be called if the script exits,
# ensure the temporary file is removed when the script exits.
cleanup() {
    rm -f "$cookie_file" > /dev/null 2>&1
}
trap cleanup EXIT

PIDFILE="/var/run/`basename ${0}`.${IP}_${PORT}.pid"
# kill of the last instance of this monitor if hung and log current pid
if [ -f $PIDFILE ]
then
   echo "EAV exceeded runtime needed to kill ${IP}:${PORT}" | logger -p local0.error > /dev/null 2>&1
   kill -9 `cat $PIDFILE` > /dev/null 2>&1
fi
echo "$$" > $PIDFILE

# Get the initial cookie and ntok - these commands should not be redirected to /dev/null since the outputs need to be stored in variables
init_response=$(curl -k -c $cookie_file -s -S "$URL")
ntok=$(echo "$init_response" | grep -oP 'name="ntok" id="[^"]*" value="\K[^"]*')

# Check if ntok is valid
if ! [[ $ntok =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid ntok for ${IP}:${PORT}" | logger -p local0.error > /dev/null 2>&1
    exit 1
fi

# Log in with the cookie and ntok
http_code=$(curl -k -b $cookie_file -w "%{http_code}" -d "target=&ntok=$ntok&static_u=&no_u=&no_p=&username=$USERNAME&F_password=0&password=$PASSWORD" "$URL" -s -S -o /dev/null)

# Expecting a 302 redirect upon successful login - set RECV to 302 in config
if [[ $http_code -eq 302 ]]; then
    URI=/guest/auth_logout.php
    URL="${URL_PREFIX}${URI}"
    http_code=$(curl -k -b $cookie_file -w "%{http_code}" "$URL" -s -S -o /dev/null)
    if [[ $http_code -eq 302 ]]; then 
        echo UP
    fi
fi
#
