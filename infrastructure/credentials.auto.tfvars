# ThreeFold Grid Configuration
# Copy this file to credentials.auto.tfvars and fill in your values

# VM Configuration
vm_name = "myceliumchat"
node_id = 6883
cpu_cores = 4
memory_gb = 16
disk_gb = 250
enable_mycelium = true

# VM Image
flist = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
entrypoint = "/sbin/zinit init"

# SSH Keys (auto-detected if not specified)
# ssh_public_key_path = "~/.ssh/id_ed25519.pub"
# ssh_private_key_path = "~/.ssh/id_ed25519"

# Network
network_ip_range = "10.1.0.0/16"