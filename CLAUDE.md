# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Puppet code for managing infrastructure at InfraHouse. 
It follows a role-profile pattern with support for multiple environments (production, development, sandbox) 
and is packaged as Debian packages for deployment.

## Architecture

### Role-Profile Pattern

The codebase uses the standard Puppet role-profile pattern:

- **Roles** (`modules/role/manifests/*.pp`): Business logic layer that defines what a server
  does (e.g., webserver, jumphost, github_runner). Each role includes one or more profiles.
- **Profiles** (`modules/profile/manifests/*.pp`): Technical implementation layer that
  configures specific technologies (e.g., docker, ntp, postfix, elastic). Profiles can
  include other profiles.
- **Base Profile** (`modules/profile/manifests/base.pp`): Included by all roles, sets up
  fundamental system configuration including NTP, repos, packages, InfraHouse toolkit,
  Puppet apply, swap, accounts, and sudo.

### Environment Structure

Three environments with identical structure:
- `environments/production/`
- `environments/development/`
- `environments/sandbox/`

Each environment contains:
- `manifests/site.pp`: Entry point that uses `lookup('classes', {merge => unique}).include`
  to load classes from Hiera
- `hiera.yaml`: Hierarchical data lookup configuration
- `data/`: Hiera data files organized by role name and node certname

### Hiera Hierarchy

Data is looked up in this order:
1. Per-role data: `%{::puppet_role}.yaml`
2. Per-node data: `nodes/%{::trusted.certname}.yaml`
3. Common data: `common.yaml`

## Development Workflow

### Testing and Linting

Run Puppet lint before committing:
```bash
puppet-lint --fail-on-warnings modules/profile
puppet-lint --fail-on-warnings modules/role
puppet-lint --fail-on-warnings environments/development/modules/profile
puppet-lint --fail-on-warnings environments/sandbox/modules/profile
```

The pre-commit hook (`hooks/pre-commit`) automatically:
- Runs puppet-lint on all modules with `--fail-on-warnings`
- Bumps the package version in `debian/changelog`
- Stages the changelog for commit

### Git Hooks

Install git hooks:
```bash
make hooks
```

This creates a symlink from `.git/hooks/pre-commit` to `hooks/pre-commit`.

### Testing Puppet Code Locally

Apply Puppet code locally (requires `ih-puppet` installed):
```bash
make test-puppet
```

This runs:
```bash
sudo ih-puppet \
    --root-directory /home/$(USER)/code/puppet-code \
    --environment $(PUPPET_ENV) \
    --environmentpath {root_directory}/environments \
    --hiera-config {root_directory}/environments/{environment}/hiera.yaml \
    --module-path {root_directory}/environments/{environment}/modules:{root_directory}/modules apply
```

### Building Packages

Build a Debian package:
```bash
make package
# or for specific OS version:
OS_VERSION=noble make package
```

The package script (`support/package.sh`) creates an upstream tarball and builds the .deb
package using `debuild`.

### Running in Docker

Start a container for testing:
```bash
make docker
```

### Version Management

Bump version in changelog:
```bash
make bumpversion
```

This uses a Docker container to run `dch` (Debian changelog tool).

## CI/CD

### Continuous Integration (CI.yml)

Triggered on pull requests to `main`:
- Runs on Ubuntu 24.04
- Tests against multiple Ubuntu codenames (noble, oracular)
- Installs InfraHouse APT repository
- Builds the package

### Continuous Deployment (CD.yml)

Triggered on push to `main` or manual workflow dispatch:
- Builds packages for multiple Ubuntu codenames
- Publishes Debian packages to S3-backed APT repository using `ih-s3-reprepro`
- Supports debug mode with tmate SSH access

## Installation

### Installing InfraHouse Repository

```bash
make install-infrahouse-repo
```

This adds the InfraHouse GPG key and APT repository source.

### Installing the Package

The package installs to `/opt/puppet-code/` with:
- `environments/`: All environment directories
- `modules/`: Shared modules (role and profile)

## Key Files and Patterns

- `environments/*/manifests/site.pp`: Always uses `lookup('classes', {merge => unique}).include`
  to dynamically load classes from Hiera
- `environments/*/data/*.yaml`: Role-specific Hiera data that defines which classes to include
- `modules/profile/manifests/base.pp`: Core profile included by all roles, installs Ruby gems
  (json, aws-sdk-core, aws-sdk-secretsmanager) for Puppet
- Pre-commit hook always bumps version, so commits to main automatically increment the package
  version

## Available Roles

Roles define server types:
- `base`: Base configuration only
- `webserver`: Web server
- `jumphost`: SSH bastion host
- `github_runner`: GitHub Actions runner
- `ecsnode`: AWS ECS container host
- `mta`: Mail transfer agent
- `terraformer`: Terraform runner
- `openvpn_server`: OpenVPN server
- `elastic_master`: Elasticsearch master node
- `elastic_data`: Elasticsearch data node
- `bookstack`: BookStack wiki
- `infrahouse_github_backup`: GitHub backup service
- `teleport`: Teleport access proxy

## Common Profiles

Key technical profiles:
- `base`: Fundamental system setup (NTP, repos, packages, swap, accounts, sudo)
- `docker`: Docker installation and configuration
- `ntp`: Network time configuration
- `repos`: APT repository configuration
- `packages`: Standard package installation
- `infrahouse_toolkit`: InfraHouse utilities
- `puppet_apply`: Puppet apply wrapper scripts
- `swap`: Swap file configuration
- `letsencrypt`: Let's Encrypt SSL certificates
- `postfix`: Mail server configuration
- `elastic/*`: Elasticsearch components (config, service, TLS, backups, etc.)
- `github_runner/*`: GitHub Actions runner components (user, registration, service)
