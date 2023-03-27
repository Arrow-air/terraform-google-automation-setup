## DO NOT EDIT!
# This file was provisioned by Terraform
# File origin: https://github.com/Arrow-air/tf-github/tree/main/src/templates/tf-all/Makefile

help: .help-base .help-cspell .help-markdown .help-editorconfig .help-tf

include .make/base.mk
include .make/cspell.mk
include .make/markdown.mk
include .make/editorconfig.mk
include .make/terraform.mk

test: cspell-test md-test-links editorconfig-test
