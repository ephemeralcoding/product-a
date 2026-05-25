# --- ISO cache --------------------------------------------------------------

ISO_CACHE := iso-cache

ensure-iso: check-env
	@test -n "$(BUILD_ID)" || (echo "ERROR: BUILD_ID required" && exit 1)
	$(eval BASE_OS := $($(BUILD_ID)_BASE_OS))
	@test -n "$(BASE_OS)" || (echo "ERROR: unknown BUILD_ID '$(BUILD_ID)'" && exit 1)
	@mkdir -p $(ISO_CACHE)
	@if [ ! -f $(ISO_CACHE)/$(BASE_OS).iso ]; then \
	  echo ">>> Downloading $(BASE_OS).iso"; \
	  curl -fsS \
	    -H "Authorization: Bearer $$ARTIFACTORY_TOKEN" \
	    -o $(ISO_CACHE)/$(BASE_OS).iso \
	    "$(ARTIFACTORY_URL)$(ISO_PATH)$(BASE_OS).iso"; \
	  curl -fsS \
	    -H "Authorization: Bearer $$ARTIFACTORY_TOKEN" \
	    -o $(ISO_CACHE)/$(BASE_OS).iso.sha256 \
	    "$(ARTIFACTORY_URL)$(ISO_PATH)$(BASE_OS).iso.sha256"; \
	else \
	  echo ">>> ISO cached: $(ISO_CACHE)/$(BASE_OS).iso"; \
	fi

# --- Build ------------------------------------------------------------------

build-one: ensure-iso
	$(eval BASE_OS := $($(BUILD_ID)_BASE_OS))
	$(eval HOST    := $($(BUILD_ID)_HOST))
	@echo ">>> Building $(BUILD_ID)"
	cd packer && $(PACKER) init . && \
	  $(PACKER) build \
	    -var-file=../output/builds/$(BUILD_ID)/$(HOST).pkrvars.hcl \
	    .
	@echo ">>> Done: $(BUILD_ID)"
