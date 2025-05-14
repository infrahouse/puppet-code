#!/usr/bin/env bash

set -eu

sudo chown -R "$USER" "$GITHUB_WORKSPACE"
/usr/local/bin/ih-aws autoscaling scale-in enable-protection
