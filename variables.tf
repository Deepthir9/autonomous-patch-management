variable "ibmcloud_api_key" {
  description = "IBM Cloud API key used to authenticate with the IBM Cloud platform."
  type        = string
  sensitive   = true
}

variable "instance_name" {
  description = "Name prefix applied to all created resources (VPC, subnet, security group, VSI, etc.)."
  type        = string
  default     = "apm-demo"
}

variable "region" {
  description = "IBM Cloud region in which to deploy all resources (e.g. us-south, eu-de)."
  type        = string
  default     = "us-south"
}

variable "resource_group" {
  description = "Name of the existing IBM Cloud resource group in which to create resources."
  type        = string
  default     = "Default"
}

variable "ssh_public_key" {
  description = "SSH public key material (the contents of your ~/.ssh/id_rsa.pub or equivalent). Used to access the virtual server instance."
  type        = string
  sensitive   = true
}

variable "ssh_private_key" {
  description = "SSH private key material corresponding to ssh_public_key. Used for remote-exec patch management over SSH."
  type        = string
  sensitive   = true
}

variable "zone" {
  description = "Availability zone within the chosen region (e.g. us-south-1)."
  type        = string
  default     = "us-south-1"
}

variable "image_id" {
  description = <<-EOT
    ID of the IBM Cloud VPC stock image to use for the virtual server instance.
    Must be a public Ubuntu 24.04 LTS image available in the target region.

    Look up the current ID with:
      ibmcloud is images --visibility public --status available | grep ibm-ubuntu-24-04

    Example (us-south, May 2025): r006-867f36e5-f875-4571-9c60-b4ea9a0bc1b9
  EOT
  type        = string
}
