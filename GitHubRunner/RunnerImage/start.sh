#!/bin/bash

# Generate a JWT using the GitHub App's private key
generate_jwt() {
  header='{
    "alg": "RS256",
    "typ": "JWT"
  }'

  payload=$(cat <<EOF
{
  "iat": $(date +%s),
  "exp": $(($(date +%s) + 600)),
  "iss": "$GITHUB_APP_ID"
}
EOF
)

  # Generate the JWT
  jwt=$(echo -n "${header}" | base64 | tr -d '\n=')\
.$(echo -n "${payload}" | base64 | tr -d '\n=')\
| openssl dgst -sha256 -sign "$GITHUB_APP_KEY" | base64 | tr -d '\n='

  echo $jwt
}

# Exchange the JWT for an installation token
get_installation_token() {
  jwt=$1

  # Fetch the installation ID for the App (assuming single installation)
  installation_id=$(curl -s -H "Authorization: Bearer $jwt" \
                        -H "Accept: application/vnd.github+json" \
                        https://api.github.com/app/installations | jq -r '.[0].id')

  if [ -z "$installation_id" ] || [ "$installation_id" == "null" ]; then
    echo "Failed to retrieve installation ID"
    exit 1
  fi

  # Use the installation ID to get an access token
  token=$(curl -s -X POST \
                -H "Authorization: Bearer $jwt" \
                -H "Accept: application/vnd.github+json" \
                https://api.github.com/app/installations/$installation_id/access_tokens \
          | jq -r '.token')

  echo $token
}

# Fetch the registration token for the self-hosted runner
get_registration_token() {
  installation_token=$1

  reg_token=$(curl -s -X POST \
                  -H "Authorization: token $installation_token" \
                  -H "Accept: application/vnd.github+json" \
                  https://api.github.com/orgs/"${ORG_NAME}"/actions/runners/registration-token \
            | jq -r '.token')

  echo $reg_token
}

# Main Flow
jwt=$(generate_jwt)
installation_token=$(get_installation_token "$jwt")
REG_TOKEN=$(get_registration_token "$installation_token")

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" == "null" ]; then
  echo "Failed to retrieve the registration token"
  exit 1
fi

# Configure and run the self-hosted runner
./config.sh --url https://github.com/"${ORG_NAME}" --token "${REG_TOKEN}" --unattended --ephemeral && ./run.sh
