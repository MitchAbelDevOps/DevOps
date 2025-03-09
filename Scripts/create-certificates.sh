#!/bin/bash

# This script can be used to generate the necessary self-signed certificate chain and fake root CA that can then be used for the following:
# PFX that can be attached to APIM custom domains
# RootCA.cer that can be upload to APIM CA store
# PFX that can be attached to App Gateway listeners
# RootCA.cer that can be attached to App Gateway backend settings trusted roots 

CUSTOM_DOMAINS=$@

if [[ -z $CUSTOM_DOMAINS ]]; then
    echo "Parameters missing."
    echo "Usage: create-certificates.sh domain1 domain2 ..."
    echo "Example: create-certificates.sh api.justice.govt.nz portal.api.justice.govt.nz"
    exit 1
fi

create_san_list() {
    local counter=0
    SAN_LIST=""
    for DOMAIN in $CUSTOM_DOMAINS; do
        counter=$((counter + 1))
        SAN_LIST+="DNS:$DOMAIN"
        if [[ $counter -lt $# ]]; then
            SAN_LIST+=", "
        fi
    done
    echo $SAN_LIST
}

create_root_CA_cert() {
    echo "Creating root CA certificate."

    # Create the root key
    openssl ecparam -out rootCA.key -name prime256v1 -genkey

    # Create a Root Certificate and self-sign it
    openssl req -new -sha256 -key rootCA.key -out rootCA.csr \
        -subj "//CN=Sample Root CA"

    cat > rootCA.ext <<-EOF
    authorityKeyIdentifier = keyid:always
    basicConstraints = critical,CA:TRUE,pathlen:2
    keyUsage = critical, keyCertSign, cRLSign
EOF

    openssl x509 -req -sha256 -days 365 -in rootCA.csr -signkey rootCA.key -out rootCA.crt -extfile rootCA.ext

    # Base64 encode CRT
    base64 rootCA.crt > rootCA.crt.txt
}

create_intermediate_CA_cert() {
    echo "Creating intermediate CA certificate."

    # Create the intermediate key
    openssl ecparam -out intermediateCA.key -name prime256v1 -genkey

    # Create the CSR for the intermediate certificate
    openssl req -new -sha256 -key intermediateCA.key -out intermediateCA.csr \
        -subj "//CN=Sample Intermediate CA"

    cat > intermediateCA.ext <<-EOF
    authorityKeyIdentifier = keyid,issuer
    basicConstraints = critical,CA:TRUE,pathlen:1
    keyUsage = critical, keyCertSign, cRLSign
EOF

    openssl x509 -req -sha256 -days 365 -in intermediateCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
        -out intermediateCA.crt -extfile intermediateCA.ext

    # Base64 encode the intermediate certificate
    base64 intermediateCA.crt > intermediateCA.crt.txt
}

create_server_cert() {
    echo "Creating server certificate for $CUSTOM_DOMAINS."

    SAN_LIST=$(echo "$CUSTOM_DOMAINS" | sed -e 's/ /,DNS:/g' -e 's/^/DNS:/')
    EXTENSION_CONFIGURATION="subjectAltName=$SAN_LIST"

    # Create the certificate's key
    openssl ecparam -out domain.key -name prime256v1 -genkey

    # Create the CSR (Certificate Signing Request)
    openssl req -new -sha256 -key domain.key -out domain.csr \
        -subj "/CN=${CUSTOM_DOMAINS%% *}" \
        -addext "$EXTENSION_CONFIGURATION"

    # Write the SAN configuration to the ext file
    echo "$EXTENSION_CONFIGURATION" > domain.ext

    # Generate the certificate
    openssl x509 -req -days 365 -sha256 -in domain.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
        -out domain.crt -extfile domain.ext

    # Export PFX file
    openssl pkcs12 -export -out domain.pfx -inkey domain.key -in domain.crt -passout pass:

    # Base64 encode PFX
    base64 domain.pfx > domain.pfx.txt
}


# Create a new directory for the certificates
mkdir -p .certs
cd .certs || exit

# Create root CA certificate
create_root_CA_cert

# Create intermediate CA certificate
create_intermediate_CA_cert

# Create server certificates
create_server_cert