.PHONY: build test unittest lint clean prepare update docker

# change the following boolean flag to enable or disable the Full RELRO (RELocation Read Only) for linux ELF (Executable and Linkable Format) binaries
ENABLE_FULL_RELRO=true
# change the following boolean flag to enable or disable PIE for linux binaries which is needed for ASLR (Address Space Layout Randomization) on Linux, the ASLR support on Windows is enabled by default
ENABLE_PIE=true

MICROSERVICES=cmd/device-rest

.PHONY: $(MICROSERVICES)

ARCH=$(shell uname -m)

DOCKERS=docker_device_rest_go
.PHONY: $(DOCKERS)

VERSION=$(shell cat ./VERSION 2>/dev/null || echo 0.0.0)

ifeq ($(ENABLE_FULL_RELRO), true)
	ENABLE_FULL_RELRO_GOFLAGS = -bindnow
endif

GIT_SHA=$(shell git rev-parse HEAD)
SDKVERSION=$(shell cat ./go.mod | grep 'github.com/edgexfoundry/device-sdk-go/v4 v' | awk '{print $$2}')
GOFLAGS=-ldflags "-s -w -X github.com/edgexfoundry/device-rest-go.Version=$(VERSION) \
                  -X github.com/edgexfoundry/device-sdk-go/v4/internal/common.SDKVersion=$(SDKVERSION) \
                  $(ENABLE_FULL_RELRO_GOFLAGS)" \
                   -trimpath -mod=readonly

ifeq ($(ENABLE_PIE), true)
	GOFLAGS += -buildmode=pie
endif

build: $(MICROSERVICES)

build-nats:
	make -e ADD_BUILD_TAGS=include_nats_messaging build

tidy:
	go mod tidy

cmd/device-rest:
	CGO_ENABLED=0 go build -tags "$(ADD_BUILD_TAGS)" $(GOFLAGS) -o $@ ./cmd

unittest:
	go test ./... -coverprofile=coverage.out ./...

lint:
	@which golangci-lint >/dev/null || echo "WARNING: go linter not installed. To install, run make install-lint"
	@if [ "z${ARCH}" = "zx86_64" ] && which golangci-lint >/dev/null ; then golangci-lint run --config .golangci.yml ; else echo "WARNING: Linting skipped (not on x86_64 or linter not installed)"; fi

install-lint:
	sudo curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $$(go env GOPATH)/bin v1.61.0

test: unittest lint
	go vet ./...
	gofmt -l $$(find . -type f -name '*.go'| grep -v "/vendor/")
	[ "`gofmt -l $$(find . -type f -name '*.go'| grep -v "/vendor/")`" = "" ]
	./bin/test-attribution-txt.sh

clean:
	rm -f $(MICROSERVICES)

update:
	$(GO) mod download

docker: $(DOCKERS)

docker_device_rest_go:
	docker build \
		--build-arg ADD_BUILD_TAGS=$(ADD_BUILD_TAGS) \
		--build-arg http_proxy \
		--build-arg https_proxy \
		--label "git_sha=$(GIT_SHA)" \
		-t edgexfoundry/device-rest:$(GIT_SHA) \
		-t edgexfoundry/device-rest:$(VERSION)-dev \
		.

docker-nats:
	make -e ADD_BUILD_TAGS=include_nats_messaging docker

vendor:
	CGO_ENABLED=0 go mod vendor
