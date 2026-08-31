output "instance_floating_ip" {
  description = "Public floating IP address assigned to the Ubuntu virtual server instance."
  value       = ibm_is_floating_ip.main.address
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
