resource "oci_core_instance" "gizmo" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.tenancy_ocid

  display_name = var.instance_name
  shape        = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.gizmo.id

    display_name   = var.instance_name
    hostname_label = var.instance_name

    private_ip       = var.instance_private_ip
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_ocid

    boot_volume_size_in_gbs = 47
    boot_volume_vpus_per_gb = 10
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
}

data "oci_core_vnic_attachments" "gizmo" {
  compartment_id = var.tenancy_ocid
  instance_id    = oci_core_instance.gizmo.id
}

data "oci_core_private_ips" "gizmo" {
  vnic_id = data.oci_core_vnic_attachments.gizmo.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id

  display_name = "${var.instance_name}_ip"
  lifetime     = "RESERVED"

  private_ip_id = data.oci_core_private_ips.gizmo.private_ips[0].id

  lifecycle {
    prevent_destroy = true
  }

}
