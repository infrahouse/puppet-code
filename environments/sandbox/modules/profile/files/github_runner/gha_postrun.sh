#!/usr/bin/env bash

set -eu

/usr/local/bin/ih-aws autoscaling scale-in disable-protection
