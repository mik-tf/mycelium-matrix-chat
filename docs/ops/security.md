# Security Best Practices for MMC Deployment

This document outlines security best practices for the Mycelium-Matrix Chat (MMC) deployment, particularly focusing on handling sensitive credentials like the ThreeFold mnemonic phrase.

## Handling Sensitive Credentials

The ThreeFold Grid deployment requires a mnemonic phrase for authentication, which is a highly sensitive credential that should be protected.

### Secure Method for Setting Credentials

We recommend using environment variables with shell history protection. The variable name `TF_VAR_mnemonic` corresponds to the `mnemonic` variable defined in `infrastructure/variables.tf` and used in `infrastructure/main.tf`.

#### Bash/Zsh
```bash
# This prevents your mnemonic from being stored in shell history
set +o history
export TF_VAR_mnemonic="your_mnemonic_phrase"
set -o history
```

#### Fish Shell
```fish
# Disable history recording for this session
set -l fish_history ""
# Export variable so subprocesses (like OpenTofu) can see it
set -x TF_VAR_mnemonic "your_mnemonic_phrase"
```

**✅ Variable Mapping Confirmed**: `TF_VAR_mnemonic` → `var.mnemonic` → OpenTofu/Terraform provider

### Verifying Variable Setup

You can verify that OpenTofu/Terraform is reading your environment variable correctly:

```bash
# Check if variable is set
echo $TF_VAR_mnemonic  # Should show your mnemonic (be careful!)

# Test OpenTofu variable reading
cd infrastructure
tofu plan  # Should not ask for mnemonic input if TF_VAR_mnemonic is set
```

This approach:
- Keeps sensitive information in memory only, not on disk
- Prevents the command from being saved in your shell history
- Automatically works with the OpenTofu/Terraform `-var` mechanism
- Disappears when you close your terminal session

### Alternative: Credentials File (Not Recommended for Production)

For development/testing, you can create a `credentials.auto.tfvars` file:

```bash
cp infrastructure/credentials.auto.tfvars.example infrastructure/credentials.auto.tfvars
# Edit the file with your mnemonic and other settings
```

⚠️ **Warning**: Never commit `credentials.auto.tfvars` to version control. It's already in `.gitignore` for your protection.

### Verifying Credentials Are Set

To verify your credentials are set (without exposing them):

```bash
# This will show if the variable exists but not its value
env | grep -o TF_VAR_mnemonic
```

If the command returns `TF_VAR_mnemonic`, the variable is set.

## SSH Key Security

MMC deployment uses SSH keys for secure VM access. Best practices:

1. **Use strong, passphrase-protected SSH keys**
2. **Rotate keys regularly** for production deployments
3. **Keep private keys secure** and never share them
4. **Use SSH agent forwarding** instead of storing keys on deployment servers

## Deployment Security

### tfcmd Deployment Security
- Uses SSH keys for VM access (no password authentication)
- Automatically configures firewall rules
- Deploys with minimal attack surface

### Ansible Security
- Uses SSH key-based authentication
- Configures sudo access for deployment user
- Hardens SSH server configuration
- Sets up UFW firewall rules

### Application Security
- Services run as non-root user (`muser`)
- Minimal required ports are open
- System is kept updated during deployment
- SSH root login is disabled

## Environment Variable Management

### Setting Multiple Variables Securely

#### Bash/Zsh
```bash
# Disable history recording
set +o history

# Set your credentials
export TF_VAR_mnemonic="your_mnemonic_phrase_here"
export TF_VAR_node_id="6883"
export TF_VAR_cpu_cores="4"

# Re-enable history (but sensitive commands won't be recorded)
set -o history
```

#### Fish Shell
```fish
# Disable history recording for this session
set -l fish_history ""

# Export variables so subprocesses (like OpenTofu) can see them
set -x TF_VAR_mnemonic "your_mnemonic_phrase_here"
set -x TF_VAR_node_id "6883"
set -x TF_VAR_cpu_cores "4"
```

### Clearing Sensitive Variables

#### Bash/Zsh
```bash
# Clear individual variables
unset TF_VAR_mnemonic

# Clear all TF_VAR_* variables
unset $(env | grep '^TF_VAR_' | cut -d= -f1)
```

#### Fish Shell
```fish
# Clear individual variables
set -e TF_VAR_mnemonic

# Clear all TF_VAR_* variables
for var in (env | grep '^TF_VAR_' | cut -d= -f1)
    set -e $var
end
```

## File-Based Security

### Protected Files

The following files contain sensitive information and are protected by `.gitignore`:

- `infrastructure/credentials.auto.tfvars` - Contains mnemonic and deployment settings
- `inventory/hosts.ini` - Contains VM IP addresses and connection details
- `ansible.log` - May contain sensitive deployment information
- `wg-mmc.conf` - WireGuard configuration (if used)

### Backup Security

When backing up deployment files:
1. **Exclude sensitive files** from backups
2. **Encrypt sensitive backups** if they must be stored
3. **Use secure backup locations** (encrypted drives, secure cloud storage)

## Production Deployment Considerations

### Multi-User Environments

For team deployments:
1. **Use shared credentials management** (e.g., HashiCorp Vault, AWS Secrets Manager)
2. **Implement role-based access control**
3. **Audit credential access** and usage
4. **Rotate credentials regularly**

### CI/CD Integration

For automated deployments:
1. **Use secret management systems** (GitHub Secrets, GitLab CI secrets)
2. **Implement credential rotation** in pipelines
3. **Audit deployment logs** for security events
4. **Use ephemeral deployment environments**

## Monitoring and Auditing

### Security Monitoring

1. **Monitor SSH access logs** on deployed VMs
2. **Check systemd service status** regularly
3. **Monitor firewall rules** and network connections
4. **Audit ansible logs** for unusual activities

### Log Security

```bash
# Check recent SSH connections
sudo journalctl -u ssh -n 50

# Monitor MMC service logs
sudo journalctl -u mmc-web-gateway -f
sudo journalctl -u mmc-matrix-bridge -f
sudo journalctl -u mmc-frontend -f
```

## Emergency Procedures

### Credential Compromise

If credentials are compromised:
1. **Immediately rotate the mnemonic** through ThreeFold Connect
2. **Destroy and redeploy all VMs**
3. **Update all SSH keys**
4. **Audit all access logs** for unauthorized activity

### Security Incident Response

1. **Isolate affected systems**
2. **Preserve evidence** (logs, configurations)
3. **Notify relevant parties**
4. **Implement fixes** and security improvements

## Additional Security Resources

- [ThreeFold Grid Security Documentation](https://library.threefold.me/info/manual/#/manual__grid_security)
- [OpenTofu Security Best Practices](https://opentofu.org/docs/intro/security/)
- [Ansible Security Best Practices](https://docs.ansible.com/ansible/latest/user_guide/security.html)
- [OWASP DevSecOps Guidelines](https://owasp.org/www-project-devsecops-guideline/)

For enterprise deployments or advanced security requirements, consider consulting with security professionals or implementing dedicated secret management solutions.