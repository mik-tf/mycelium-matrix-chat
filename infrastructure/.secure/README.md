# Secure Credential Storage

This directory contains examples and templates for secure credential management following industry best practices.

## Industry Standard Approaches

### 1. Environment Variables (CI/CD, Automation)
```bash
export TF_VAR_mnemonic="your_mnemonic_phrase"
```

### 2. Local Config Files (Development)
```bash
# Create secure config directory
mkdir -p ~/.config/threefold
echo "your_mnemonic_phrase" > ~/.config/threefold/mnemonic
chmod 600 ~/.config/threefold/mnemonic
```

### 3. Encrypted Files (Production)
```bash
# Using GPG encryption
echo "your_mnemonic_phrase" | gpg --encrypt --recipient your-email@example.com > mnemonic.gpg
```

### 4. Secret Management Systems (Enterprise)
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- Kubernetes Secrets

## Priority Order

The deployment system checks for credentials in this order:

1. **TF_VAR_mnemonic** environment variable (highest priority)
2. **~/.config/threefold/mnemonic** file
3. **~/.threefold/mnemonic** file
4. Interactive prompt (fallback)

## Security Best Practices

- ✅ Never commit credentials to version control
- ✅ Use restrictive file permissions (600)
- ✅ Encrypt sensitive files when possible
- ✅ Rotate credentials regularly
- ✅ Use different credentials for different environments
- ✅ Audit credential access logs

## Examples

See the example files in this directory for secure configuration templates.