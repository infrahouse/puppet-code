#!/usr/bin/env bash

set -eux

environment=$(facter -p puppet_environment)
puppet apply --environment "${environment}" \
  "/etc/puppetlabs/code/environments/${environment}/manifests/site.pp" \
  --write-catalog-summary \
  --detailed-exitcodes
