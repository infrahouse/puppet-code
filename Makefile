.DEFAULT_GOAL := help

define BROWSER_PYSCRIPT
import os, webbrowser, sys

from urllib.request import pathname2url

webbrowser.open("docs/_build/html/index.html")
endef
export BROWSER_PYSCRIPT

define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
	match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
	if match:
		target, help = match.groups()
		print("%-20s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT

BROWSER := python -c "$$BROWSER_PYSCRIPT"
OS_VERSION ?= jammy

PWD := $(shell pwd)
INSTALL_DIR = "/opt/puppet-code"

help:
	@python -c "$$PRINT_HELP_PYSCRIPT" < $(MAKEFILE_LIST)

.PHONY: hooks
hooks:  ## Instance git hooks
	test -L .git/hooks/pre-commit || ln -fs ../../hooks/pre-commit .git/hooks/pre-commit

bootstrap:  ## Install dependencies
	apt-get -y install devscripts \
		debhelper

all:
	@echo "Nothing to build"

install: ## Install the code
	mkdir -p "${DESTDIR}${INSTALL_DIR}"
	cp -R environments "${DESTDIR}${INSTALL_DIR}"; find "${DESTDIR}${INSTALL_DIR}/environments/" -type f -exec chmod 644 {} \;
	cp -R modules "${DESTDIR}${INSTALL_DIR}" ; find "${DESTDIR}${INSTALL_DIR}/modules/" -type f -exec chmod 644 {} \;

.PHONY: package
package:  ## Build a deb package
	bash support/package.sh

.PHONY: docker
docker:  ## Run a container
	@docker run -it --rm -v $$PWD:/puppet-code -w /puppet-code ubuntu:jammy bash -l


.PHONY: bumpversion
bumpversion:
	@docker run --rm -v $$PWD:/puppet-code -w /puppet-code ubuntu:jammy bash -c "apt-get update; \
		apt-get -y install devscripts \
		debhelper; \
		DEBEMAIL=packager@infrahouse.com dch --distribution jammy -R 'commit event. see changes history in git log'"

.PHONY: test
test:
	sudo ih-puppet \
     --environment development \
     --environmentpath {root_directory}/environments \
     --root-directory /home/ubuntu/code/puppet-code \
     --hiera-config {root_directory}/environments/{environment}/hiera.yaml \
     --module-path {root_directory}/modules apply
