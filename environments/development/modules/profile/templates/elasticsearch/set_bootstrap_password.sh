#!/usr/bin/env bash

set -eu
export PATH="$PATH:/usr/bin:/usr/share/elasticsearch/bin"
BOOTSTRAP_TOUCH_FILE="<%= @bootstrap_touch_file %>"

aws secretsmanager get-secret-value --secret-id "<%= @bootstrap_password %>" | jq .SecretString -r | elasticsearch-keystore add -x bootstrap.password
touch "${BOOTSTRAP_TOUCH_FILE}"
