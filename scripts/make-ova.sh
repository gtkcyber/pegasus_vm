#!/usr/bin/env bash
#
# make-ova.sh  <input.qcow2>  <output.ova>  [memory_mb]  [cpus]
# -----------------------------------------------------------------------------
# Convert a qcow2 disk into a streamOptimized VMDK and wrap it in a minimal,
# VirtualBox/Fusion-importable OVA. Pure qemu-img + tar; no hypervisor needed
# on the build host.
# -----------------------------------------------------------------------------
set -euo pipefail

IN="${1:?usage: make-ova.sh <input.qcow2> <output.ova> [memory_mb] [cpus]}"
OUT="${2:?missing output .ova path}"
MEM="${3:-4096}"
CPUS="${4:-2}"

[[ -f "$IN" ]] || { echo "input not found: $IN" >&2; exit 1; }
command -v qemu-img >/dev/null || { echo "qemu-img not found (brew install qemu)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VMNAME="$(basename "${OUT%.ova}")"
VMDK="${VMNAME}.vmdk"
OVF="${VMNAME}.ovf"

echo "==> Converting to streamOptimized VMDK"
qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized "$IN" "${WORK}/${VMDK}"

# Virtual capacity (bytes) from the source image; VMDK file size from disk.
CAPACITY="$(qemu-img info "$IN" | sed -n 's/.*(\([0-9]\+\) bytes).*/\1/p' | head -n1)"
VMDK_SIZE="$(wc -c < "${WORK}/${VMDK}" | tr -d ' ')"

echo "==> Writing OVF (capacity=${CAPACITY} vmdk=${VMDK_SIZE} mem=${MEM}MB cpus=${CPUS})"
cat > "${WORK}/${OVF}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope ovf:version="1.0" xml:lang="en-US"
  xmlns="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
  xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="${VMDK}" ovf:id="file1" ovf:size="${VMDK_SIZE}"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${CAPACITY}" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks</Info>
    <Network ovf:name="NAT"><Description>NAT network</Description></Network>
  </NetworkSection>
  <VirtualSystem ovf:id="${VMNAME}">
    <Info>Cybersecurity course VM</Info>
    <Name>${VMNAME}</Name>
    <OperatingSystemSection ovf:id="94">
      <Info>Installed guest operating system</Info>
      <Description>Ubuntu Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${VMNAME}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>${CPUS} virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>${CPUS}</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>${MEM} MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>${MEM}</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:ElementName>sataController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF

echo "==> Packing OVA (OVF first, then VMDK)"
# OVF must be the first entry in the tar for a valid OVA.
( cd "$WORK" && tar -cf "${VMNAME}.ova" "${OVF}" "${VMDK}" )
mkdir -p "$(dirname "$OUT")"
mv "${WORK}/${VMNAME}.ova" "$OUT"
echo "==> Wrote ${OUT}"
