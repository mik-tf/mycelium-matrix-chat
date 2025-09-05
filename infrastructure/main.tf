terraform {
  required_providers {
    grid = {
      source  = "threefoldtech/grid"
      version = "~> 1.0"
    }
  }
}

# OpenTofu Configuration
# This configuration works with both Terraform and OpenTofu
# Note: If provider is not available, you may need to use Terraform instead

# Configure the provider
provider "grid" {
  mnemonic = var.mnemonic
  network   = var.network
}

# SSH key for VM access
resource "grid_sshkey" "mmc_key" {
  name   = var.vm_name
  ssh_key = file(var.ssh_public_key_path)
}

# MMC VM deployment
resource "grid_deployment" "mmc_vm" {
  node         = var.node_id
  network_name = grid_network.mmc_network.name

  vms {
    name             = var.vm_name
    flist            = var.flist
    entrypoint       = var.entrypoint
    publicip         = false
    mycelium_ip_seed = var.enable_mycelium
    cpu              = var.cpu_cores
    memory           = var.memory_gb * 1024  # Convert GB to MB
    rootfs_size      = var.disk_gb * 1024    # Convert GB to MB

    env_vars = {
      SSH_KEY = fileexists(var.ssh_public_key_path) ? file(var.ssh_public_key_path) : ""
    }
  }
}

# Network for MMC VM
resource "grid_network" "mmc_network" {
  nodes       = [var.node_id]
  ip_range    = var.network_ip_range
  name        = "${var.vm_name}_network"
  description = "Network for MMC deployment"
  add_wg_access = true
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  filename = "${path.root}/../inventory/hosts.ini"
  content = templatefile("${path.root}/inventory.tpl", {
    vm_ip = grid_deployment.mmc_vm.vms[0].mycelium_ip
    ssh_key_path = var.ssh_private_key_path
  })
}

# Generate WireGuard configuration for access
resource "local_file" "wireguard_config" {
  filename = "${path.root}/../wg-mmc.conf"
  content  = grid_network.mmc_network.access_wg_config
}

# Outputs
output "vm_mycelium_ip" {
  value = grid_deployment.mmc_vm.vms[0].mycelium_ip
  description = "Mycelium IP address of the deployed VM"
}

output "vm_name" {
  value = var.vm_name
  description = "Name of the deployed VM"
}

output "network_name" {
  value = grid_network.mmc_network.name
  description = "Name of the created network"
}

output "wireguard_config_path" {
  value = local_file.wireguard_config.filename
  description = "Path to WireGuard configuration file"
}