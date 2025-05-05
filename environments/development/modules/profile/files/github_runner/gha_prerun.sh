#!/usr/bin/env bash

set -eu

sudo chown -R "$USER" "$GITHUB_WORKSPACE"
ih-aws autoscaling scale-in enable-protection
