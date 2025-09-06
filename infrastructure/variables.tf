# ThreeFold Grid Configuration
variable "mnemonic" {
  description = "ThreeFold mnemonic phrase for authentication"
  type        = string
  sensitive   = true
}

variable "network" {
  description = "ThreeFold network to deploy to"
  type        = string
  default     = "main"
}

# VM Configuration
variable "vm_name" {
  description = "Name of the VM to deploy"
  type        = string
  default     = "myceliumchat"
}

variable "node_id" {
  description = "ThreeFold Grid node ID to deploy to"
  type        = number
  default     = 6883
}

variable "cpu_cores" {
  description = "Number of CPU cores for the VM"
  type        = number
  default     = 4
}

variable "memory_gb" {
  description = "Memory size in GB"
  type        = number
  default     = 16
}

variable "disk_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 250
}

variable "enable_mycelium" {
  description = "Enable mycelium networking"
  type        = bool
  default     = true
}

# VM Image Configuration
variable "flist" {
  description = "Flist URL for the VM image"
  type        = string
  default     = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
}

variable "entrypoint" {
  description = "Entrypoint for the VM"
  type        = string
  default     = "/sbin/zinit init"
}

# SSH Configuration
variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# Network Configuration
variable "network_ip_range" {
  description = "IP range for the private network"
  type        = string
  default     = "10.1.0.0/16"
}

variable "wireguard_endpoint" {
  description = "WireGuard endpoint IP for access (optional, leave empty for auto-detection)"
  type        = string
  default     = ""
}

# Flexible Deployment Options
variable "enable_public_ipv4" {
  description = "Enable public IPv4 access for domain-based deployment"
  type        = bool
  default     = false
}