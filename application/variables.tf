variable "tags" {
  type        = map
  description = "Tags to assign to resources"
  default = {
    deployment    = "Terraform"
    terraform_version = "1.2.9"
  }
}