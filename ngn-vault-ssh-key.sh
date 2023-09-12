#!/bin/bash
#
# Creates a vault signed SSH key
#
# Required environment variables:
#   VAULT_ADDR The Vault server URL
#   VAULT_TOKEN The Vault auth token
#
# Optional environment variables:
#   VAULT_NAMESPACE The Vault namespace
#

# Set echo ON so we can see each cmd being run
set -x

help() {
    cat <<EOF
usage: $0 [-hf] [-r SSH_ROLE] [-u USERNAME] <KEY_PATH>
    -r The Vault SSH role name, which determines various restrictions on the key
       and defaults to "automation"
    -u The target username, which defaults to "automation"
    -f Force creation of a new key when the target key already exists
EOF
}

# Path to the ssh secret engine
VAULT_SSH_PATH="ngn/shared/shared/ssh"
# Default ssh role name
VAULT_SSH_ROLE="automation"
# Default valid principals value
USERNAME="automation"
# Don't force a new key
FORCE=0
while getopts 'hr:u:f' OPTION; do
    case "$OPTION" in
        h)
            help
            exit 0
            ;;
        r)
            VAULT_SSH_ROLE="$OPTARG"
            ;;
        u)
            USERNAME="$OPTARG"
            ;;
        f)
            FORCE=1
            ;;
        ?)
            help
            exit 1
            ;;
    esac
done
shift "$(($OPTIND -1))"

if [ "$#" -ne 1 ]; then
    help
    exit 1
fi
PRV_KEY_PATH=$1
PUB_KEY_PATH="${PRV_KEY_PATH}.pub"
CERT_PATH="${PRV_KEY_PATH}-cert.pub"

# Check for vault on the path
VAULT=vault
if ! which vault; then
    VAULT=/usr/local/bin/vault
fi

# Delete old key
if [ ${FORCE} -eq 1 ]; then
    rm -f ${PRV_KEY_PATH} ${PUB_KEY_PATH} ${CERT_PATH} || exit 1
fi

# Generate a new key
if [ ! -f ${PRV_KEY_PATH} ]; then
    ssh-keygen -q -t ed25519 -b 256 -f ${PRV_KEY_PATH} -N "" || exit 1
    chmod 0600 ${PRV_KEY_PATH} || exit 1
fi

# Sign key
${VAULT} write \
    -field=signed_key \
    "${VAULT_SSH_PATH}/sign/${VAULT_SSH_ROLE}" \
    "valid_principals=${USERNAME}" \
    "public_key=@${PUB_KEY_PATH}" > ${CERT_PATH} || exit 1

