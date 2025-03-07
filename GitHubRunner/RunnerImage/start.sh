#!/usr/bin/env bash

set -o pipefail

app_id=$GITHUB_APP_ID
printf '%s\n' "App ID: $app_id"
pem=$(echo "$GITHUB_APP_KEY" | sed 's/.\{64\}/&\n/g')
echo "$pem" | head -n 10
env=$ENV

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json="{
    \"iat\":${iat},
    \"exp\":${exp},
    \"iss\":\"${app_id}\"
}"
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT
JWT="${header_payload}"."${signature}"
printf '%s\n' "JWT: $JWT"

# Exchange the JWT for an installation token

# Fetch the installation ID for the App (assuming single installation)
echo "Fetching installation ID..."
installation_id=$(curl -s -H "Authorization: Bearer $JWT" \
                      -H "Accept: application/vnd.github+json" \
                      https://api.github.com/app/installations | jq -r '.[0].id')

echo "Installation ID: $installation_id"

if [ -z "$installation_id" ] || [ "$installation_id" == "null" ]; then
  echo "Failed to retrieve installation ID"
  exit 1
fi

# Use the installation ID to get an access token
echo "Fetching installation token..."
installation_token=$(curl -s -X POST \
                  -H "Authorization: Bearer $JWT" \
                  -H "Accept: application/vnd.github+json" \
                  https://api.github.com/app/installations/$installation_id/access_tokens \
            | jq -r '.token')

if [ -z "$installation_token" ] || [ "$installation_token" == "null" ]; then
  echo "Failed to retrieve installation token"
  exit 1
fi

echo "Installation Token: $installation_token"


# Fetch the registration token for the self-hosted runner
echo "Fetching registration token..."
reg_token=$(curl -s -X POST \
                -H "Authorization: token $installation_token" \
                -H "Accept: application/vnd.github+json" \
                https://api.github.com/orgs/"${ORG_NAME}"/actions/runners/registration-token \
          | jq -r '.token')

echo "Registration Token: $reg_token"

if [ -z "$reg_token" ] || [ "$reg_token" == "null" ]; then
  echo "Failed to retrieve the registration token"
  exit 1
fi

# Configure and run the self-hosted runner
echo "Configuring and starting the runner"
./config.sh --url https://github.com/"${ORG_NAME}" \
            --token "${reg_token}" \
            --unattended \
            --name "Mitchtest-Runner-${INSTANCE}" \
            --labels self-hosted-"${ENV}"

./run.sh