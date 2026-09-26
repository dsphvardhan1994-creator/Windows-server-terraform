variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "harsha-windows"
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "lab"
}

variable "vpc_cidr" {
  description = "CIDR for the new VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. Windows with Python packages benefits from 4 GiB RAM."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Encrypted root volume size in GiB."
  type        = number
  default     = 60
}

variable "windows_username" {
  description = "Local Windows account used in Fleet Manager."
  type        = string
  default     = "harsha"
}

variable "windows_password" {
  description = "Password for the local Windows account. Terraform prompts when not supplied."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.windows_password) >= 12 && can(regex("[A-Z]", var.windows_password)) && can(regex("[a-z]", var.windows_password)) && can(regex("[0-9]", var.windows_password)) && can(regex("[^A-Za-z0-9]", var.windows_password))
    error_message = "Use at least 12 characters with upper, lower, numeric, and special characters."
  }
}

variable "python_installer_url" {
  description = "Official 64-bit Python installer URL."
  type        = string
  default     = "https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe"
}

variable "attach_fleet_manager_policy_to_instance_role" {
  description = "Optional: also attach operator policy to EC2's role. Normally leave false and attach it to the human/operator role."
  type        = bool
  default     = false
}
