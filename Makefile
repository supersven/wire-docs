SHELL = bash

.DEFAULT_GOAL := docs

MKFILE_DIR = $(abspath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

DOCKER_USER   ?= quay.io/wire
DOCKER_IMAGE  = alpine-sphinx
DOCKER_TAG    ?= latest

# You can set these variables (with a ?=) from the command line, and also
# from the environment.
SPHINXOPTS    ?= -q
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = $(MKFILE_DIR)/src
BUILDDIR      = $(MKFILE_DIR)/build
# note: if you're using direnv/nix, this will be set to USE_POETRY=0 automatically in .envrc
USE_POETRY    ?= 1

ifeq ($(OS), darwin)
OPEN := open
else
OPEN := xdg-open
endif

.PHONY: Makefile

.DEFAULT: docs
.PHONY: docs
docs:
	docker run --rm -v $$(pwd):/mnt $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) make clean html

.PHONY: docs-pdf
docs-pdf:
	docker run --rm -v $$(pwd):/mnt $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) make clean pdf

.PHONY: docs-all
docs-all:
	docker run --rm -v $$(pwd):/mnt $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) make clean html pdf

.PHONY: clean
clean:
	rm -rf "$(BUILDDIR)"

# Only build part of the documentation
# See 'exclude_patterns' in source/conf.py
docs-administrate:
	docker run --rm -e SPHINXOPTS='-t administrate' -v $$(pwd):/mnt $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) make clean html
	cd build && zip -r administration-wire-$$(date +"%Y-%m-%d").zip html

.PHONY: exec
exec:
	docker run -it -v $(MKFILE_DIR):/mnt $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: docker
docker:
	docker build -t $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG) $(MKFILE_DIR)

.PHONY: docker-push
docker-push:
	docker push $(DOCKER_USER)/$(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: push
push:
ifeq ($(USE_POETRY), 1)
	source $$HOME/.poetry/env && \
	poetry run aws s3 sync $(BUILDDIR)/html s3://origin-docs.wire.com/
else
	aws s3 sync $(BUILDDIR)/html s3://origin-docs.wire.com/
endif

.PHONY: dev-run
dev-run: clean
ifeq ($(USE_POETRY), 1)
	source $$HOME/.poetry/env && \
	poetry run sphinx-autobuild \
		--port 3000 \
		--host 127.0.0.1 \
		-b html \
		$(SPHINXOPTS) \
		"$(SOURCEDIR)" "$(BUILDDIR)"
else
	sphinx-autobuild \
		--port 3000 \
		--host 127.0.0.1 \
		-b html \
		$(SPHINXOPTS) \
		"$(SOURCEDIR)" "$(BUILDDIR)"
endif

.PHONY: dev-pdf
dev-pdf: pdf
	$(OPEN) build/pdf/wire_federation.pdf 2>&1 > /dev/null &
	find src/ | entr make pdf

.PHONY: help
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)

# Catch-all target: route all unknown targets to Sphinx. This "converts" unknown targets into sub-commands (or more precicly
# into `buildername`) of the $(SPHINXBUILD) CLI (see https://www.gnu.org/software/make/manual/html_node/Last-Resort.html).
%:
ifeq ($(USE_POETRY), 1)
	source $$HOME/.poetry/env && \
	poetry run $(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)
	$(if $(and $(@),html), poetry run sphinx-multiversion "$(SOURCEDIR)" "$(BUILDDIR)/$(@)" $(SPHINXOPTS))
else
	$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)
	$(if $(and $(@),html), sphinx-multiversion "$(SOURCEDIR)" "$(BUILDDIR)/$(@)" $(SPHINXOPTS))
endif
