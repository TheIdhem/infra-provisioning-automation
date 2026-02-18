variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "az_suffixes" {
  type    = list(string)
  default = ["a", "b"]
}

variable "environment" {
  type = string
}

variable "vpc_main_cidr" {
  type = string
}

variable "ec2_general_config" {
  type = map(any)
}

variable "keypair_default" {
  type = map(any)
}

variable "internal_domain" {
  type = string
}

variable "public_domain" {
  type = string
}

variable "website_domain" {
  type = string
}

variable "eks_main_managed_node_group_general_settings" {
  type = object({
    desired_size   = number
    min_size       = number
    max_size       = number
    instance_types = list(string)
    capacity_type  = string
  })
}

variable "eks_main_cert_manager_cluster_issuers" {
  type = list(object({
    name        = string
    acme_server = string
    acme_email  = string
  }))
}

variable "rds_msgc_instance_configurations" {
  type = object({
    instance_class        = string
    allocated_storage     = number
    max_allocated_storage = number
  })
}

variable "docdb_datacore_configurations" {
  type = object({
    instance_class = string
  })
}

variable "eks_main_admins" {
  type        = list(string)
  description = "Put the users here you want to access the eks cluster"
}

variable "eks_main_ingress_nginx" {
  type = object({
    min_replicas              = number
    max_replicas              = number
    target_memory_utilization = number
    req_cpu                   = string
    req_mem                   = string
  })
}

variable "slack_alert_hook" {
  type = string
}

variable "cw_alert_lambda_func_path" {
  type = string
}

variable "gb_to_mb" {
  type    = number
  default = 1073741824
}
