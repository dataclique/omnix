variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.do_token) > 0
    error_message = "do_token must not be empty."
  }
}

variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean"
  type        = string
  default     = "my-service-op"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "Droplet size"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "volume_size_gb" {
  description = "Data volume size in GB"
  type        = number
  default     = 5

  validation {
    condition     = var.volume_size_gb >= 1
    error_message = "volume_size_gb must be at least 1."
  }
}
