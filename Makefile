.DEFAULT_GOAL := all

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
hooks:
	test -f .git/hooks/pre-commit || cp hooks/pre-commit .git/hooks/pre-commit

all:
	@echo "Nothing to build"

install:
	mkdir -p "${DESTDIR}${INSTALL_DIR}"
	cp -R environments "${DESTDIR}${INSTALL_DIR}"; find "${DESTDIR}${INSTALL_DIR}/environments/" -type f -exec chmod 644 {} \;
	cp -R modules "${DESTDIR}${INSTALL_DIR}" ; find "${DESTDIR}${INSTALL_DIR}/modules/" -type f -exec chmod 644 {} \;

.PHONY: package
package:
	bash support/package.sh
