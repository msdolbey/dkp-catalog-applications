CI_DOCKERFILE ?= $(REPO_ROOT)/Dockerfile.ci

ifneq ($(wildcard $(CI_DOCKERFILE)),)
CI_DOCKER_TAG ?= $(shell (cat $(CI_DOCKERFILE) $(CI_DOCKER_EXTRA_FILES) \
                         $(if $(CI_DOCKER_BUILD_ARGS),&& echo $(CI_DOCKER_BUILD_ARGS))) \
                         | shasum | awk '{ print $$1 }')
CI_DOCKER_IMG ?= $(GITHUB_ORG)/$(GITHUB_REPOSITORY)-ci:$(CI_DOCKER_TAG)

export GOLANG_VERSION ?= 1.19.1
DOCKER_VERSION ?= 20.10.7

.PHONY: dockerauth
dockerauth:
ifdef DOCKER_USERNAME
ifdef DOCKER_PASSWORD
	$(info $(M) Logging in to Docker Hub)
	echo -n $(DOCKER_PASSWORD) | docker login -u $(DOCKER_USERNAME) --password-stdin
endif
endif

.PHONY: ci.docker.ensure
ci.docker.ensure: ## Ensures the docker image is locally available
ci.docker.ensure: dockerauth ; $(info $(M) Ensuring CI Docker image is available locally)
	(docker image inspect $(CI_DOCKER_IMG) &>/dev/null && echo '$(CI_DOCKER_IMG) already exists - skipping image build' ) || \
		docker pull $(CI_DOCKER_IMG) || \
		$(MAKE) ci.docker.build

.PHONY: ci.docker.build
ci.docker.build: ## Builds the CI Docker image
ci.docker.build: dockerauth ; $(info $(M) Building CI Docker image)
	DOCKER_BUILDKIT=1 docker build \
		--tag $(CI_DOCKER_IMG) \
		--build-arg DOCKER_VERSION=$(DOCKER_VERSION) \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		$(if $(CI_DOCKER_BUILD_ARGS),$(addprefix --build-arg ,$(CI_DOCKER_BUILD_ARGS))) \
		-f $(CI_DOCKERFILE) .

.PHONY: ci.docker.push
ci.docker.push: ## Pushes the CI Docker image
ci.docker.push: ci.docker.ensure ; $(info $(M) Pushes the CI Docker image)
	docker push $(CI_DOCKER_IMG)

.PHONY: ci.docker.run
ci.docker.run: ## Runs the build in the CI Docker image.
ci.docker.run: RUN_WHAT ?=
ci.docker.run: ci.docker.ensure ; $(info $(M) Runs the build in the CI Docker image)
	docker run --rm -i$(if $(RUN_WHAT),,$(if $(INTERACTIVE),t)) \
		-v $(REPO_ROOT):$(REPO_ROOT) \
 		-w $(REPO_ROOT) \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v /etc/docker/certs.d:/etc/docker/certs.d \
		$(if $(AWS_REGION),-e AWS_REGION=$(AWS_REGION)) \
		$(if $(AWS_ACCESS_KEY_ID),-e AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)) \
		$(if $(AWS_SECRET_ACCESS_KEY),-e AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)) \
		$(if $(AWS_SESSION_TOKEN),-e AWS_SESSION_TOKEN=$(AWS_SESSION_TOKEN)) \
		$(if $(DOCKER_USERNAME),-e DOCKER_USERNAME=$(DOCKER_USERNAME)) \
		$(if $(DOCKER_PASSWORD),-e DOCKER_PASSWORD=$(DOCKER_PASSWORD)) \
		$(if $(SLACK_WEBHOOK),-e SLACK_WEBHOOK=$(SLACK_WEBHOOK)) \
		$(if $(SSH_AUTH_SOCK),-v $(SSH_AUTH_SOCK):$(SSH_AUTH_SOCK) -e SSH_AUTH_SOCK=$(SSH_AUTH_SOCK)) \
		$(if $(GITHUB_USER_TOKEN),-e GITHUB_USER_TOKEN=$(GITHUB_USER_TOKEN) -e GITHUB_TOKEN=$(GITHUB_USER_TOKEN),$(if $(GITHUB_TOKEN),-e GITHUB_TOKEN=$(GITHUB_TOKEN))) \
		--net=host \
		$(CI_DOCKER_IMG) \
		$(if $(RUN_WHAT),bash -ec "$(RUN_WHAT)")

endif
