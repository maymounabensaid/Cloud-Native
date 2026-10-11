 

# Lab 01 — Deploying and exploring an OpenStack infrastructure

## Lab objectives

- Install and configure an OpenStack infrastructure
- Create and manage a virtual machine with the Horizon web dashboard
- Create and manage an instance with the CLI
- Access a virtual machine deployed on OpenStack
- Understand the basics of resource management in an IaaS infrastructure

> [!TIP]
> Sections 1 and 2 are detailed step by step, with screenshots of the AWS console, in the **[illustrated install guide](install-guide.md)**.

---

## 1. Provisioning the EC2 instance

- **Name**: `DevStack`
- **AMI**: Ubuntu **26.04 LTS**
- **Instance type**: `r8i.large` (2 vCPU, 16 GB RAM)
- **Key pair**: create a new key pair named `devstack`
- **Security group**: create a new group `DevStack SG` with the following rules:
  - SSH (port 22) — from anywhere
  - HTTP (port 80) — from anywhere
- **Storage**: **50 GB**

> [!IMPORTANT]
> **Elastic IP address**: once the instance is running, allocate an Elastic IP address and associate it with the instance, to keep a stable IP from one session to the next.

### 1.1. Checking virtualization support

> [!NOTE]
> OpenStack does not virtualize by itself. Its compute service, Nova, delegates VM creation to the KVM hypervisor, and KVM relies on the CPU's hardware virtualization extensions (Intel VT-x).
>
> Our OpenStack host is already a virtual machine: the EC2 instance runs on AWS's hypervisor. For KVM to work inside it, AWS must expose these extensions to the instance. This is **nested virtualization**, disabled by default.

<img src="img/nestedvirt.png" width="75%">

Connect to your EC2 instance over SSH:

```bash
ssh -i devstack.pem ubuntu@<instance_IP>
```

Check that the CPU exposes the virtualization extensions:

```bash
lscpu | grep -i virtualization
```

Check that KVM is usable:

```bash
sudo apt update && sudo apt install -y cpu-checker
sudo kvm-ok
```

If you get:

```
INFO: Your CPU does not support KVM extensions
KVM acceleration can NOT be used
```

enable nested virtualization:

1. Stop the instance (**Stop**, not *Terminate*) and wait for the *stopped* state.
2. Select the EC2 instance: `Actions > Instance settings > Change CPU options > Nested virtualization > Enable`.
3. Start the instance again, reconnect, and run `sudo kvm-ok` again.

Expected result:

```
INFO: /dev/kvm exists
KVM acceleration can be used
```

---

## 2. Installing DevStack

1. Update the system, then reboot:

   ```bash
   sudo apt update
   sudo apt upgrade -y
   sudo reboot
   ```

   Wait a minute, then reconnect over SSH.

2. Install the basic tools:

   ```bash
   sudo apt install -y git curl net-tools
   ```

3. Download DevStack:

   ```bash
   git clone https://opendev.org/openstack/devstack
   ```

4. Create the `local.conf` file:

   ```bash
   cd devstack
   nano local.conf
   ```

   Copy and paste the following content:

   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=secret
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   ```

5. Run the installation:

   ```bash
   ./stack.sh
   ```

---

## 3. Checking the services

**Loading the OpenStack credentials:** before using the `openstack` command, you must load the required environment variables into the current shell.

```bash
cd ~/devstack
source openrc admin admin
```

| Element | Role |
| --- | --- |
| `source` | Runs the `openrc` script in the current shell, so that the variables it defines remain available to subsequent commands. |
| `openrc` | Script containing the authentication and connection information for Keystone, OpenStack's identity service. |
| 1st argument (`admin`) | OpenStack user name. |
| 2nd argument (`admin`) | Project (*tenant*) name. |

All operations go through a single command: `openstack <service> <action> ...`. The `openstack --help` command lists all available services and actions.

```bash
# Services and endpoints
openstack service list
openstack endpoint list

# Compute
openstack compute service list
openstack hypervisor list

# Networking
openstack network agent list
openstack network list
openstack subnet list

# Storage
openstack volume service list
openstack volume list

# Images
openstack image list

# Instances
openstack server list
openstack server list --all-projects
```

---

## 4. Creating a VM with the Horizon dashboard

### 4.1. Accessing the Horizon dashboard

- URL: `http://<instance_elastic_IP>`
- User: `admin`
- Password: `secret` (value set in `local.conf`)

### 4.2. Creating the network, routing and security resources

In this part, you will build the network architecture shown in the [summary diagram](#summary-diagram).

**Network and subnet**

`Project > Network > Networks > Create Network`:

- Network Name: `horizon-network`
- Subnet Name: `horizon-subnet`
- Network Address: `192.168.10.0/24`

**Router**

An isolated private network cannot reach the outside world without a router.

`Project > Network > Routers > Create Router`:

- Router Name: `horizon-router`
- External Network: `public`

Then add an interface linking this router to the private subnet: `horizon-router > Interfaces > Add Interface`, then select `horizon-subnet`.

**Security group**

`Project > Network > Security Groups > Create Security Group`:

- Name: `horizon-sg`
- Add Rule: SSH (22)

**SSH key pair**

`Project > Compute > Key Pairs > Create Key Pair`:

- Key Pair Name: `horizon-keypair`
- Key Type: SSH Key

The browser downloads the `.pem` file automatically.

### 4.3. Creating the VM

`Project > Compute > Instances > Launch Instance`:

- Instance Name: `horizon-vm`
- Source: Image → `cirros`, with `Create New Volume` = **No**
- Flavor: `m1.tiny`
- Networks: `horizon-network`
- Security Groups: `horizon-sg`
- Key Pair: `horizon-keypair`

### 4.4. Assigning a floating IP

Once the VM is active, it can only be reached from the private network `horizon-network`. To access it from the EC2 host, you must assign it a floating IP from the external network `public` (usually in the `172.24.4.0/24` range).

1. `Project > Network > Floating IPs > Allocate IP to Project` — Pool: `public`.
2. In `Project > Compute > Instances`, on the `horizon-vm` row, open the actions menu → **Associate Floating IP** → select the allocated IP → confirm.

---

## 5. Connecting to the VM over SSH from the EC2 host

**Copying the OpenStack key to the EC2 instance**

From a Windows terminal (PowerShell), copy the key downloaded in step 4.2 to the EC2 instance:

```powershell
scp -i "C:\path\to\devstack.pem" "C:\path\to\horizon-keypair.pem" ubuntu@<instance_elastic_IP>:~/
```

Then, on the EC2 instance, restrict its permissions:

```bash
chmod 400 ~/horizon-keypair.pem
```

**Connecting to the OpenStack VM**

```bash
ssh -i ~/horizon-keypair.pem cirros@<VM_floating_IP>
```

The default user of the CirrOS image is `cirros`.

### Summary diagram

<img src="img/openstack-network.png" width="75%">

### Network components summary

| Component | Example in this lab | Role |
|---|---|---|
| **External network** | `public` (`172.24.4.0/24`) | Network connecting OpenStack to the outside world. Floating IPs come from it. |
| **br-ex** | bridge on the EC2 host | Virtual switch connecting the external network to the host. In DevStack, it is not attached to any physical NIC: the `public` network can only be reached from the host. |
| **Private network** | `horizon-network` | Isolated virtual network, specific to the project, to which VMs are attached. |
| **Subnet** | `horizon-subnet` (`192.168.10.0/24`) | IP address range of the private network. It automatically assigns (DHCP) a fixed IP to each VM. |
| **Router** | `horizon-router` | Connects the private network to the external network. It lets VMs reach the outside and translates floating IPs into private IPs (NAT). |
| **External gateway** | `172.24.4.x` | Router interface on the external network side. |
| **Router interface** | `192.168.10.1` | Router interface on the private network side. It is the VMs' default gateway. |
| **Fixed IP** | `192.168.10.x` | Private address of the VM, visible on its network interface. It can only be reached from the private network. |
| **Floating IP** | `172.24.4.y` | Address from the external network, associated with a VM. The router translates it into the fixed IP (1:1 NAT). It can be detached and reassigned to another VM. |
| **Security group** | `horizon-sg` | Firewall applied to the VM. All inbound traffic is blocked, except what its rules allow (here: SSH, port 22). |
| **Key pair** | `horizon-keypair` | The public key is injected into the VM at boot. The private key (`.pem`) is used to connect over SSH without a password. |

> [!TIP]
> **Key takeaway:** for a VM to be reachable over SSH, you need **all five elements**: a private network with its subnet, a **router** connected to the `public` network, a **floating IP** associated with the VM, a **security group** allowing port 22, and a **key pair**.

---

## 6. Creating a VM with the OpenStack CLI

Load the OpenStack credentials:

```bash
cd ~/devstack
source openrc admin admin
```

**Private network and subnet**

Create the `cli-network` network and the `cli-subnet` subnet:

```bash
openstack network create cli-network

openstack subnet create cli-subnet \
  --network cli-network \
  --subnet-range 192.168.20.0/24
```

**Router**

Create a router, give it an external gateway on the `public` network, then connect it to the `cli-subnet` subnet:

```bash
openstack router create cli-router
openstack router set cli-router --external-gateway public
openstack router add subnet cli-router cli-subnet
```

**Security group**

Create a security group with an inbound SSH rule:

```bash
openstack security group create cli-sg
openstack security group rule create --protocol tcp --dst-port 22 cli-sg
```

**SSH key pair**

Create the `cli-keypair` key pair and save the private key:

```bash
openstack keypair create cli-keypair > cli-keypair.pem
chmod 400 cli-keypair.pem
```

**Launching the VM**

First, get the exact name of the CirrOS image, which depends on the version installed by DevStack:

```bash
openstack image list
```

Then launch the VM, adjusting the image name if needed:

```bash
openstack server create cli-vm \
  --image "cirros-0.6.3-x86_64-disk" \
  --flavor m1.tiny \
  --network cli-network \
  --security-group cli-sg \
  --key-name cli-keypair
```

Check the instance status (wait for `ACTIVE`):

```bash
openstack server list
openstack server show cli-vm
```

**Allocating and associating a floating IP**

Allocate a floating IP on the `public` network:

```bash
openstack floating ip create public
```

Get the allocated address and associate it with the VM:

```bash
openstack floating ip list
openstack server add floating ip cli-vm <floating_IP>
```

**Connecting to the OpenStack VM**

```bash
ssh -i cli-keypair.pem cirros@<VM_floating_IP>
```
