resource "oci_core_volume" "gizmo_data" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = oci_identity_compartment.infra.id

  display_name = "${var.instance_name}-data"

  size_in_gbs = var.data_volume_size_gb
  vpus_per_gb = var.data_volume_vpus_per_gb
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "gizmo_data" {
  attachment_type = "paravirtualized"

  instance_id = oci_core_instance.gizmo.id
  volume_id   = oci_core_volume.gizmo_data.id

  display_name = "volumeattachment20260712062810"
}
