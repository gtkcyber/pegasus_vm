PACKER ?= packer

.PHONY: help init fmt validate arm64 amd64 all clean

help:
	@echo "Targets:"
	@echo "  make init      - install the QEMU plugin"
	@echo "  make fmt       - format the HCL"
	@echo "  make validate  - validate the template"
	@echo "  make arm64     - build the arm64 qcow2  (fast on Apple Silicon)"
	@echo "  make amd64     - build the amd64 qcow2 + OVA  (fast on x86)"
	@echo "  make all       - build both (one will be emulated/slow)"
	@echo "  make clean     - remove output/"

init:
	$(PACKER) init .

fmt:
	$(PACKER) fmt .

validate: init
	$(PACKER) validate .

arm64: init
	$(PACKER) build -only='course.qemu.arm64' .

amd64: init
	$(PACKER) build -only='course.qemu.amd64' .

all: arm64 amd64

clean:
	rm -rf output
