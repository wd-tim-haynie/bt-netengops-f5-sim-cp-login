#!/bin/bash
# Version 1.2.1

# Note the start time
START_TIME=$(date +%s%N)

# Uncomment the following lines for testing
#USERNAME='test-username'
#PASSWORD='test-password'
#ENCRYPTED_PASSWORD="U2FsdGVkX19tKPeA3hWRZcfGl6H+ILXks2VtidUEbb7unSw7NAzzIg/OYWl+Myx8"

# Remove “::ffff:” from the IP passed as the first argument
IP=${1:7}  # This is fast but not applicable to IPv6 or for testing at CLI
# Uncomment the following line for IPv6 or for testing IPv4 at CLI
#IP=$(echo ${1} | sed 's/::ffff://')

PORT=${2}  # The port number is the second argument

# Enable or disable logging
#LOGGING=true # true or false to turn logging on/off
# Logging level hierarchy (in order of severity)
declare -A LOG_LEVELS=( ["debug"]=0 ["info"]=1 ["notice"]=2 ["warn"]=3 ["err"]=4 ["crit"]=5 ["alert"]=6 ["emerg"]=7 )
# Minimum logging level
#MIN_LOG_LEVEL="err"

ALL_LOG_LEVELS=$(echo ${!LOG_LEVELS[@]})

# If MIN_LOG_LEVEL is not set or is not a valid log level, default it to "warn"
if [[ -z "${MIN_LOG_LEVEL}" || -z "${LOG_LEVELS[$MIN_LOG_LEVEL]}" ]]
then
    if [[ "$LOGGING" == "true" ]]
    then
        MIN_LOG_LEVEL="warn"
        echo "Invalid MIN_LOG_LEVEL ${MIN_LOG_LEVEL} in $MON_TMPL_NAME, defaulting to warn" | logger -p local0.warn > /dev/null 2>&1

    fi
else
    # If MIN_LOG_LEVEL is set to a valid value and LOGGING is null from environment, enable logging
    if [[ -z "$LOGGING" ]]
    then
        LOGGING="true"
    fi
fi

LOG_MESSAGE() {
    # Check if provided log level is valid
    if [[ -n "${LOG_LEVELS[$2]}" ]]
    then
        # Check if logging is enabled and its severity is greater or equal to MIN_LOG_LEVEL
        if [[ $LOGGING == "true" && ${LOG_LEVELS[$2]} -ge ${LOG_LEVELS[$MIN_LOG_LEVEL]} ]]
        then
            # Log the message with the provided level
            echo "$1" | logger -p local0.$2 > /dev/null 2>&1
        fi
    else
        # If the log level provided was invalid, log an error message
        LOG_MESSAGE "Invalid log level provided: Monitor: $MON_TMPL_NAME Message: $1 Level $2. Valid log levels are: ${ALL_LOG_LEVELS}" "err"
    fi
}

# Decrypt the password if ENCRYPTED_PASSWORD is not empty (-n)
if [[ -n "$ENCRYPTED_PASSWORD" ]]
then

    # Locate the key file. Use head to only take a single entry and discard any other matches.
    DECRYPTION_FILE_PATH=$(ls /config/filestore/files_d/Common_d/ifile_d/:Common:sim_cp_login.key_* 2> /dev/null | head -n 1)

    # Check to see if its not empty (-n) and a real file (-f)
    if [[ -n "$DECRYPTION_FILE_PATH" && -f "$DECRYPTION_FILE_PATH" ]]
    then
        read -r DECRYPTION_KEY < "$DECRYPTION_FILE_PATH" 2> /dev/null

        if ! [[ -n "$ENCRYPTED_PASSWORD" ]]
        then
            LOG_MESSAGE "Decryption file exists but seems empty for $MON_TMPL_NAME Name: $NODE_NAME IP: $IP Port: $PORT" "err"
            exit 1
        fi
    else
        LOG_MESSAGE "Decryption file not found for $MON_TMPL_NAME Name: $NODE_NAME IP: $IP Port: $PORT" "err"
        exit 1
    fi    
    PASSWORD=$(echo "$ENCRYPTED_PASSWORD" | openssl enc -aes-256-cbc -d -a -k "$DECRYPTION_KEY" 2> /dev/null)
    if ! [[ -n "$PASSWORD" ]]
    then
        LOG_MESSAGE "An error occurred with openssl for $MON_TMPL_NAME Name: $NODE_NAME IP: $IP Port: $PORT" "err"
        exit 1
    fi
fi

# Define the URL
URL_PREFIX="https://${IP}:${PORT}"
URI="/guest/auth_login.php"
URL="${URL_PREFIX}${URI}"

# Remove old cookie files
find /tmp -name "$(basename ${0}).${IP}_${PORT}_*.cookie" -type f -delete > /dev/null 2>&1

# Define temporary files
COOKIE_FILE="/tmp/$(basename ${0}).${IP}_${PORT}_$$.cookie"
PID_FILE="/var/run/$(basename ${0}).${IP}_${PORT}.pid"

# Cleanup function to ensure removal of temporary files on script exit
CLEANUP() {
    rm -f "$COOKIE_FILE" > /dev/null 2>&1
    rm -f "$PID_FILE" > /dev/null 2>&1
}

# Setup trap to call cleanup function on script exit
trap cleanup EXIT INT TERM ERR

# Kill the last instance of this monitor if it is hung, and log the current PID
if [ -f "$PID_FILE" ]
then
   PID=$(cat "$PID_FILE")
   if kill -0 "$PID" 2>/dev/null; then
       LOG_MESSAGE "EAV exceeded runtime, killing previous instance ${IP}:${PORT}" "err"
       kill "$PID" > /dev/null 2>&1
   fi
fi

# Record the PID ($$) to the PID file
echo "$$" > "$PID_FILE"

# Begin the actual monitor
# Get the initial cookie and ntok
INIT_RESPONSE=$(curl -k -c "$COOKIE_FILE" -s -S "$URL")
NTOK=$(echo "$INIT_RESPONSE" | grep -oP 'name="ntok" id="[^"]*" value="\K[^"]*')

# Check if ntok is valid - 40 hex characters
if ! [[ -n "$NTOK" ]]
then
    LOG_MESSAGE "Couldn't find ntok for $MON_TMPL_NAME Name: $NODE_NAME IP: $IP Port: $PORT" "err"
    exit 1
fi

# Log in with the cookie, ntok, username, and password
HTTP_CODE=$(curl -k -b "$COOKIE_FILE" -w "%{http_code}" -d "target=&ntok=$NTOK&static_u=&no_u=&no_p=&username=$USERNAME&F_password=0&password=$PASSWORD" "$URL" -s -S -o /dev/null)

# Expecting a 302 redirect upon successful login
if [[ $HTTP_CODE -eq 302 ]]
then
    URI="/guest/auth_logout.php"
    URL="${URL_PREFIX}${URI}"
    HTTP_CODE=$(curl -k -b "$COOKIE_FILE" -w "%{http_code}" "$URL" -s -S -o /dev/null)

    # Warn if logout fails, but don't quit
    if ! [[ $HTTP_CODE -eq 302 ]]
    then
        LOG_MESSAGE "$MON_TMPL_NAME - PID: $$ Name: $NODE_NAME IP: $IP Port: $PORT failed to logout." "warn"
    fi

    END_TIME=$(date +%s%N)
    ELAPSED_TIME=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000}")
    LOG_MESSAGE "$MON_TMPL_NAME - PID: $$ Name: $NODE_NAME IP: $IP Port: $PORT Succeeded after $ELAPSED_TIME ms" "info"

    CLEANUP
    
    echo UP
    exit 0
else
    LOG_MESSAGE "$MON_TMPL_NAME - PID: $$ Name: $NODE_NAME IP: $IP Port: $PORT Incorrect username or password" "err"
    exit 1
fi
