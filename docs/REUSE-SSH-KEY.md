# Reusing Your SSH Key for Multiple Azure ML VMs

## Quick Answer

**Yes!** You can reuse the same .pem key across multiple VMs by copying the **public key** into Azure when creating each new VM.

## Steps

### 1. Extract the Public Key from Your .pem

```bash
# If your .pem is an OpenSSH private key
ssh-keygen -y -f ~/.ssh/your-key.pem > ~/.ssh/your-key.pub

# Example with your key
ssh-keygen -y -f ~/.ssh/rarko1.pem > ~/.ssh/rarko1.pub
```

### 2. View Your Public Key

```bash
cat ~/.ssh/rarko1.pub
# Copy this entire output (starts with ssh-rsa or ssh-ed25519)
```

### 3. Create New Azure ML VM

When creating the VM in Azure ML:
1. Go to "Compute" → "Compute instances" → "New"
2. Choose your VM size and settings
3. Under **"SSH settings"**:
   - Select **"Use existing public key"**
   - Paste your **public key** (from step 2) into the text box
4. Create the VM

### 4. Connect to the New VM

Update your SSH config with the new VM's details:

```bash
# Run the setup script
cd ~/dev/arrive-aml  # or wherever you cloned it
bash scripts/setup-azureml-ssh.sh

# Enter:
# - New VM hostname/alias (e.g., rarko2)
# - New VM's public IP (from Azure portal)
# - Same .pem file path (reused!)
```

## Best Practice: Keep Keys Organized

```bash
# Recommended structure
~/.ssh/
├── azure-ml-master.pem      # Your master private key (NEVER share)
├── azure-ml-master.pub      # Public key (safe to share/paste)
├── config                    # SSH config for all VMs
└── known_hosts              # Auto-populated

# In SSH config:
Host rarko1
    HostName 1.2.3.4
    IdentityFile ~/.ssh/azure-ml-master.pem

Host rarko2
    HostName 5.6.7.8
    IdentityFile ~/.ssh/azure-ml-master.pem  # Same key!

Host rarko3
    HostName 9.10.11.12
    IdentityFile ~/.ssh/azure-ml-master.pem  # Same key!
```

## Security Note

- **Private key (.pem)**: NEVER share, NEVER upload to Azure, keep secure (chmod 400)
- **Public key (.pub)**: Safe to paste into Azure, GitHub, authorized_keys, etc.
- Each VM you create with the same public key will accept your private key for authentication

## Alternative: Auto-Generate Per VM

If you prefer unique keys per VM (more secure but less convenient):
1. Choose "Generate new SSH key pair" in Azure
2. Download the new .pem when prompted
3. Run `setup-azureml-ssh.sh` with the new .pem path

## Which Approach?

**One key for all VMs:**
- ✅ Convenient - manage one key
- ✅ Quick setup for new VMs
- ⚠️ If compromised, all VMs affected

**Unique key per VM:**
- ✅ Better security isolation
- ✅ Revoke access to one VM without affecting others
- ⚠️ More keys to manage

**Recommendation**: For personal development VMs in the same org, one key is fine. For production or shared resources, use unique keys.
