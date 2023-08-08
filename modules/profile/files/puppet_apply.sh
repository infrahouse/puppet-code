#!/usr/bin/env bash

set -eux
source /etc/profile.d/puppet-agent.sh

environment=$(facter -p puppet_environment)
root_dir="/opt/puppet-code"

puppet apply -d --environment "${environment}" \
  --hiera_config "${root_dir}/environments/${environment}/hiera.yaml" \
  --modulepath="${root_dir}/modules" \
  "/opt/puppet-code/environments/${environment}/manifests/site.pp" \
  --write-catalog-summary \
  --detailed-exitcodes
