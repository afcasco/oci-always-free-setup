output "instance_id" {
  value = oci_core_instance.gizmo.id
}

output "instance_private_ip" {
  value = var.instance_private_ip
}

output "instance_public_ip" {
  value = oci_core_public_ip.gizmo.ip_address
}

output "data_volume_id" {
  value = oci_core_volume.gizmo_data.id
}

output "vcn_id" {
  value = oci_core_vcn.gizmo.id
}

output "subnet_id" {
  value = oci_core_subnet.gizmo.id
}
