variable "region" {
  default = "us-east-1"
}

variable "db_password" {
  description = "RDS MySQL root password"
  type        = string
  sensitive   = true
}

variable "db_username" {
  default = "appuser"
}

variable "db_name" {
  default = "appdb"
}

variable "repo_url" {
  description = "GitHub repo containing both backend/ and client/"
  type        = string
}