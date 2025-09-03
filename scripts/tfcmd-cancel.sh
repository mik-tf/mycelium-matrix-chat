#!/bin/bash

# =====================================================================================
# Automated TFGrid Deployment Script for Mycelium-Matrix Chat
# =====================================================================================
# This script automates the complete deployment process:
# 1. Deploy VM using tfcmd
# 2. Extract mycelium IP from tfcmd output
# 3. Deploy Mycelium-Matrix Chat using the deployment script
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

# VM Deployment Parameters
VM_NAME="myceliumchat"

tfcmd cancel "$VM_NAME"