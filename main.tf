##############################################################################
# Data sources
##############################################################################

data "ibm_resource_group" "main" {
  name = var.resource_group
}

# Resolve the latest available Ubuntu 24.04 LTS image in the target region.
# ibm_is_images supports visibility and status as top-level filter arguments.
# Name filtering is done in the locals block below via a for expression.
data "ibm_is_images" "ubuntu" {
  visibility = "public"
  status     = "available"
}

locals {
  # Sort matching images by created_at descending and take the newest one.
  # This is deterministic regardless of API return order.
  ubuntu_image_id = reverse(sort([
    for img in data.ibm_is_images.ubuntu.images : img.id
    if startswith(img.name, "ibm-ubuntu-24-04")
  ]))[0]
}

##############################################################################
# VPC
##############################################################################

resource "ibm_is_vpc" "main" {
  name           = "${var.instance_name}-vpc"
  resource_group = data.ibm_resource_group.main.id
}

##############################################################################
# Subnet
##############################################################################

resource "ibm_is_subnet" "main" {
  name                     = "${var.instance_name}-subnet"
  vpc                      = ibm_is_vpc.main.id
  zone                     = var.zone
  total_ipv4_address_count = 256
  resource_group           = data.ibm_resource_group.main.id
}

##############################################################################
# Security group
##############################################################################

resource "ibm_is_security_group" "main" {
  name           = "${var.instance_name}-sg"
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.main.id
}

# Allow inbound SSH (TCP 22) from any source.
# Uses flat port_min / port_max / protocol arguments — the nested tcp {} block
# is a legacy form removed in provider >= 1.60 and unsupported in Schematics.
resource "ibm_is_security_group_rule" "ssh" {
  group     = ibm_is_security_group.main.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  protocol  = "tcp"
  port_min  = 22
  port_max  = 22
}

# Allow all outbound traffic so the instance can reach package repositories.
resource "ibm_is_security_group_rule" "outbound_all" {
  group     = ibm_is_security_group.main.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

##############################################################################
# SSH key
##############################################################################

resource "ibm_is_ssh_key" "main" {
  name           = "${var.instance_name}-key"
  public_key     = var.ssh_public_key
  resource_group = data.ibm_resource_group.main.id
}

##############################################################################
# Virtual server instance
##############################################################################

resource "ibm_is_instance" "main" {
  name           = "${var.instance_name}-vsi"
  image          = local.ubuntu_image_id
  profile        = "bx2-2x8" # 2 vCPU / 8 GB — lowest-cost balanced profile
  zone           = var.zone
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.main.id
  keys           = [ibm_is_ssh_key.main.id]

  # Use the legacy primary_network_interface block (not the new VNI attachment
  # API) so that primary_network_interface[0].id remains a stable target for
  # the floating IP resource below.
  primary_network_interface {
    subnet          = ibm_is_subnet.main.id
    security_groups = [ibm_is_security_group.main.id]
  }

  # Prevent re-creation when a newer Ubuntu image is published after the
  # instance was first provisioned — matches the official IBM module pattern.
  lifecycle {
    ignore_changes = [image]
  }
}

##############################################################################
# Floating IP
##############################################################################

resource "ibm_is_floating_ip" "main" {
  name           = "${var.instance_name}-fip"
  target         = ibm_is_instance.main.primary_network_interface[0].id
  resource_group = data.ibm_resource_group.main.id
}
