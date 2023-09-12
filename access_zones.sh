#!/bin/bash

set -x
D=`dirname $0`

export VAULT_ADDR=https://stg.vault.nvidia.com
export VAULT_NAMESPACE=ngn-platform
vault login -method=oidc role=ngn-admin
bash $D/ngn-vault-ssh-key.sh -r ngnadmin -u ngnadmin ~/.ssh/stg-ssh-key



export VAULT_ADDR=https://prod.vault.nvidia.com
export VAULT_NAMESPACE=ngn-platform
vault login -method=oidc role=ngn-admin
bash $D/ngn-vault-ssh-key.sh -r ngnadmin -u ngnadmin ~/.ssh/prod-ssh-key

