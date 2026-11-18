#!/bin/sh

# Extract the value associated with a specified JSON key.
# Supports both quoted string values and unquoted values
# (number, boolean, null) in simple JSON objects.
# Usage: jsonval <key>
jsonval() {
	awk -v target="$1" '
    BEGIN { FS="\"" }   # Split on double quotes to locate JSON keys reliably.

    {
      for (i = 1; i < NF; i++) {
        if ($i != target)
          continue

        # String value:
        #   "key":"value"
        # Fields: key | : | value
        if ($(i + 1) ~ /^[[:space:]]*:[[:space:]]*$/) {
          print $(i + 2)
          exit
        }

        # Unquoted value:
        #   "key":123
        #   "key":true
        #   "key":null
        val = $(i + 1)
        sub(/^[[:space:]]*:[[:space:]]*/, "", val)
        sub(/[[:space:]]*[,}].*$/, "", val)
        print val
        exit
      }
    }
  '
}

get_ip() {
	curl -s -$1 https://www.cloudflare.com/cdn-cgi/trace | awk -F'=' '/^ip=/ {print $2}'
}

need_update() {

	if [ -z "$1" ]; then
		exit 100
	fi

	if [ -z "$2" ] || [ "$1" = "$2" ]; then
		return 1
	else
		return 0
	fi
}

update_record() {

	RECORD_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME&type=$2" \
		-H "Authorization: Bearer $CFTOKEN" \
		-H "Content-Type: application/json")

	CFRECORD_ID=$(echo "$RECORD_RESPONSE" | jsonval id)
	echo $CFRECORD_ID

	if [ -z "$CFRECORD_ID" ]; then
		echo "ERROR: Failed to get Record ID for $2 record"
		exit 4
	fi

	RECORD_ROXIED=$(echo "$RECORD_RESPONSE" | jsonval proxied)
	echo $RECORD_ROXIED
	RECORD_TTL=$(echo "$RECORD_RESPONSE" | jsonval ttl)
	echo $RECORD_TTL
	RECORD_IP=$(echo "$RECORD_RESPONSE" | jsonval content)
	echo $RECORD_IP

	if [ -z "$RECORD_ROXIED" ]; then
		echo "ERROR: Failed to get Record proxied for $2 record"
		exit 4
	fi
	if [ -z "$RECORD_TTL" ]; then
		echo "ERROR: Failed to get Record ttl for $2 record"
		exit 4
	fi
	if [ -z "$RECORD_IP" ]; then
		echo "ERROR: Failed to get Record ip for $2 record"
		exit 4
	fi

	if ! need_update "$RECORD_IP" "$3" && ! need_update "$RECORD_ROXIED" "$CFPROXIED" && ! need_update "$RECORD_TTL" "$CFTTL"; then
		echo "IPv$1 address is up to date ($3) and no settings changed, skipping update."
	else

		if need_update "$RECORD_IP" "$3"; then
			echo "IPv$1 changed from $RECORD_IP to $3, updating..."
		else
			echo "IPv$1 is $3, ttl from $RECORD_TTL to ${CFTTL:-$RECORD_TTL}, proxied from  $RECORD_ROXIED to ${CFPROXIED:-$RECORD_ROXIED}, updating..."
		fi

		RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
			-H "Authorization: Bearer $CFTOKEN" \
			-H "Content-Type: application/json" \
			--data "{\"type\":\"$2\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$3\", \"ttl\":${CFTTL:-$RECORD_TTL},\"proxied\":${CFPROXIED:-$RECORD_ROXIED}}")

		if echo "$RESPONSE" | grep -q '"success":true'; then
			echo "Updated succesfuly!"
		else
			echo 'Something went wrong :('
			echo "Response: $RESPONSE"
			RETVAL=1
		fi

	fi

}

get_and_update() {
	# Get current and old WAN ip
	WAN_IP=$(get_ip $1 || echo "")

	if [ -z "$WAN_IP" ]; then
		echo "Warning: Failed to get IPv$1 address."
	else

		update_record $1 $2 $WAN_IP

	fi

}

set -o errexit
set -o nounset
#only works in bash so I removed it
#set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Can retrieve cloudflare Domain id and list zone's, because, lazy

# Place at:
# curl https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1

# Usage:
# cf-ddns.sh -k cloudflare-api-token \
#            -h host.example.com \     # fqdn of the record you want to update
#            -z example.com \          # will show you all zones if forgot, but you need this
#            -t 4|6|all                # specify ipv4/ipv6, default: all

# default config

# API key, see https://www.cloudflare.com/a/account/my-account,
# incorrect api-key results in E_UNAUTH error
: ${CFTOKEN:=}

# Zone name, eg: example.com
: ${CFZONE_NAME:=}

# Hostname to update, eg: homeserver.example.com
: ${CFRECORD_NAME:=}

# Record type, 4|6|all, default all
: ${CFRECORD_TYPE:=all}

# Cloudflare TTL for record, between 120 and 86400 seconds
: ${CFTTL:=}

# Cloudflare proxied for record, true or false
: ${CFPROXIED:=}

# Return Value, 1 if at least one update didn't receive a RESPONSE with success
RETVAL=0

# get parameter
while getopts k:h:z:t:l:p: opts; do
	case ${opts} in
	k) CFTOKEN=${OPTARG} ;;
	h) CFRECORD_NAME=${OPTARG} ;;
	z) CFZONE_NAME=${OPTARG} ;;
	t) CFRECORD_TYPE=${OPTARG} ;;
	l) CFTTL=${OPTARG} ;;
	p) CFPROXIED=${OPTARG} ;;
	esac
done

# If required settings are missing just exit
if [ "$CFTOKEN" = "" ]; then
	echo "Missing api-key, get at: https://www.cloudflare.com/a/account/my-account"
	echo "and set env CFTOKEN=value or using the -k flag"
	exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then
	echo "Missing hostname, what host do you want to update?"
	echo "set env CFRECORD_NAME=value or using the -h flag"
	exit 2
fi

# If the hostname is not a FQDN
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
	CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
	echo " => Hostname is not a FQDN, assuming $CFRECORD_NAME"
fi

echo "Updating zone_identifier & record_identifier"
CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
	-H "Authorization: Bearer $CFTOKEN" \
	-H "Content-Type: application/json" |
	jsonval id)
echo $CFZONE_ID
if [ -z "$CFZONE_ID" ]; then
	echo "ERROR: Failed to get CF ZONE ID based on Token and Zone Name"
	exit 5
fi

if [ "$CFRECORD_TYPE" != "6" ]; then

	get_and_update 4 A

fi

if [ "$CFRECORD_TYPE" != "4" ]; then

	get_and_update 6 AAAA

fi

exit $RETVAL
