output "state_bucket_name" {
  value = oci_objectstorage_bucket.terraform_state.name
}

output "object_storage_namespace" {
  value = data.oci_objectstorage_namespace.this.namespace
}
