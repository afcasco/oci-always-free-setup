resource "oci_core_vcn" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id

  cidr_blocks = [
    var.vcn_cidr
  ]

  display_name = "vcn-20230126-1553"
  dns_label    = "vcn01261555"
}

resource "oci_core_internet_gateway" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id
  vcn_id         = oci_core_vcn.gizmo.id

  display_name = "Internet Gateway vcn-20230126-1553"
  enabled      = true
}

resource "oci_core_route_table" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id
  vcn_id         = oci_core_vcn.gizmo.id

  display_name = "Default Route Table for vcn-20230126-1553"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.gizmo.id
  }
}

resource "oci_core_security_list" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id
  vcn_id         = oci_core_vcn.gizmo.id

  display_name = "Default Security List for vcn-20230126-1553"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # ICMP destination unreachable / fragmentation needed.
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP destination unreachable from inside the VCN.
  ingress_security_rules {
    protocol = "1"
    source   = var.vcn_cidr

    icmp_options {
      type = 3
    }
  }

  ingress_security_rules {
    description = "http"
    protocol    = "6"
    source      = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    description = "https"
    protocol    = "6"
    source      = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    description = "wireguard"
    protocol    = "17"
    source      = "0.0.0.0/0"

    udp_options {
      min = 51820
      max = 51820
    }
  }
}

resource "oci_core_subnet" "gizmo" {
  compartment_id = oci_identity_compartment.infra.id
  vcn_id         = oci_core_vcn.gizmo.id

  cidr_block   = var.subnet_cidr
  display_name = "subnet-20230126-1553"
  dns_label    = "subnet01261555"

  prohibit_public_ip_on_vnic = false

  route_table_id = oci_core_route_table.gizmo.id

  security_list_ids = [
    oci_core_security_list.gizmo.id
  ]
}
