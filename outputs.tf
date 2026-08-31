output "instance_floating_ip" {
  description = "Public floating IP address assigned to the Ubuntu virtual server instance."
  value       = ibm_is_floating_ip.main.address
}

output "patch_result" {
  description = "Status report of the automated patch management remote-exec operation."
  value       = "Patching workflow completed successfully on ${ibm_is_floating_ip.main.address} (${ibm_is_instance.main.name}). Package lists updated, available updates applied via apt-get upgrade, server reachability verified, and remaining upgrade status reported."
  depends_on  = [terraform_data.patch_management]
}

output "instance_id" {
  description = "Resource ID of the created IBM Cloud VPC virtual server instance."
  value       = ibm_is_instance.main.id
}

output "instance_name" {
  description = "Name of the created virtual server instance."
  value       = ibm_is_instance.main.name
}

output "vpc_id" {
  description = "Resource ID of the created IBM Cloud VPC."
  value       = ibm_is_vpc.main.id
}
