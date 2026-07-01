variable "location" {
  type        = string
  default     = "Central US"
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  default     = "RG-FileServerLab"
  description = "Must stay consistent — Lab 2 references this name."
}

variable "vnet_name" {
  type    = string
  default = "VNET-FileServerLab"
}

variable "subnet_name" {
  type    = string
  default = "Subnet-Servers"
}

variable "vnet_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "nsg_name" {
  type    = string
  default = "NSG-RDP"
}

variable "rdp_source" {
  type        = string
  default     = "*"
  description = "Your public IP in CIDR format — e.g. 1.2.3.4/32."
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_admin_password env var — never in a file."
}

variable "server_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "client_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}