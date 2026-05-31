.PHONY: test
test:
	bash test/run-all.sh

.PHONY: check-safety
check-safety:
	@SETTINGS_TMP=$$(mktemp) && GUARD_TMP=$$(mktemp) && \
	cp shared/agent-settings.json $$SETTINGS_TMP && \
	cp shared/pre-bash-guard.sh $$GUARD_TMP && \
	bash shared/generate-safety-rules.sh && \
	if ! diff -q shared/agent-settings.json $$SETTINGS_TMP > /dev/null || \
	   ! diff -q shared/pre-bash-guard.sh $$GUARD_TMP > /dev/null; then \
	    echo "ERROR: Safety rules out of sync. Run shared/generate-safety-rules.sh and commit the output."; \
	    cp $$SETTINGS_TMP shared/agent-settings.json; \
	    cp $$GUARD_TMP shared/pre-bash-guard.sh; \
	    rm -f $$SETTINGS_TMP $$GUARD_TMP; \
	    exit 1; \
	fi; \
	rm -f $$SETTINGS_TMP $$GUARD_TMP

.env:
	cp .env.example .env
	@ROOT_PASS=$$(openssl rand -hex 24); \
	sed -i.bak "s/^DOLT_ROOT_PASSWORD=$$/DOLT_ROOT_PASSWORD=$$ROOT_PASS/" .env && rm -f .env.bak
	@MINORDOMO_PASS=$$(openssl rand -hex 24); \
	sed -i.bak "s/^DOLT_MINORDOMO_PASSWORD=$$/DOLT_MINORDOMO_PASSWORD=$$MINORDOMO_PASS/" .env && rm -f .env.bak
	@echo "Generated .env with random DOLT_ROOT_PASSWORD and DOLT_MINORDOMO_PASSWORD"

.PHONY: setup-cd
setup-cd: .env
	@set -a && . ./.env && set +a && \
	helm upgrade --install \
		--namespace minordomo \
		--create-namespace \
		minordomo-cd-setup helm/minordomo-cd-setup/ \
		--set doltRootPassword=$$DOLT_ROOT_PASSWORD \
		--set doltMinordomoPassword=$$DOLT_MINORDOMO_PASSWORD

	# The secret needs to also be in the default namespace for Jenkins to access it, since Jenkins runs in the default namespace.
	@set -a && . ./.env && set +a && \
	helm upgrade --install \
		--namespace default \
		minordomo-cd-setup helm/minordomo-cd-setup/ \
		--set doltRootPassword=$$DOLT_ROOT_PASSWORD \
		--set doltMinordomoPassword=$$DOLT_MINORDOMO_PASSWORD
