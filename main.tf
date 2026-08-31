##############################################################################
# Data sources
##############################################################################

data "ibm_resource_group" "main" {
  name = var.resource_group
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
  image          = var.image_id
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

##############################################################################
# Patch management (proof-of-concept remote-exec)
##############################################################################

resource "terraform_data" "patch_management" {
  depends_on = [
    ibm_is_instance.main,
    ibm_is_floating_ip.main,
    ibm_is_security_group_rule.ssh,
    ibm_is_security_group_rule.outbound_all
  ]

  triggers_replace = [
    ibm_is_instance.main.id,
    ibm_is_floating_ip.main.address
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = ibm_is_floating_ip.main.address
    private_key = var.ssh_private_key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '=== Step 1: Updating package lists ==='",
      "sudo apt-get update",
      "echo '=== Step 2: Checking available updates ==='",
      "apt list --upgradable 2>/dev/null | tee /tmp/pre-patch-upgrades.txt",
      "PRE_COUNT=$(apt list --upgradable 2>/dev/null | grep -v 'Listing...' | wc -l)",
      "echo \"Packages available for upgrade before patching: $PRE_COUNT\"",
      "echo '=== Step 3: Applying available updates ==='",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "echo '=== Step 4: Verifying server reachability and status ==='",
      "uptime",
      "echo '=== Step 5: Checking remaining upgradeable packages ==='",
      "apt list --upgradable 2>/dev/null | tee /tmp/post-patch-upgrades.txt",
      "POST_COUNT=$(apt list --upgradable 2>/dev/null | grep -v 'Listing...' | wc -l)",
      "echo \"Packages remaining for upgrade after patching: $POST_COUNT\"",
      "echo '=== Patch Management Operation Complete ==='"
    ]
  }
}
