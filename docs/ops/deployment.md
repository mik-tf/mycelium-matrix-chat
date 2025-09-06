# Complete Guide: Running Mycelium-Matrix Chat Homeservers with P2P Enhancement

## **Understanding Homeservers in Mycelium-Matrix Chat**

Each deployment of the mycelium-matrix-chat repository creates a **Matrix homeserver** - a complete chat server that can host users and rooms. Matrix's federation protocol allows these homeservers to communicate with each other, while Mycelium adds an encrypted P2P overlay for enhanced privacy and performance.

## **How Multiple Homeservers Work**

### **1. Independent Deployments with Federation**
Each homeserver is a separate deployment that can federate:
- **chat.projectmycelium.org** (existing)
- **your-org-chat.com** (your deployment)
- **friends-chat.net** (another person's deployment)

### **2. Federation + Mycelium Enhancement**
```
User A @alice:chat.projectmycelium.org
    ↓
Can chat with (Standard Matrix Federation)
    ↓
User B @bob:your-org-chat.com
    ↓
Enhanced with Mycelium P2P (when available)
    ↓
Direct encrypted P2P routing
```

## **Step-by-Step: Deploying Your Own Homeserver**

### **Prerequisites**
- Domain name (e.g., `your-chat.example.com`)
- ThreeFold account with TFT balance
- SSH keys configured

### **Deployment Process**

**1. Clone and Configure**
```bash
git clone https://github.com/mik-tf/mycelium-matrix-chat
cd mycelium-matrix-chat

# Configure your domain in nginx config
nano config/nginx.conf
# Change: server_name chat.projectmycelium.org;
# To:     server_name your-chat.example.com;
```

**2. Set Up Credentials**
```bash
# Secure credential setup
set +o history
export TF_VAR_mnemonic="your_threefold_mnemonic"
set -o history
```

**3. Deploy Infrastructure (Includes Mycelium)**
```bash
# Deploy VM on ThreeFold Grid + Mycelium setup
make vm

# Prepare VM with required software
make prepare

# Deploy MMC application
make app

# Validate deployment
make validate
```

**4. DNS Configuration**
Point your domain to the deployed VM's IP:
```
Type: A
Name: your-chat
Value: [VM_IP_from_make_status]
```

**5. SSL Setup**
```bash
# Connect to VM and set up SSL
make connect
sudo certbot --nginx -d your-chat.example.com
```

## **Mycelium Integration Architecture**

### **Infrastructure Layer**
```
ThreeFold Grid VM Deployment
        ↓
Ubuntu 24.04 + Mycelium Client
        ↓
Automatic IPv6 Address Assignment
        ↓
Mycelium P2P Network Join
```

**What happens during `make vm`:**
- Terraform deploys VM on ThreeFold Grid
- Mycelium client installed and configured
- Unique IPv6 address automatically assigned
- VM joins global Mycelium P2P network

### **Network Architecture**
```
🌐 Traditional Internet
    ↓
[ThreeFold Grid VM]
    ↙        ↘
Mycelium IPv6   Public IPv4
    ↓           ↓
P2P Overlay    Domain Access
```

## **Federation Enhancement**

### **Standard Matrix Federation (Always Available)**
```
Homeserver A ←HTTPS/WSS→ Homeserver B
(chat.projectmycelium.org)    (your-chat.com)
```

### **Enhanced Mycelium Federation (When Available)**
```
Homeserver A ←Mycelium P2P→ Homeserver B
    ↙              ↘
Mycelium Node   Mycelium Node
```

**Benefits:**
- **Direct P2P Routing**: Messages bypass traditional internet infrastructure
- **Enhanced Privacy**: Additional encryption layer
- **Censorship Resistance**: Routes around blocked connections
- **Better Performance**: Optimized P2P paths

## **User Experience Integration**

### **Progressive Enhancement Model**
```
User visits homeserver web app
        ↓
JavaScript detects Mycelium installation
        ↓
If Mycelium found → Enable P2P features
If not found → Standard Matrix federation
```

### **Feature Activation**
**Without Mycelium:**
- Standard Matrix chat
- HTTPS federation
- Web-based access

**With Mycelium:**
- All above features +
- Direct P2P messaging
- Enhanced encryption
- Offline mesh networking
- Network topology visualization

## **Bridge Service Architecture**

### **Matrix-Mycelium Bridge**
```
Matrix Federation Events
        ↓
[Matrix Bridge Service] (Rust)
        ↓
Mycelium P2P Transport
        ↓
Target Homeserver
```

**Bridge Components:**
- **Event Translation**: Matrix events → Mycelium messages
- **Peer Discovery**: Automatic homeserver discovery
- **Route Optimization**: Best path selection
- **Fallback Handling**: Standard federation when P2P fails

## **User Registration and Communication**

**1. User Registration**
- Users visit `https://your-chat.example.com`
- Create accounts: `@username:your-chat.example.com`
- Can authenticate with existing Matrix accounts

**2. Cross-Homeserver Communication**
- Users from `chat.projectmycelium.org` can join rooms on your server
- Your users can join rooms on other federated servers
- Direct messaging works across all servers

**3. Room Discovery**
- Public rooms are discoverable across the federation
- Users can search for and join rooms from any homeserver
- Room addresses: `#roomname:homeserver.domain`

## **Operational Management**

### **Daily Operations**
```bash
# Check status
make status

# SSH access
make connect

# View logs
make logs

# Update deployment
make app  # Re-deploy application
```

### **Network-Wide Benefits**
- **Global Mesh**: All homeservers connected via Mycelium
- **Automatic Discovery**: New homeservers join network seamlessly
- **Resilient Routing**: Multiple paths between servers
- **Zero Configuration**: Works out-of-the-box

## **Security & Privacy Layers**

```
User Data → Matrix E2EE → Mycelium Transport → Internet
     ↓           ↓              ↓              ↓
Encrypted   Encrypted      Encrypted      Potentially
Messages   Federation     P2P Overlay    Monitored
```

**Result:** Triple encryption for enhanced users

## **Scaling & Performance**

### **Traditional Scaling**
- More users → More load on homeserver
- Federation traffic through internet
- Dependent on DNS and routing

### **Mycelium-Enhanced Scaling**
- P2P distribution of traffic
- Automatic load balancing
- Geographic optimization
- Offline capability in local networks

## **Real-World Example**

```
User on chat.projectmycelium.org
Messages user on your-chat.example.com

Without Mycelium:
chat.projectmycelium.org → Internet → your-chat.example.com

With Mycelium:
chat.projectmycelium.org → Mycelium P2P → your-chat.example.com
```

## **Current Implementation Status**

### **✅ Completed (95%)**
- Mycelium infrastructure integration
- Matrix Bridge service (Rust)
- P2P federation routing
- Automatic peer discovery
- Standard Matrix federation

### **🔄 Remaining (5%)**
- Frontend Mycelium detection
- Progressive enhancement UI
- P2P message routing in web app

## **Key Benefits for Operators**

✅ **Full Control**: You own and operate your homeserver  
✅ **Federation**: Connect with the broader Matrix ecosystem  
✅ **Mycelium Enhancement**: Optional P2P features for advanced users  
✅ **Decentralized**: No vendor lock-in  
✅ **Scalable**: Handle growth through federation  
✅ **Secure**: Enterprise-grade security practices  
✅ **Cost-Effective**: Run on decentralized ThreeFold Grid  

## **Community and Network Growth**

### **Joining the Mycelium-Matrix Network**
1. Deploy your homeserver
2. Users automatically discover other servers through Matrix federation
3. Mycelium provides additional P2P capabilities
4. Network grows organically

### **Governance**
- Each homeserver operator is independent
- No central authority
- Community-driven development
- Open-source and transparent

This architecture enables anyone to run their own chat infrastructure while participating in a global, federated network with optional P2P enhancements - combining the best of centralized usability with decentralized resilience and privacy.