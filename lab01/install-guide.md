 

# Lab 01 — Illustrated install guide

This guide walks through preparing the EC2 instance and installing DevStack, with screenshots of the AWS console. It accompanies sections 1 and 2 of the **[Lab 01 instructions](README.md)**.

---

## 1. Provisioning the EC2 instance

**Name**: `DevStack` — **AMI**: Ubuntu **26.04 LTS**

<img src="img/vm1.png" width="85%">

**Instance type**: `r8i.large` (2 vCPU, 16 GB RAM)

<img src="img/vm2.png" width="85%">

**Key pair**: create a new key pair named `devstack`

<img src="img/vm3.png" width="85%">

<img src="img/vm4.png" width="85%">

**Security group**: create a new group `DevStack SG` with the following rules:

- SSH (port 22) — from anywhere
- HTTP (port 80) — from anywhere

<img src="img/vm5.png" width="85%">

<img src="img/vm6.png" width="85%">

<img src="img/vm7.png" width="85%">

<img src="img/vm8.png" width="85%">

**Storage**: **50 GB**

<img src="img/vm30.png" width="85%">

---

## 2. Associating an Elastic IP address

<img src="img/vm10.png" width="85%">

<img src="img/vm11.png" width="85%">

<img src="img/vm12.png" width="85%">

<img src="img/vm13.png" width="85%">

<img src="img/vm14.png" width="85%">

---

## 3. Enabling nested virtualization

> [!IMPORTANT]
> The instance must be **stopped** (*Stop*, not *Terminate*) to change its CPU options.

<img src="img/vm16.png" width="85%">

<img src="img/vm17.png" width="85%">

<img src="img/vm18.png" width="85%">

<img src="img/vm19.png" width="85%">

<img src="img/vm20.png" width="85%">

---

## 4. Connecting over SSH

<img src="img/vm21.png" width="85%">

<img src="img/vm22.png" width="85%">

<img src="img/vm23.png" width="85%">

---

## 5. Installing DevStack

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

   <img src="img/vm24.png" width="85%">

5. Run the installation:

   ```bash
   ./stack.sh
   ```

   <img src="img/vm25.png" width="85%">

---

## 6. Checking the services (CLI)

Load the OpenStack credentials into the current shell, then list the services:

```bash
cd ~/devstack
source openrc admin admin
openstack service list
```

<img src="img/vm26.png" width="85%">

<img src="img/vm27.png" width="85%">

---

## 7. Accessing the Horizon dashboard

- URL: `http://<instance_elastic_IP>`
- User: `admin`
- Password: `secret` (value set in `local.conf`)

<img src="img/vm28.png" width="85%">

<img src="img/vm29.png" width="85%">

---

The installation is complete. Return to the **[Lab 01 instructions](README.md)** at section 3.
