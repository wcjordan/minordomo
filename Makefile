.PHONY: test
test:
	bash test/run-all.sh

.env:
	cp .env.example .env
	@PASS=$$(openssl rand -hex 24); \
	sed -i.bak "s/^DOLT_ROOT_PASSWORD=$$/DOLT_ROOT_PASSWORD=$$PASS/" .env && rm -f .env.bak
	@echo "Generated .env with random DOLT_ROOT_PASSWORD"

.PHONY: setup-cd
setup-cd: .env
	@set -a && . ./.env && set +a && \
	helm upgrade --install minordomo-cd-setup helm/minordomo-cd-setup/ \
		--set doltRootPassword=$$DOLT_ROOT_PASSWORD
