# --- ISO cache --------------------------------------------------------------

ISO_CACHE := iso-cache

# Download an ISO + its checksum from Artifactory if missing.
# Pattern rule matches any *.iso under iso-cache/.
$(ISO_CACHE)/%.iso:
	@mkdir -p $(ISO_CACHE)
	@echo ">>> Downloading $* from Artifactory"
	@curl -fsS \
	  -H "Authorization: Bearer $$ARTIFACTORY_TOKEN" \
	  -o $@ \
	  "$$ARTIFACTORY_URL/artifactory/iso/$*.iso"
	@curl -fsS \
	  -H "Authorization: Bearer $$ARTIFACTORY_TOKEN" \
	  -o $@.sha256 \
	  "$$ARTIFACTORY_URL/artifactory/iso/$*.iso.sha256"
	@echo ">>> Cached at $@"

# Get the base_os value for a build from its build.mk, then ensure ISO exists.
ensure-iso: check-env
	@test -n "$(BUILD_ID)" || (echo "ERROR: BUILD_ID required" && exit 1)
	@$(eval include generated/builds/$(BUILD_ID)/build.mk)
	@$(MAKE) --no-print-directory $(ISO_CACHE)/$(BASE_OS).iso

# build-one now depends on the ISO being available
build-one: check-env ensure-iso
	... existing logic ...
