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

