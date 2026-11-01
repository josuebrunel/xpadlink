TOKEN  ?= abc
LISTEN ?= :9777
BIN    := server/xpadlinkd

.PHONY: help build run dry sim test vet fmt clean uinput-setup firewall app app-run app-clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

build: ## Build the xpadlinkd server
	cd server && go build -o xpadlinkd ./cmd/xpadlinkd

run: build ## Run xpadlinkd (TOKEN=... LISTEN=...)
	$(BIN) -listen $(LISTEN) -token $(TOKEN)

dry: build ## Run xpadlinkd without uinput (logs input)
	$(BIN) -dry -listen $(LISTEN) -token $(TOKEN)

sim: ## Simulate a phone against a running server (TOKEN=...)
	cd server && go run ./cmd/xpadsim -token $(TOKEN) -for 20s

test: ## Run Go tests
	cd server && go test ./...

vet: ## Run go vet
	cd server && go vet ./...

fmt: ## Format Go code
	cd server && gofmt -w .

clean: ## Remove built binaries
	rm -f $(BIN)

uinput-setup: ## One-time uinput access (needs sudo, then re-login)
	sudo modprobe uinput
	echo uinput | sudo tee /etc/modules-load.d/uinput.conf
	sudo cp 99-xpadlink-uinput.rules /etc/udev/rules.d/
	sudo udevadm control --reload && sudo udevadm trigger
	sudo usermod -aG input $$USER
	@echo "Log out and back in for the input group to apply."

firewall: ## Open UDP 9777 with ufw
	sudo ufw allow 9777/udp

app: ## Generate the Flutter Android project
	cd app && ./setup.sh

app-run: ## Run the app on a connected phone
	cd app/xpadlink_app && flutter run

app-clean: ## Remove the generated Flutter project
	rm -rf app/xpadlink_app
