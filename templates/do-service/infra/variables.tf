variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.do_token)) > 0
    error_message = "do_token must not be empty or whitespace-only."
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
    condition     = var.volume_size_gb >= 1 && var.volume_size_gb == floor(var.volume_size_gb)
    error_message = "volume_size_gb must be an integer >= 1."
  }
}
