-include *.mk

SHELL := /bin/bash
.DEFAULT_GOAL := all
.PHONY: all build push shell prune scan demo login check

IMAGE_REPOSITORY ?= xanter/flutter
FLUTTER_CHANNEL ?=
FLUTTER_VERSION ?=
IMAGE_TAG = $(if $(FLUTTER_VERSION),$(FLUTTER_VERSION),$(if $(FLUTTER_CHANNEL),$(FLUTTER_CHANNEL),stable))
export IMAGE_REPOSITORY FLUTTER_CHANNEL FLUTTER_VERSION IMAGE_TAG

all:
	@echo 'make build FLUTTER_VERSION=3.35.7 (or FLUTTER_CHANNEL=stable)'
	@echo 'Targets: build, check, push, shell, demo, login, prune, scan'

build:
	bash tools/image.sh build

push:
	bash tools/image.sh push

check:
	bash tools/verify_images.sh "$$IMAGE_REPOSITORY" "$$IMAGE_TAG"

shell:
	docker run --rm -it -v "$(CURDIR):/workspace" --workdir /workspace \
		"$$IMAGE_REPOSITORY:$$IMAGE_TAG-android-warmed" /bin/bash

demo:
	docker run --rm -v "$(CURDIR)/tools:/tools:ro" \
		"$$IMAGE_REPOSITORY:$$IMAGE_TAG-android-warmed" bash /tools/build_demo_android.sh

login:
	docker login

prune:
	docker image prune -af --filter 'label=family=xanter/flutter'

scan:
	docker scout cves "$$IMAGE_REPOSITORY:$$IMAGE_TAG-android-warmed"
