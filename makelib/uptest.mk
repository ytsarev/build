# ====================================================================================
# End to End Testing

ifndef UPTEST_LOCAL_DEPLOY_TARGET
  $(error UPTEST_LOCAL_DEPLOY_TARGET is not set. It is required for the provider or configuration \
		to be deployed before running the tests. \
		Example `local.xpkg.deploy.configuration.$(PROJECT_NAME)` for configurations or \
		`local.xpkg.deploy.provider.$(PROJECT_NAME)` for providers)
endif

UPTEST_ARGS ?=

UPTEST_SKIP_UPDATE ?= false
ifeq ($(UPTEST_SKIP_UPDATE),true)
    UPTEST_ARGS += --skip-update
endif

UPTEST_SKIP_IMPORT ?= false
ifeq ($(UPTEST_SKIP_IMPORT),true)
    UPTEST_ARGS += --skip-import
endif

UPTEST_SKIP_DELETE ?= false
ifeq ($(UPTEST_SKIP_DELETE),true)
    UPTEST_ARGS += --skip-delete
endif

UPTEST_DEFAULT_TIMEOUT ?=
ifdef UPTEST_DEFAULT_TIMEOUT
	UPTEST_ARGS += --default-timeout=$(UPTEST_DEFAULT_TIMEOUT)
endif

UPTEST_RENDER_ONLY ?= false
ifeq ($(UPTEST_RENDER_ONLY),true)
    UPTEST_ARGS += --render-only
endif

UPTEST_COMMAND = SKIP_DEPLOY_ARGO=$(SKIP_DEPLOY_ARGO) \
	KUBECTL=$(KUBECTL) \
	CHAINSAW=$(CHAINSAW) \
	CROSSPLANE_CLI=$(CROSSPLANE_CLI) \
	CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) \
	YQ=$(YQ) \
	$(UPTEST) e2e $(UPTEST_INPUT_MANIFESTS) \
	--data-source="${UPTEST_DATASOURCE_PATH}" \
	--setup-script=$(UPTEST_SETUP_SCRIPT) \
	$(UPTEST_ARGS)

# This target requires the following environment variables to be set:
# - To ensure the proper functioning of the end-to-end test resource pre-deletion hook, it is crucial to arrange your resources appropriately.
#   You can check the basic implementation here: https://github.com/crossplane/uptest/blob/main/internal/templates/03-delete.yaml.tmpl
# - UPTEST_DATASOURCE_PATH (optional), see https://github.com/crossplane/uptest?tab=readme-ov-file#injecting-dynamic-values-and-datasource
UPTEST_SETUP_SCRIPT ?= test/setup.sh
uptest: $(UPTEST) $(KUBECTL) $(CHAINSAW) $(CROSSPLANE_CLI) $(YQ)
	@$(INFO) running automated tests
	$(UPTEST_COMMAND) || $(FAIL)
	@$(OK) running automated tests

# Run uptest together with all dependencies. Use `make e2e UPTEST_SKIP_DELET=true` to skip deletion of resources.
e2e: build controlplane.down controlplane.up $(UPTEST_LOCAL_DEPLOY_TARGET) uptest #

# Renders crossplane compositions in the current project
#
# Composition and Function must be defined, Environment and Observeed Resources are optionally available.
# The command discovers sees by parsing the `render.crossplane.io/*`-annotations of file found in the
# examples-directorry, usually: `/examples`
#
# Possible values are:
#  - composition-path (Composition)
#  - function-path (Function)
#  - environment-path (Environment Configs)
#  - observe-path (Observed Resources)
#
#  Example: `render.crossplane.io/composition-path: "apis/kcl/composition.yaml"`
#
render: $(CROSSPLANE_CLI) ${YQ}
	@indir="./examples"; \
	rm -rf "$(CACHE_DIR)/render"; \
	mkdir -p "$(CACHE_DIR)/render" || true; \
	for file in $$(find $$indir -type f -name '*.yaml' ); do \
		doc_count=$$(${YQ} eval 'documentIndex' $$file | wc -l); \
		for i in $$(seq 0 $$(($$doc_count - 1))); do \
			COMPOSITION=$$(${YQ} eval "select(documentIndex == $$i) | .metadata.annotations.\"render.crossplane.io/composition-path\"" $$file); \
			FUNCTION=$$(${YQ} eval "select(documentIndex == $$i) | .metadata.annotations.\"render.crossplane.io/function-path\"" $$file); \
			ENVIRONMENT=$$(${YQ} eval "select(documentIndex == $$i) | .metadata.annotations.\"render.crossplane.io/environment-path\"" $$file); \
			OBSERVE=$$(${YQ} eval "select(documentIndex == $$i) | .metadata.annotations.\"render.crossplane.io/observe-path\"" $$file); \
			if [[ "$$ENVIRONMENT" == "null" ]]; then \
				ENVIRONMENT=""; \
			fi; \
			if [[ "$$OBSERVE" == "null" ]]; then \
				OBSERVE=""; \
			fi; \
			if [[ "$$COMPOSITION" == "null" || "$$FUNCTION" == "null" ]]; then \
				continue; \
			fi; \
			OUT_FILE=$$(echo $$file | md5sum | head -c5); \
			ENVIRONMENT=$${ENVIRONMENT=="null" ? "" : $$ENVIRONMENT}; \
			OBSERVE=$${OBSERVE=="null" ? "" : $$OBSERVE}; \
			$(CROSSPLANE_CLI) render $$file $$COMPOSITION $$FUNCTION $${ENVIRONMENT:+-e $$ENVIRONMENT} $${OBSERVE:+-o $$OBSERVE} -x >> "$(CACHE_DIR)/render/$${OUT_FILE}.yaml"; \
		done; \
	done

# Prints the raw rendered yaml to stdout
render.show:
	@$(MAKE) render > /dev/null
	@find "$(CACHE_DIR)/render" -type f -name "*.yaml" -exec cat {} \;

YAMLLINT_FOLDER ?= ./apis
yamllint: ## Static yamllint check
	@$(INFO) running yamllint
	@yamllint $(YAMLLINT_FOLDER) || $(FAIL)
	@$(OK) running yamllint

.PHONY: uptest e2e render yamllint


