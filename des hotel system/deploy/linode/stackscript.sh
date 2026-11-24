#!/bin/bash
# Linode / Akamai Marketplace One-Click — DezPMS StackScript stub.
#
# Submit via https://www.linode.com/marketplace/app-partners/ with Ansible
# playbooks per https://github.com/linode-solutions/marketplace-apps
#
# UDF fields (Linode Marketplace convention):
# <UDF name="site_name" label="Site domain" example="pms.yourhotel.com" />
# <UDF name="admin_email" label="Admin email" example="you@yourhotel.com" />
# <UDF name="admin_password" label="Admin password" />
# <UDF name="soa_email_address" label="Let's Encrypt email" default="" />

set -euo pipefail
exec > >(tee -a /var/log/DezPMS-stackscript.log) 2>&1

export SITE_NAME="${SITE_NAME:-}"
export ADMIN_EMAIL="${ADMIN_EMAIL:-}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
export LETSENCRYPT_EMAIL="${soa_email_address:-$ADMIN_EMAIL}"

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl git ca-certificates
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# Builds the image on first boot (20–45 min); adds swap on 4 GB plans.
# Once ghcr.io/DezPMS-pms/DezPMS is public: export DezPMS_PULL=1 here to pull
# the prebuilt image instead (a few minutes).
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh \
  -o /tmp/DezPMS-install.sh
chmod +x /tmp/DezPMS-install.sh
bash /tmp/DezPMS-install.sh

unset ADMIN_PASSWORD
echo "DezPMS Linode One-Click finished. Open http://$(hostname -I | awk '{print $1}'):8080/DezPMS"
