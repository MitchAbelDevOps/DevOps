#!/usr/bin/env bash

set -o pipefail

NUM_RUNNERS=2  # Number of runners to register
app_id=$GITHUB_APP_ID
printf '%s\n' "App ID: $app_id"

# Decode the private key from Base64
pem=$(echo "$GITHUB_APP_KEY" | base64 -d)
env=$ENV

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
header=$( echo -n "${header_json}" | b64enc )

payload_json="{
    \"iat\":${iat},
    \"exp\":${exp},
    \"iss\":\"${app_id}\"    
}"
payload=$( echo -n "${payload_json}" | b64enc )

header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

JWT="${header_payload}"."${signature}"
printf '%s\n' "JWT: $JWT"

# Fetch the installation ID
echo "Fetching installation ID..."
installation_id=$(curl -s -H "Authorization: Bearer $JWT" \
                      -H "Accept: application/vnd.github+json" \
                      https://api.github.com/app/installations | jq -r '.[0].id')

echo "Installation ID: $installation_id"

if [ -z "$installation_id" ] || [ "$installation_id" == "null" ]; then
  echo "Failed to retrieve installation ID"
  exit 1
fi

# Get the installation token
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

# Fetch the registration token
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

# Start multiple runners
for i in $(seq 1 $NUM_RUNNERS); do
    echo "Configuring runner #$i"
    RUNNER_DIR="runner_$i"
    mkdir -p $RUNNER_DIR
    cp -r * $RUNNER_DIR
    cd $RUNNER_DIR
    
    ./config.sh --url https://github.com/"${ORG_NAME}" \
                --token "${reg_token}" \
                --unattended \
                --name "Runner-${INSTANCE}-$i" \
                --labels self-hosted-"${ENV}"

    echo "Starting runner #$i"
    ./run.sh &  # Start the runner in the background

    cd ..
done

# Keep the container running
wait
