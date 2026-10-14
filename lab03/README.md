# Lab 03 — Compute & Images: Nova and Glance



---
## Objectives


- Manage images with **Glance**: import, formats, properties, visibility and sharing between projects;
- Define **flavors** tailored to a given need;
- Customize an instance at boot time with **cloud-init**;
- Drive the **lifecycle** of a Nova instance (stop, pause, suspend, shelve, resize) and explain the effect of each operation;
- Create an **instance snapshot** and redeploy from it;
- Observe on the hypervisor side (**libvirt / KVM**) what Nova actually created.

---

## Part 0 — Checking the OpenStack environment

If the EC2 instance was stopped since the last session, check that the OpenStack services are running again.

```bash
sudo systemctl list-units 'devstack@*' --no-pager
source ~/devstack/openrc admin admin      # adjust the path if needed
openstack compute service list
openstack hypervisor list
openstack network agent list
```

All services must be `up` / `enabled`. If one of them is `down`, find the matching unit in the `systemctl list-units` output (**UNIT** column), then restart it:

```bash
sudo systemctl restart <unit>        # e.g. sudo systemctl restart devstack@n-cpu.service
```

> **Warning:** the name shown by `openstack compute service list` (`nova-compute`) is not the systemd unit name (`devstack@n-cpu.service`). The table below lists the useful mappings.

| OpenStack service | systemd unit |
|---|---|
| nova-compute | `devstack@n-cpu.service` |
| nova-scheduler | `devstack@n-sch.service` |
| nova-conductor | `devstack@n-cond-cell1.service`, `devstack@n-super-cond.service` |
| nova-api | `devstack@n-api.service` |
| neutron-server | `devstack@q-svc.service` or `devstack@neutron-api.service` (depending on the version) |
| Keystone | `devstack@keystone.service` |
| Glance | `devstack@g-api.service` |

If the restart fails, check the logs: `sudo journalctl -u <unit> -n 50 --no-pager`

Then check the external bridge `br-ex`, which connects the host to the `public` network (172.24.4.0/24) used by floating IPs:

```bash
ip addr show br-ex
```

The bridge must be `UP` and carry the address `172.24.4.1/24`. DevStack configures this address during installation, but it **is not kept after a reboot** of the EC2 instance. If it is missing, restore it:

```bash
sudo ip addr add 172.24.4.1/24 dev br-ex
sudo ip link set br-ex up
```

> Without this step, floating IPs are unreachable from the host: `ping`, `ssh` and `curl` hang without any response.

> **Q1.** Which Nova services are listed by `openstack compute service list`? Explain the role of each one in one sentence (`nova-scheduler`, `nova-conductor`, `nova-compute`).

---

## Part 1 — Glance: managing images

### 1.1 Exploring the existing images

```bash
openstack image list
openstack image show <cirros-image-id>
```

> **Q2.** Write down the disk format (`disk_format`), the container format (`container_format`), the size, the visibility and the owner of the CirrOS image.

### 1.2 Importing an Ubuntu cloud image

```bash
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img
```
- Display the image details:
```bash
qemu-img info ubuntu-24.04-minimal-cloudimg-amd64.img
```

> **Q3.** What is the actual format of the file according to `qemu-img info`? Compare its size on disk (*disk size*) with its virtual size (*virtual size*). Why do these two values differ?

Create the image in Glance:

```bash
openstack image create ubuntu-24.04-minimal \
    --file ubuntu-24.04-minimal-cloudimg-amd64.img \
    --disk-format qcow2 \
    --container-format bare \
    --min-disk 4 \
    --min-ram 512 \
    --property os_distro=ubuntu \
    --property os_version=24.04 \
    --private
```

> **Q4.** What are `--min-disk` and `--min-ram` used for?

### 1.3 Visibility and sharing between projects

Glance offers four visibility levels: `private`, `shared`, `community`, `public`.

#### a) Create a test project and user

With the `admin` credentials:

```bash
source ~/devstack/openrc admin admin
openstack project create project-lab03
openstack user create student-lab03 --project project-lab03 --password Lab03Pass
openstack role add --project project-lab03 --user student-lab03 member
```

> **Important:** an administrator sees all images, whatever their visibility. To actually observe the effect of sharing, you must look at things from the point of view of a **non-administrator** user.

#### b) Check that the image is invisible to the new project

Open a **second terminal** on the EC2 instance and log in as `student-lab03`:

```bash
source ~/devstack/openrc student-lab03 project-lab03
export OS_PASSWORD=Lab03Pass
openstack image list
```

> **Note:** `openrc` loads the settings shared by the whole cloud (Keystone address, region, domain); its two arguments set the user and the project. The password must be set again, because `openrc` uses the administrator's password by default. Check your identity with `env | grep OS_ | grep -v PASSWORD`.
>
> Each terminal keeps its own environment variables: the first one stays logged in as `admin`, the second one as `student-lab03`. Compare the output of `openstack image list` in both terminals.
#### c) Share the image with the project

In the **first terminal** (admin):

```bash
openstack image set --shared ubuntu-24.04-minimal
openstack image add project ubuntu-24.04-minimal project-lab03
openstack image member list ubuntu-24.04-minimal
```

#### d) Accept the share

In the **second terminal** (`student-lab03`):

```bash
openstack image list
openstack image set --accept <ubuntu-image-id>
openstack image list
```

Check the member status again in the first terminal:

```bash
openstack image member list ubuntu-24.04-minimal
```

> **Q5.** Is the image visible to `student-lab03` **before** sharing? After sharing but **before** acceptance? After acceptance? What is the member status (`pending`, `accepted`, `rejected`) at each step?
>
> **Q6.** What is the difference between a `shared` image and a `community` image? Who can make an image `public`, and why is this operation restricted to that role?

---

## Part 2 — Flavors

```bash
openstack flavor list
```

Create two flavors (with the `admin` credentials):

```bash
openstack flavor create lab03.small  --vcpus 1 --ram 1024 --disk 5
openstack flavor create lab03.medium --vcpus 2 --ram 2048 --disk 8
```

Create a private flavor, restricted to the Lab 03 project (`project-lab03`):

```bash
openstack flavor create lab03.private --vcpus 1 --ram 512 --disk 4 --private
openstack flavor set lab03.private --project project-lab03
```

> **Q7.** Can the Ubuntu image be launched with the `m1.tiny` flavor? Test it, then explain the message you get in relation to `--min-disk` and `--min-ram`.
>
> **Q8.** Does the `lab03.private` flavor appear in `openstack flavor list` when you are logged in with another project? What is a private flavor used for in an enterprise cloud?

---

## Part 3 — Boot-time customization with cloud-init

All commands in this part are run on the EC2 instance, with the `admin` credentials (first terminal).

Go to your home directory: the key and the user-data file will be created there.

```bash
cd ~
```

### 3.1 Preparing the network and access to the instance

#### a) Private network, subnet and router

```bash
openstack network create net-lab03
openstack subnet create subnet-lab03 \
    --network net-lab03 \
    --subnet-range 192.168.30.0/24 \
    --dns-nameserver 8.8.8.8
openstack router create router-lab03
openstack router set router-lab03 --external-gateway public
openstack router add subnet router-lab03 subnet-lab03
```

#### b) Security group

Allow SSH, HTTP and ping:

```bash
openstack security group create sg-lab03 --description "SSH, HTTP and ICMP for Lab 03"
openstack security group rule create --protocol tcp --dst-port 22 sg-lab03
openstack security group rule create --protocol tcp --dst-port 80 sg-lab03
openstack security group rule create --protocol icmp sg-lab03
openstack security group rule list sg-lab03
```

#### c) Key pair

```bash
openstack keypair create key-lab03 > key-lab03.pem
chmod 600 key-lab03.pem
```

### 3.2 Writing the user-data file

The file must be created in the same directory as the key (your home directory), because the `openstack server create` command in section 3.3 refers to it:

```bash
cd ~
nano web-init.yaml
```

Paste the following content, then save and exit:

```yaml
#cloud-config
hostname: vm-web
write_files:
  - path: /var/www/index.html
    content: |
      <h1>Lab 03 - Instance configured with cloud-init</h1>
runcmd:
  - cd /var/www && nohup python3 -m http.server 80 > /var/log/web.log 2>&1 &
```

> **Mind the indentation:** YAML is whitespace-sensitive. Use spaces, never tabs.

Meaning of the directives:

| Directive       | Role                                                                                                         |
| --------------- | ------------------------------------------------------------------------------------------------------------ |
| `#cloud-config` | **Mandatory** first line: tells cloud-init that the file uses the cloud-config format (YAML)                 |
| `hostname`      | Hostname assigned to the VM                                                                                  |
| `write_files`   | Creates files in the VM (here, the website home page)                                                        |
| `runcmd`        | Commands run as `root` at the end of the first boot (here, starting a Python web server on port 80)          |

Check the file:

```bash
ls -l web-init.yaml
cat web-init.yaml
sudo cloud-init schema --config-file web-init.yaml
```

The last command validates the syntax of the file with the cloud-init tool installed on the EC2 instance. The expected result is `Valid schema web-init.yaml`.

> **Security:** the user-data content remains readable by any process in the VM for its entire lifetime. Never put a password, a private key or an access token in it.

### 3.3 Launching the instance

#### a) Create the instance

```bash
openstack server create vm-web \
    --image ubuntu-24.04-minimal \
    --flavor lab03.small \
    --network net-lab03 \
    --security-group sg-lab03 \
    --key-name key-lab03 \
    --user-data web-init.yaml \
    --wait
```

The `--wait` option returns once the instance is `ACTIVE`. At this point, it only has a **private** address (`192.168.30.x`).

#### b) Associate a floating IP

A floating IP is a Neutron resource, separate from the instance: it is first allocated from the `public` network, then associated with the VM. The address is stored in the `FIP` variable, reused throughout the rest of the lab:

```bash
FIP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip vm-web $FIP
echo $FIP
```

#### c) Follow the boot process

The first boot may take several minutes. Run the following command repeatedly until you see the line `Cloud-init v. ... finished`:

```bash
openstack console log show vm-web | grep -i cloud-init
```

#### d) Test the web service

If not already done (Part 0), bring up the external bridge `br-ex`, which connects the host to the floating IP network:

```bash
sudo ip addr add 172.24.4.1/24 dev br-ex
sudo ip link set br-ex up
```

Define the `web` and `relaunch_web` functions, which test and restart the web server:

```bash
web() {
  curl -sS -m 5 http://$FIP || echo "=> no response from the web server"
}

relaunch_web() {
  ssh -n -i ~/key-lab03.pem \
      -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      ubuntu@$FIP \
      "cd /var/www && sudo nohup python3 -m http.server 80 > /tmp/web.log 2>&1 < /dev/null &" \
    && echo "=> web server restarted"
}
```

Check connectivity and the service:

```bash
ping -c 3 $FIP
web
```

The expected result is the page `<h1> Lab 03 - Instance configured with cloud-init </h1>`.

**Troubleshooting:** if `web` does not respond, the `curl` error message tells you where to look:

| Error                                                | Meaning                                                   | Action                                                                        |
| ---------------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Immediate refusal (*Failed to connect … after 0 ms*) | The VM responds, but no service is listening on port 80  | Restart the server: `relaunch_web`, then `web`                                |
| Timeout (*timed out*) or no ping reply               | Network problem, or VM not booted yet                     | Check `br-ex` (Part 0), wait for the boot to finish (console), then try again |

## Part 4 — Instance lifecycle

For each operation below, write down the Nova **status**, the `vm_state`, the `power_state`, and the state seen by the hypervisor.

All commands are run on the EC2 instance, with the `admin` credentials, in the **same terminal as in Part 3** (the `FIP` variable and the `web` and `relaunch_web` functions are already defined there).

To simplify observations, define a small `state` function in your terminal:

```bash
state() {
  openstack server show vm-web -f shell \
    -c status -c flavor -c OS-EXT-STS:vm_state -c OS-EXT-STS:power_state -c OS-EXT-STS:task_state
  sudo virsh list --all
}
```

> **Important:** lifecycle commands return before the operation is complete. Wait until `state` shows `task_state = None` before running the next command, otherwise you will get a `409 Conflict` error.

> **New terminal?** The functions (`web`, `relaunch_web`, `state`) and the `FIP` variable only exist in the terminal where they were defined. Define them again before continuing:

After each **reverse** operation (`start`, `unpause`, `resume`, `unshelve`, `reboot`), test the web server with `web`. If it does not respond, note it for Q9, then restart it with `relaunch_web` before moving on to the next operation.

#### a) Stop and start

```bash
openstack server stop vm-web
state                                 # wait for: SHUTOFF, task_state None
openstack server start vm-web
state                                # wait for: ACTIVE
web
```

#### b) Pause

```bash
openstack server pause vm-web
state
openstack server unpause vm-web
state
web
```

#### c) Suspend

```bash
openstack server suspend vm-web
state
openstack server resume vm-web
state
web
```

#### d) Shelve

The `openstack server shelve` command puts an instance "on the shelf": the instance is stopped, then **removed from the compute node**, in order to free the resources (vCPUs, RAM, local disk) it was using there. Yet it still exists for OpenStack: it remains visible in `openstack server list` and keeps its identity (UUID, name, IP addresses, key pair). The reverse command, `openstack server unshelve`, brings it back onto a compute node and restarts it.

This is the right operation for an instance that will not be used for a long time but that you want to get back as it was later. Watch carefully what changes in Nova, in libvirt **and** in Glance.

```bash
openstack server shelve vm-web
state                                 # wait for: SHELVED_OFFLOADED
openstack image list                  # a new image has appeared
openstack server unshelve vm-web
state                                  # wait for: ACTIVE
openstack image list
web
```

#### e) Reboots

```bash
openstack server reboot --soft vm-web
state
openstack server reboot --hard vm-web
state
web
```

> **Q9.** Fill in the following table:

| Operation | Nova status | libvirt state | Where is the memory state? | CPU/RAM resources freed on the host? | Web server running after the reverse operation? |
|---|---|---|---|---|---|
| stop | | | | | |
| pause | | | | | |
| suspend | | | | | |
| shelve | | | | | |

> **Q10.** After `shelve`, a new image appears in Glance. Why? What happens during `unshelve`?
>
> **Q11.** What is the difference between `reboot --soft` and `reboot --hard`?

### 4.1 Resize

Resize the instance to the `lab03.medium` flavor, then **revert** the operation:

```bash
openstack server resize --flavor lab03.medium vm-web
state                                # wait for: VERIFY_RESIZE, task_state None
openstack server resize revert vm-web
state                                 # wait for: ACTIVE — which flavor?
```

Do it again, but this time **confirm**:

```bash
openstack server resize --flavor lab03.medium vm-web
state                                 # wait for: VERIFY_RESIZE, task_state None
openstack server resize confirm vm-web
state                                  # ACTIVE with lab03.medium
```

Finally, try to resize to a flavor with a **smaller** disk:

```bash
openstack server resize --flavor m1.tiny vm-web
openstack image show ubuntu-24.04-minimal -c min_disk
```

> **Q12.** What is the status of the instance right after the resize, before confirmation? What do `openstack server resize revert` and `openstack server resize confirm` do?
>
> **Q13.** What happens when resizing to `m1.tiny`, and why? Compare the minimum size given in the error message with the `min_disk` of the Ubuntu image: why do these two values differ?

### 4.2 Action history

```bash
openstack server event list vm-web
openstack server event show vm-web <request-id>      # pick the request-id of the resize
```

> **Q14.** What is the `request-id` used for? Why is this history useful in operations?

Before moving on to Part 5, make sure the web server responds:

```bash
relaunch_web
web
```

---

## Part 5 — Instance snapshots

Log in to the VM and add a line to the home page:

```bash
ssh -i ~/key-lab03.pem ubuntu@$FIP
```

Inside the VM:

```bash
echo "<p> Changed after boot </p>" | sudo tee -a /var/www/index.html
exit
```

Back on the EC2 instance, check the change, then take a snapshot:

```bash
web
openstack server image create vm-web --name snap-vm-web --wait
openstack image show snap-vm-web -c status -c size -c min_disk -c properties
```

Launch a new instance from the snapshot, **without user-data**, and associate a floating IP with it:

```bash
openstack server create vm-web-clone \
    --image snap-vm-web \
    --flavor lab03.medium \
    --network net-lab03 \
    --security-group sg-lab03 \
    --key-name key-lab03 \
    --wait

FIP_CLONE=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip vm-web-clone $FIP_CLONE
echo $FIP_CLONE
```

Wait for the boot to finish (`openstack console log show vm-web-clone | tail -5`), then test the clone:

```bash
ping -c 3 $FIP_CLONE
curl -sS -m 5 http://$FIP_CLONE
ssh -i ~/key-lab03.pem ubuntu@$FIP_CLONE "cat /var/www/index.html"
```

> **Q15.** Does the clone contain the manual change? Is the web server started automatically? Explain.



## Part 6 — Hypervisor side: what Nova created

So far, you have handled instances through `openstack` commands, that is, through OpenStack's logical view. In this part, you will observe what actually exists on the compute host: the virtual machine defined in **libvirt** and its disk files.

All commands are run on the EC2 instance, with the `admin` credentials.

### 6.1 The virtual machine in libvirt

Retrieve the UUID of the instance and its libvirt name:

```bash
ID=$(openstack server show vm-web -f value -c id)
INST=$(openstack server show vm-web -f value -c OS-EXT-SRV-ATTR:instance_name)
echo "UUID: $ID"
echo "libvirt name: $INST"
```

Display the characteristics of the VM, then the description of its disk in the XML configuration generated by Nova:

```bash
sudo virsh dominfo $INST
sudo virsh dumpxml $INST | grep -E "<vcpu|<memory"
sudo virsh dumpxml $INST | grep -A6 "<disk"
```

### 6.2 The instance disk

List the instance files and examine its disk:

```bash
sudo ls -lh /opt/stack/data/nova/instances/$ID/
sudo qemu-img info /opt/stack/data/nova/instances/$ID/disk
```

Find the `backing file` line, then examine the base image cache:

```bash
sudo ls -lh /opt/stack/data/nova/instances/_base/
```

### 6.3 Comparison with the clone

Make the same observation for `vm-web-clone`:

```bash
ID_CLONE=$(openstack server show vm-web-clone -f value -c id)
sudo qemu-img info /opt/stack/data/nova/instances/$ID_CLONE/disk
```

Compare the `backing file`, `virtual size` and `disk size` fields of the two instances.

> **Q16.** Find the number of vCPUs and the amount of memory in the libvirt XML. Do they match the current flavor of the instance?

---
## Cleanup

* Delete all the resources created during this lab.

> Order matters: a resource cannot be deleted while another one depends on it (a network attached to a router, a security group used by an instance…). In addition, deleting a project does not delete its resources: they would remain orphaned.

### a) Project resources (`student-lab03` terminal)

```bash
# Instances and snapshot
openstack server delete vm-web vm-web-clone --wait
openstack image delete snap-vm-web

# Floating IPs (deleting an instance does not release them)
openstack floating ip delete $(openstack floating ip list -f value -c ID)

# Router, then network (the subnet is deleted along with the network)
openstack router remove subnet router-lab03 subnet-lab03
openstack router unset --external-gateway router-lab03
openstack router delete router-lab03
openstack network delete net-lab03

# Security group and key pair
openstack security group delete sg-lab03
openstack keypair delete key-lab03
rm -f ~/key-lab03.pem
```

### b) Administration resources (`admin` terminal)

```bash
openstack image delete ubuntu-24.04-minimal
openstack flavor delete lab03.small lab03.medium lab03.private

# "default" security group created automatically in the project
openstack security group delete $(openstack security group list --project project-lab03 -f value -c ID)

openstack user delete student-lab03
openstack project delete project-lab03
```

### c) Verification (`admin` terminal)

```bash
openstack server list --all-projects
openstack floating ip list
openstack router list
openstack network list
openstack image list
openstack flavor list
```

Only the original DevStack resources should be listed (`public`, `private` and `shared` networks, `cirros` image, `m1.*` flavors…).

> The `ubuntu-24.04-minimal-cloudimg-amd64.img` file can be kept: it avoids downloading it again if needed.