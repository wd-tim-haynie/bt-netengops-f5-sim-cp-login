#!/bin/bash

#sim-cp-login.sh
#Version 1.5 June 20, 2023
#https://github.com/wd-tim-haynie/bt-netengops-f5-sim-cp-login
#Author: Tim Haynie, CWNE #254, ACMX #508 https://www.linkedin.com/in/timhaynie/

# Note the start time
START_TIME=$(date +%s%N)

# Remove “::ffff:” from the IP passed as the first argument. Compatible with both IPv4 and IPv6, unless your IPv6 IP includes ::ffff:
IP=$(echo ${1} | sed 's/::ffff://')
PORT=${2}  # The port number is the second argument

# Uncomment the following lines for testing at CLI
#USERNAME='test-username'
#PASSWORD='test-password'
#ENCRYPTED_PASSWORD="U2FsdGVkX19tKPeA3hWRZcfGl6H+ILXks2VtidUEbb7unSw7NAzzIg/OYWl+Myx8"
#LOG_LEVEL="err"
#DECRYPTION_KEY_FILE_NAME="sim_cp_login.key"

# Logging section
# Logging level hierarchy (in order of severity)
declare -A ALL_LOG_LEVELS=( ["debug"]=0 ["info"]=1 ["notice"]=2 ["warn"]=3 ["err"]=4 ["crit"]=5 ["alert"]=6 ["emerg"]=7 )
ALL_LOG_LEVELS_STR=$(echo ${!ALL_LOG_LEVELS[@]})

LOG_MESSAGE() {
    # Check if provided log level is valid
    if [[ -n "${ALL_LOG_LEVELS[$2]}" ]]
    then
        # If LOG_LEVEL is set and its severity is less than or equal to the provided log level, log the message
        if [[ -n "$LOG_LEVEL" && ${ALL_LOG_LEVELS[$2]} -ge ${ALL_LOG_LEVELS[$LOG_LEVEL]} ]]
        then
            # Log the message with the provided level
            echo "$MON_TMPL_NAME PID: $$ Name: $NODE_NAME IP: $IP Port: $PORT $1" | logger -p local0.$2 > /dev/null 2>&1
        fi
    else
        # Log level is invalid, log a warning
        LOG_MESSAGE "Invalid log level \"$2\" for provided log. Valid levels are: $ALL_LOG_LEVELS_STR. Message: $1" "warn"
    fi
}

# Validate LOG_LEVEL, unset to disable logging if it is invalid
if [[ -z "$LOG_LEVEL" ]]
then
    : # Do nothing, it's already empty, logging is disabled
elif [[ -z "${ALL_LOG_LEVELS[$LOG_LEVEL]}" ]]
then
    # LOG_LEVEL is either null or invalid, disable logging
    PROVIDED_LOG_LEVEL=${LOG_LEVEL}
    LOG_LEVEL="warn"
    LOG_MESSAGE "Invalid LOG_LEVEL \"$PROVIDED_LOG_LEVEL\", disabling additional logging" "warn"
    unset LOG_LEVEL
fi

# End of Logging section

# Decrypt the password if ENCRYPTED_PASSWORD is not empty (-n)
if [[ -n "$ENCRYPTED_PASSWORD" ]]
then

    # Locate the key file. Use head to only take a single entry and discard any other matches.
    DECRYPTION_KEY_FILE_PATH=$(ls /config/filestore/files_d/Common_d/ifile_d/:Common:${DECRYPTION_KEY_FILE_NAME}_* 2> /dev/null | head -n 1)
    LOG_MESSAGE "Decryption Key File Path: $DECRYPTION_KEY_FILE_PATH" "info"

    # Check to see if its not empty (-n) and a real file (-f)
    if [[ -n "$DECRYPTION_KEY_FILE_PATH" && -f "$DECRYPTION_KEY_FILE_PATH" ]]
    then
        # Read the first line of the decryption key file
        read -r DECRYPTION_KEY < "$DECRYPTION_KEY_FILE_PATH" 2> /dev/null
        #LOG_MESSAGE "Decryption Key: $DECRYPTION_KEY" "debug"
        #echo "Decryption Key: $DECRYPTION_KEY" >> /path/to/outputfile

        # Check to see if the key is empty
        if [[ -z "$DECRYPTION_KEY" ]]
        then
            LOG_MESSAGE "Decryption file exists but seems empty" "err"
            exit 1
        fi
    else # We couldn't find the key file
        LOG_MESSAGE "Decryption file not found" "err"
        exit 1
    fi    

    # Use openssl to decrypt the password
    PASSWORD=$(echo "$ENCRYPTED_PASSWORD" | openssl enc -aes-256-cbc -d -a -k "$DECRYPTION_KEY" 2> /dev/null)
    #LOG_MESSAGE "Decrypted Password: $PASSWORD" "debug"
    #echo "Decrypted Password: $PASSWORD" >> /path/to/outputfile
    
    # If there's a problem with openssl, then password will be blank.
    if [[ -z "$PASSWORD" ]]
    then
        LOG_MESSAGE "An error occurred with openssl" "err"
        exit 1
    fi
fi

# Define temporary files
COOKIE_FILE="/tmp/$(basename ${MON_TMPL_NAME})_${IP}_${PORT}_$$.cookie"
PID_FILE="/var/run/$(basename ${MON_TMPL_NAME})_${IP}_${PORT}.pid"

# Cleanup previous cookie if it exists
rm -f "/tmp/$(basename ${MON_TMPL_NAME}).${IP}_${PORT}_$(cat "$PID_FILE" 2> /dev/null).cookie" > /dev/null 2>&1

# Cleanup function to ensure removal of temporary files on script exit
CLEANUP() {
    rm -f "$COOKIE_FILE" > /dev/null 2>&1
    rm -f "$PID_FILE" > /dev/null 2>&1
}

# Setup trap to call cleanup function on script exit
trap CLEANUP EXIT

# Kill the last instance of this monitor if it is hung, and log the current PID
if [ -f "$PID_FILE" ]
then
   PID=$(cat "$PID_FILE")
   if kill -0 "$PID" 2>/dev/null
   then
       LOG_MESSAGE "EAV exceeded runtime, killing previous instance" "err"
       kill "$PID" > /dev/null 2>&1
   fi
fi

# Set the PID file (overwrites previous value)
echo "$$" > "$PID_FILE"

# Begin the actual monitor
# Define the URL
URL_PREFIX="https://${IP}:${PORT}"
URI="/guest/auth_login.php"
URL="${URL_PREFIX}${URI}"

# Get the initial cookie and ntok
INIT_RESPONSE=$(curl -k -c "$COOKIE_FILE" -s -S "$URL" -H 'Accept-Encoding: identity' -H "Connection: close")
NTOK=$(echo "$INIT_RESPONSE" | grep -oP 'name="ntok" id="[^"]*" value="\K[^"]*')

# Check if ntok is valid - 40 hex characters
if ! [[ -n "$NTOK" ]]
then
    LOG_MESSAGE "Couldn't find ntok" "err"
    exit 1
fi

# Log in with the cookie, ntok, username, and password
CURL_DATA="target=&ntok=$NTOK&static_u=&no_u=&no_p=&username=$USERNAME&F_password=0&password=$PASSWORD"
HTTP_CODE=$(curl -k -b "$COOKIE_FILE" -w "%{http_code}" -d $CURL_DATA "$URL" -s -S -H 'Accept-Encoding: identity' -H "Connection: close" -o /dev/null)

# A function to check any URIs passed as arguments from the monitor
CHECK_URIS() {
    # Loop through each argument provided
    for URI in "$@"
    do
        # Define the URL
        URL="${URL_PREFIX}${URI}"

        # Run a curl command to the URI and save the HTTP code and body
        CURL_OUTPUT=$(curl -k -i -s -S "$URL" -H 'Accept-Encoding: identity' -H "Connection: close")

        # Extract the HTTP status code and body
        HTTP_CODE=$(echo "$CURL_OUTPUT" | grep HTTP | awk '{print $2}' | tail -n 1)
        HTTP_BODY=$(echo "$CURL_OUTPUT" | awk '{x[NR]=$0} END{for (i=1; i<=NR-1; i++) print x[i]}' )
        
        # Debug logs
        LOG_MESSAGE "Testing URI $URI" "debug"
        LOG_MESSAGE "HTTP Status Code: $HTTP_CODE" "debug"

        if [[ $HTTP_BODY == *"html"* ]]
        then
            LOG_MESSAGE "HTTP body contain html: True" "debug"
        else
            LOG_MESSAGE "HTTP body contains html: False" "debug"
        fi

        # Check if the HTTP code is not 200 or the body does not contain "html"
        if [[ $HTTP_CODE -ne 200 || $HTTP_BODY != *"html"* ]]
        then
            LOG_MESSAGE "Failed to validate URI $URI" "err"
            exit 1
        fi
    done
}

# Expecting a 302 redirect upon successful login
if [[ $HTTP_CODE -eq 302 ]]
then
    URI="/guest/auth_logout.php"
    URL="${URL_PREFIX}${URI}"
    HTTP_CODE=$(curl -k -b "$COOKIE_FILE" -w "%{http_code}" "$URL" -s -S -H 'Accept-Encoding: identity' -H "Connection: close" -o /dev/null)

    # Warn if logout fails, but don't quit
    if ! [[ $HTTP_CODE -eq 302 ]]
    then
        LOG_MESSAGE "Failed to logout" "warn"
    fi

    # Call the new function to check URIs passed as arguments
    CHECK_URIS "${@:3}"

    END_TIME=$(date +%s%N)
    ELAPSED_TIME=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000}")
    LOG_MESSAGE "Succeeded after $ELAPSED_TIME ms" "notice"

    CLEANUP
    
    echo UP
    exit 0
else
    LOG_MESSAGE "Incorrect username or password, or bad decryption key" "err"
    exit 1
fi
