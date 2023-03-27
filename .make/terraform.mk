## DO NOT EDIT!
# This file was provisioned by Terraform
# File origin: https://github.com/Arrow-air/tf-github/tree/main/src/templates/all/.make/terraform.mk

# GCP required vars
GOOGLE_IMPERSONATE_SERVICE_ACCOUNT ?= tf-ro-${TF_WORKSPACE}-${TF_PROJECT}@${TF_PREFIX}-${TF_WORKSPACE}-${TF_PROJECT}.iam.gserviceaccount.com
GOOGLE_APPLICATION_CREDENTIALS     ?= $(HOME)/.config/gcloud/application_default_credentials.json

# Terraform required vars
TF_STATE_BUCKET ?= ${TF_PREFIX}-${TF_WORKSPACE}-${TF_PROJECT}-tfstate
TF_IMAGE_NAME   ?= ghcr.io/arrow-air/tools/arrow-tfenv
TF_IMAGE_TAG    ?= 3.0.0-v1.4.2-1
TF_WORKSPACE    ?= default
TF_FLAGS        ?=
TF_STDOUT       ?= &1

TF_STATE_FILE := $(SOURCE_PATH)/src/.terraform/terraform.tfstate
JQ            := $(shell command -v jq 2> /dev/null)
ifneq ("$(wildcard $(TF_STATE_FILE))","")
	ifdef JQ
		CONFIGURED_STATE_BUCKET := $(shell jq -r '.backend.config.bucket' < ${TF_STATE_FILE})
		CONFIGURED_BACKEND_TYPE := $(shell jq -r '.backend.type' < ${TF_STATE_FILE})
	endif
endif

TF_STATE_BUCKET = $(TF_PREFIX)-$(*)-$(TF_PROJECT)-tfstate

# function with a generic template to run docker with the required values
# Accepts $1 = command to run, $2 = additional command flags (optional)
tf_run = docker run \
	--name=${DOCKER_NAME}-$@ \
	--workdir=/opt/ \
	--rm \
	--user `id -u`:`id -g` \
	-v "${SOURCE_PATH}/src/:/opt/" \
	-v "${GOOGLE_APPLICATION_CREDENTIALS}:/tmp/credentials.json" \
	-e "GOOGLE_APPLICATION_CREDENTIALS=/tmp/credentials.json" \
	-e "GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=${GOOGLE_IMPERSONATE_SERVICE_ACCOUNT}" \
	-e "PLAN_FILE=plan-${TF_WORKSPACE}.tfplan" \
	-e "TF_IN_AUTOMATION=true" \
	-e "TF_WORKSPACE=${TF_WORKSPACE}" \
	-e "TF_STATE_BUCKET=${TF_STATE_BUCKET}" \
	-e "TF_VAR_tf_project=${TF_PROJECT}" \
	-t ${TF_IMAGE_NAME}:${TF_IMAGE_TAG} \
	$(1) $(2) 1>$(TF_STDOUT)

# function to call init and providing a reason why init is needed
define run_init
	echo "$(YELLOW)$(1)$(SGR0)" && $(call tf_run,init,-backend-config="bucket=$(TF_STATE_BUCKET)" -upgrade)
endef

# Check if we need to run init, call_init when needed
ifeq ("$(wildcard $(TF_STATE_FILE))", "")
define check_init
	$(call run_init,(No state file found, need init))
endef
else
	ifdef JQ
define check_init
	$(if $(filter "$(CONFIGURED_BACKEND_TYPE)","local"),$(call run_init,(State file $(CONFIGURED_BACKEND_TYPE), always run init)),$(if $(filter "$(CONFIGURED_STATE_BUCKET)","$(TF_STATE_BUCKET)"),(echo "$(GREEN)Init already done, no need to run init again$(SGR0)"), $(call run_init,(Backend bucket mismatch in jq test (\"${CONFIGURED_STATE_BUCKET}\" != \"${TF_STATE_BUCKET}\"), need to run init))))
endef
	else
define check_init
	$(if $(shell grep bucket "${TF_STATE_FILE}" | grep -q -- ${TF_STATE_BUCKET} && echo $?) != 0,$(call run_init,(Backend bucket mismatch in grep test)))
endef
	endif
endif

tf-docker-pull:
	@echo docker pull -q $(TF_IMAGE_NAME):$(TF_IMAGE_TAG)

.help-tf:
	@echo ""
	@echo "$(SMUL)$(BOLD)$(GREEN)Terraform$(SGR0)"
	@echo "  $(BOLD)tf-clean$(SGR0)       -- Run 'rm -rf src/.terraform'"
	@echo "  $(BOLD)tf-init-ARG$(SGR0)    -- Run 'TF_WORKSPACE=ARG terraform init'"
	@echo "  $(BOLD)tf-validate-ARG$(SGR0)-- Run 'TF_WORKSPACE=ARG terraform validate ${TF_FLAGS}'"
	@echo "  $(BOLD)tf-plan-ARG$(SGR0)    -- Run 'TF_WORKSPACE=ARG terraform plan ${TF_FLAGS}'"
	@echo "  $(BOLD)tf-show-ARG$(SGR0)    -- Run 'TF_WORKSPACE=ARG terraform show ${TF_FLAGS}' to show the plan output."
	@echo "  $(BOLD)tf-workspaces$(SGR0)  -- Run 'terraform workspace list' to list the available workspaces."
	@echo "  $(BOLD)tf-fmt$(SGR0)         -- Run 'terraform fmt -check -recursive' to check terraform file formats."
	@echo "  $(BOLD)tf-tidy$(SGR0)        -- Run 'terraform fmt -recursive' to fix terraform file formats if needed."
	@echo "  $(CYAN)Combined targets$(SGR0)"
	@echo "  $(BOLD)tf-all$(SGR0)         -- Run targets; tf-clean tf-fmt"

.SILENT: tf-docker-pull

tf-clean: tf-docker-pull
	@echo "$(CYAN)Removing .terraform directory...$(SGR0)"
	@rm -rf ./src/.terraform

tf-init-%: TF_WORKSPACE=$*
tf-init-%: tf-docker-pull
	@echo "$(CYAN)Running terraform init...$(SGR0)"
	@$(call tf_run,init,-backend-config="bucket=$(TF_STATE_BUCKET)" -upgrade)

tf-validate-%: TF_WORKSPACE=$*
tf-validate-%: tf-docker-pull
	@$(call check_init)
	@echo "$(CYAN)Running terraform validate...$(SGR0)"
	@$(call tf_run,validate,$(TF_FLAGS))

tf-plan-%: TF_FLAGS=-lock=false -out $(TF_WORKSPACE).plan
tf-plan-%: TF_WORKSPACE=$*
tf-plan-%: tf-docker-pull
	@$(call check_init)
	@echo "$(CYAN)Running terraform plan...$(SGR0)"
	@$(call tf_run,plan,$(TF_FLAGS))

tf-show-%: TF_WORKSPACE=$*
tf-show-%: tf-docker-pull
	@echo "$(CYAN)Running terraform show...$(SGR0)"
	@$(call tf_run,show,$(TF_FLAGS) $(TF_WORKSPACE).plan)

tf-apply-%: TF_WORKSPACE=$*
tf-apply-%: GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=tf-${TF_WORKSPACE}-${TF_PROJECT}@${TF_PREFIX}-${TF_WORKSPACE}-${TF_PROJECT}.iam.gserviceaccount.com
tf-apply-%: tf-docker-pull
	@echo "$(CYAN)Running terraform apply...$(SGR0)"
	@$(call tf_run,apply,$(TF_FLAGS) $(TF_WORKSPACE).plan)

tf-workspaces: tf-docker-pull
	@echo "$(CYAN)Running terraform workspace list...$(SGR0)"
	@$(call tf_run,workspace,list)

tf-fmt: tf-docker-pull
	@echo "$(CYAN)Running and checking terraform file formats...$(SGR0)"
	@$(call tf_run,fmt,-check -recursive)

tf-tidy: tf-docker-pull
	@echo "$(CYAN)Running terraform file formatting fixes...$(SGR0)"
	@$(call tf_run,fmt,-recursive)

tf-all: tf-clean tf-fmt
