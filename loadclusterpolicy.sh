#!/usr/bin/env bash

. config.sh

CUSER=admin
CPASS="$ADMIN_PASS"
URL="$MASTER1_INT"
ACCT="$ORG_NAME"

POLICYBRANCH="root"
POLICY_FILE="cluster.yaml"

# Login
api_key=$(curl -sk --user $CUSER:$CPASS https://$URL/authn/$ACCT/login)
if [ "$api_key" = "" ];then
   echo "Failure: Username/Password Incorrect"
   exit 1
fi

# Get Authentication Result
auth_result=$(curl -sk https://$URL/authn/$ACCT/$CUSER/authenticate -d "$api_key")
if [ "$auth_result" = "" ];then
  echo "Failure: Could not retrieve Auth Token with API Key"
  exit 1
fi

token=$(echo -n $auth_result | base64 | tr -d '\r\n')

AUTH_TOKEN="Authorization: Token token=\"$token\""

url="https://$URL/policies/$ACCT/policy/$POLICYBRANCH"
curl -s -k -H "$AUTH_TOKEN" \
  -X PUT \
  -d "$(< $POLICY_FILE )" \
  $url > policy-load.out

cat policy-load.out
