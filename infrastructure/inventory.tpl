[mmc_servers]
mmc-node-1 ansible_host=${vm_ip} ansible_user=root

[mmc_servers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_path}'
ansible_python_interpreter=/usr/bin/python3