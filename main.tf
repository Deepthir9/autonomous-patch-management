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
  # Replace instance when the SSH key fingerprint changes so cloud-init installs the current key.
  lifecycle {
    ignore_changes = [image]
    replace_triggered_by = [
      ibm_is_ssh_key.main.fingerprint
    ]
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
      "echo '=== [1/7] Patching Started: Initializing SSH session on Ubuntu VM ==='",
      "echo 'Host: '$(hostname)' | Current Time: '$(date -u)",
      "echo '=== [2/7] Updating package index (apt-get update) ==='",
      "sudo apt-get update -y",
      "echo 'Package update completed.'",
      "echo '=== [3/7] Checking available package updates ==='",
      "apt list --upgradable 2>/dev/null | tee /tmp/pre-patch-upgrades.txt",
      "PRE_COUNT=$(apt list --upgradable 2>/dev/null | grep -v 'Listing...' | wc -l | tr -d ' ')",
      "echo \"Number of available updates before patching: $PRE_COUNT\"",
      "echo '=== [4/7] Applying available updates (apt-get upgrade) ==='",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "echo 'Package upgrade completed successfully.'",
      "echo '=== [5/7] Checking reboot requirement status ==='",
      "if [ -f /var/run/reboot-required ]; then echo 'Reboot requirement status: REBOOT REQUIRED (packages: /var/run/reboot-required.pkgs)'; else echo 'Reboot requirement status: NO REBOOT REQUIRED'; fi",
      "echo '=== [6/7] Verifying server reachability and uptime ==='",
      "uptime",
      "echo 'Server reachability verified.'",
      "echo '=== [7/7] Checking remaining upgradeable packages ==='",
      "apt list --upgradable 2>/dev/null | tee /tmp/post-patch-upgrades.txt",
      "POST_COUNT=$(apt list --upgradable 2>/dev/null | grep -v 'Listing...' | wc -l | tr -d ' ')",
      "echo \"Number of remaining upgradeable packages: $POST_COUNT\"",
      "echo '=== Final Patch Status: SUCCESS - Patch management workflow finished ==='"
    ]
  }
}
