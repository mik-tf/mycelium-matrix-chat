terraform {
  required_providers {
    grid = {
      source = "threefoldtech/grid"
    }
  }
}

# OpenTofu Configuration
# This configuration works with both Terraform and OpenTofu
# Note: If provider is not available, you may need to use Terraform instead

# Configure the provider
provider "grid" {
  mnemonic  = var.mnemonic
  network   = var.network
  relay_url = "wss://relay.grid.tf"
}

# Generate mycelium keys and IP seed
resource "random_bytes" "mycelium_key" {
  length = 32
}

resource "random_bytes" "mycelium_ip_seed" {
  length = 6
}

# MMC VM deployment
resource "grid_deployment" "mmc_vm" {
  node         = var.node_id
  network_name = grid_network.mmc_network.name

  vms {
    name             = var.vm_name
    flist            = var.flist
    entrypoint       = var.entrypoint
    publicip         = var.enable_public_ipv4
    mycelium_ip_seed = random_bytes.mycelium_ip_seed.hex
    cpu              = var.cpu_cores
    memory           = var.memory_gb * 1024  # Convert GB to MB
    rootfs_size      = var.disk_gb * 1024    # Convert GB to MB

    env_vars = {
      SSH_KEY = fileexists(var.ssh_public_key_path) ? file(var.ssh_public_key_path) : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }
  }
}

# Network for MMC VM
resource "grid_network" "mmc_network" {
  nodes         = [var.node_id]
  ip_range      = var.network_ip_range
  name          = "${var.vm_name}_network"
  description   = "Network for MMC deployment"
  add_wg_access = false  # Disabled since MMC uses mycelium networking
  mycelium_keys = {
    (var.node_id) = random_bytes.mycelium_key.hex
  }
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  filename = "${path.root}/../platform/inventory/hosts.ini"
  content = templatefile("${path.root}/inventory.tpl", {
    vm_ip = grid_deployment.mmc_vm.vms[0].mycelium_ip
    ssh_key_path = var.ssh_private_key_path
  })
}

# WireGuard configuration disabled since MMC uses mycelium networking
# resource "local_file" "wireguard_config" {
#   filename = "${path.root}/../wg-mmc.conf"
#   content  = grid_network.mmc_network.access_wg_config
# }

# Outputs
output "vm_mycelium_ip" {
  value = grid_deployment.mmc_vm.vms[0].mycelium_ip
  description = "Mycelium IP address of the deployed VM"
}

output "vm_public_ip" {
  value = var.enable_public_ipv4 ? grid_deployment.mmc_vm.vms[0].computedip : null
  description = "Public IPv4 address (only available when enable_public_ipv4 = true)"
}

output "vm_name" {
  value = var.vm_name
  description = "Name of the deployed VM"
}

output "network_name" {
  value = grid_network.mmc_network.name
  description = "Name of the created network"
}

output "deployment_type" {
  value = var.enable_public_ipv4 ? "IPv4 + Domain" : "Mycelium-Only"
  description = "Type of deployment based on IPv4 configuration"
}

output "access_urls" {
  value = var.enable_public_ipv4 ? [
    "https://[domain]:443 (configure DNS)",
    "https://${grid_deployment.mmc_vm.vms[0].mycelium_ip}:443"
  ] : [
    "https://${grid_deployment.mmc_vm.vms[0].mycelium_ip}:443"
  ]
  description = "Available access URLs for the deployment"
}

# WireGuard config disabled since MMC uses mycelium
# output "wireguard_config_path" {
#   value = local_file.wireguard_config.filename
#   description = "Path to WireGuard configuration file"
# }