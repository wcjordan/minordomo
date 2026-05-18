.PHONY: test
test:
	bash test/run-all.sh

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
