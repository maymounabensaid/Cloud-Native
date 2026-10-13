
# Lab 02 — Keystone: identity, projects and access control

## Lab objectives

This lab focuses on Keystone, OpenStack's identity service. You will discover how a client authenticates and finds the cloud's services, then how Keystone, together with the other services, isolates projects and controls what each user is allowed to do.

By the end of this lab, you will be able to:

**Part 1 — From the CLI to the REST APIs**

1. Load an identity with `openrc` and explain the role of the `OS_*` variables.
2. Explain what a token, the service catalog and an endpoint are, and how they fit together.
3. Read the CLI output in `--debug` mode to reconstruct the HTTP exchange between the client and the services (version discovery, authentication, business call).
4. Query an OpenStack API directly with `curl` and a token, and explain the effect of revoking it.

**Part 2 — Projects, users and roles**

5. Describe how Keystone is organized: domains, projects, users, groups and roles.
6. Create projects and users, and assign roles to them.
7. Manage several identities with the `clouds.yaml` file.

**Part 3 — Isolation and access control**

8. Verify isolation between projects (multi-tenancy): a user cannot see another project's resources.
9. Observe role-based access control (RBAC): distinguish the rights of the `admin`, `member` and `reader` roles, and interpret refusals (403) and resources not found (404).
10. Read a service's access policy to explain why an operation is allowed or denied.

---

## Part 1 — From the CLI to OpenStack's REST APIs

The `openstack` CLI is just an HTTP client: it requests a token from Keystone, reads the catalog to find the service's URL, then calls its REST API.

### 1.1. Loading your identity: `source openrc`

Before any command, the CLI needs to know who you are and where Keystone is. DevStack provides the `openrc` script for this:

```bash
cd ~/devstack
source openrc admin admin        # syntax: source openrc <user> <project>
env | grep ^OS_                  # shows the loaded variables
```

| Element | Role |
| --- | --- |
| `source` | Runs the script **in the current shell**: the variables it defines remain available to subsequent commands. Run without `source` (`./openrc`), the script would execute in a subshell and the variables would disappear when it ends. |
| `openrc` | DevStack script that defines the `OS_*` environment variables. |
| 1st argument (`admin`) | **User** name. |
| 2nd argument (`admin`) | Name of the **project** the token will be bound to (*scope*). |

**Main variables loaded:**

| Variable | Content | Used for |
| --- | --- | --- |
| `OS_AUTH_URL` | `http://<IP>/identity` | The **only address** the CLI knows at the start: Keystone's |
| `OS_USERNAME` / `OS_PASSWORD` | User credentials | The body of the authentication request |
| `OS_PROJECT_NAME` | Target project | The token's *scope* |
| `OS_USER_DOMAIN_NAME`, `OS_PROJECT_DOMAIN_NAME` | Domain (`Default`) | Unambiguously identifying the user and the project |
| `OS_REGION_NAME` | `RegionOne` | Selecting the endpoints of the right region in the catalog |

> [!TIP]
> **Key takeaway:** these variables do not contain a token, but credentials. The CLI sends them to Keystone with every command to get a new token. They only exist in the shell where they were loaded: you must run `source openrc` again in every new terminal or SSH session.

### 1.2. Token, catalog and endpoints

#### 1.2.1. Token

Run the command below:

```bash
openstack token issue
```

| Command | What it does | Service queried | What it displays | Key takeaway |
| --- | --- | --- | --- | --- |
| `openstack token issue` | Requests a **new token** from Keystone using the loaded credentials (`openrc` or `clouds.yaml`) and displays it in clear text. | Keystone | `expires`: expiration date and time; `id`: the token itself; `project_id`: project the token is bound to (*scope*); `user_id`: authenticated user. | The token is a **temporary proof of identity**: by default, Keystone makes it valid for 1 hour. It is bound to **a single project**: switching projects requires a new token. |

**Q1.** How long is the token valid? Which project is it bound to (*scope*)?

> [!NOTE]
> The `source openrc` command does not load a token; it loads credentials (user name, password, project, Keystone URL) into `OS_*` environment variables.
> These variables do not expire: the CLI uses them to request a new token for every command. The one-hour expiration therefore never gets in its way.

**Why this command?**

- Every `openstack` command (e.g. `openstack server list`) automatically requests a **new token** from Keystone, uses it, then discards it, without showing it to you.
- `openstack token issue` performs only the first step: it **requests a token and displays it**. It is useful to:
  - check authentication: if it fails, the problem lies with Keystone or your `OS_*` variables (check with `env | grep ^OS`), not with the other services;
  - inspect a token's content: user (`user_id`), project (`project_id`) and expiration date (`expires`, 1 h by default);
  - reuse the token to call the REST APIs directly (see section 1.3).

> [!TIP]
> **Key takeaway:** every request to an OpenStack service first goes through Keystone to obtain a token. The token is then sent in the `X-Auth-Token` HTTP header.

#### 1.2.2. Catalog

Run the command below:

```bash
openstack catalog list
```

| Command | What it does | Service queried | What it displays | Key takeaway |
| --- | --- | --- | --- | --- |
| `openstack catalog list` | Displays the **service catalog** that Keystone returns with every token. | Keystone (the catalog is part of the authentication response) | `Name`: service name (`nova`, `glance`…); `Type`: standardized type (`compute`, `image`…); `Endpoints`: for each region and interface, the service's URL. | It is the cloud's **directory**: the CLI, Horizon or Terraform look up a service's URL by its **type**. It depends on the token: a user only sees the services their project has access to. |

#### 1.2.3. Endpoints

Run the command below:

```bash
openstack endpoint list --interface public
```

| Command | What it does | Service queried | What it displays | Key takeaway |
| --- | --- | --- | --- | --- |
| `openstack endpoint list --interface public` | Lists the **endpoints** registered in Keystone, filtered on the `public` interface. | Keystone | `ID`, `Region`, `Service Name`, `Service Type`, `Enabled`, `Interface`, `URL`: one line per endpoint. | Same information as the catalog, but seen **from the administration side**: one line per endpoint, with its ID, so it can be modified or deleted. The `public` interface is for users; `internal` is for service-to-service traffic; `admin` is for administrative operations. This command generally requires the `admin` role. |

**Q2.** Compare the outputs of `openstack catalog list` and `openstack endpoint list --interface public`:

> a) Are the URLs the same in both outputs? Look at the `nova_legacy` service: what difference do you notice between the two commands, and how do you explain it?

> b) All services use the same IP address. How does the server know which service to forward a request to?

> c) Run `openstack endpoint list` again **without** the `--interface public` option. Does the result change? Which interfaces has DevStack declared? Why would a production cloud also declare an `internal` interface?
>
> *In Keystone, a single service can be registered with several addresses, one per interface, that is, depending on who calls it and from which network.*

> d) Switch identity by loading the `demo` user of the `demo` project, then run the three commands again:

```bash
source ~/devstack/openrc demo demo
openstack token issue
openstack catalog list
openstack endpoint list --interface public
```

> Compare with the results obtained as admin: what changes in the token? In the `nova_legacy` URL? What happens with `endpoint list`, and why?
>
> Then switch back to the admin identity: `source ~/devstack/openrc admin admin`.

### 1.3. Querying the API without the CLI

The CLI is just an HTTP client. You will perform its two steps yourself: get a token, then call a service.

> [!IMPORTANT]
> Make sure you are using the admin identity: `source ~/devstack/openrc admin admin`

#### 1.3.1. Token and Nova URL (retrieved once with the CLI)

```bash
export TOKEN=$(openstack token issue -f value -c id)
export NOVA=$(openstack endpoint list --service compute --interface public -f value -c URL)
```

| Element | Role |
| --- | --- |
| `export TOKEN=…` | Creates the `TOKEN` environment variable, reusable afterwards as `$TOKEN`. |
| `$( … )` | Runs the command in parentheses and replaces the expression with its output. |
| `openstack token issue` | Requests a new token from Keystone. |
| `-f value` | *Format*: displays raw values, without a table or borders. Other formats: `table` (default), `json`, `yaml`, `shell`. |
| `-c id` | *Column*: keeps only the `id` column, which contains the token. |
| `openstack endpoint list --service compute --interface public` | Looks up in Keystone the public URL of the `compute` service (Nova), stored in `NOVA`. |

#### 1.3.2. Calling the Nova API directly

```bash
curl -s  -H "X-Auth-Token: $TOKEN" $NOVA/servers
curl -si $NOVA/servers | head -1
```

| Element | Command 1: with token | Command 2: without token |
| --- | --- | --- |
| `curl` | Sends an HTTP `GET` request to the given URL. | Same. |
| `-s` | *Silent*: hides the progress bar. | Same. |
| `-i` | — | *Include*: also displays the response headers, including the HTTP status line. |
| `-H "X-Auth-Token: $TOKEN"` | Adds the header carrying the token: the proof of identity. | **Absent**: no proof of identity is sent. |
| `$NOVA/servers` | The "list of instances" resource of the Nova API. | Same. |
| `\| head -1` | — | Keeps only the first line of the response: the HTTP code. |
| **Result** | `{"servers": []}`: Nova accepts the request and returns the list. | `HTTP/1.1 401 Unauthorized`: Nova refuses, for lack of a token. |

> [!NOTE]
> A single CLI command, `openstack server list`, automatically chains several HTTP requests: version negotiation, authentication with Keystone, service lookup in the catalog, then the call to Nova. It then formats the response. With `curl`, each of these steps must be done by hand.
>
> **The CLI is an abstraction over the REST APIs.**

#### 1.3.3. Revoking a token

```bash
export TOKEN2=$(openstack token issue -f value -c id)
openstack token revoke $TOKEN2
curl -s -H "X-Auth-Token: $TOKEN2" $NOVA/servers
curl -s -H "X-Auth-Token: $TOKEN"  $NOVA/servers
openstack server list
```

| Element | Role |
| --- | --- |
| `export TOKEN2=…` | Gets a **second token**, independent of the first. |
| `openstack token revoke $TOKEN2` | Asks Keystone to invalidate this token. Prints nothing on success. |
| `curl … $TOKEN2 …` | Calls Nova with the revoked token → `HTTP/1.1 401 Unauthorized`: Nova has Keystone validate the token, and Keystone reports it as revoked. |
| `curl … $TOKEN …` | Same call with the first token → `HTTP/1.1 200 OK`: only the revoked token is refused. |
| `openstack server list` | Works normally: the CLI uses neither `$TOKEN` nor `$TOKEN2`; it gets a new token with the `openrc` credentials. |

> [!TIP]
> **Key takeaways:**
> - The token is the mandatory proof of identity for every business request. It is issued by Keystone, presented in the `X-Auth-Token` header, and checked with Keystone by the service being called. Without a valid token, no service executes a request, not even a simple read.
> - A token has a limited lifetime (expiration) and can be invalidated at any time (revocation). It does not contain the password: access can be cut off without changing the user's credentials.
> - Revoking a token only affects that token: the user's other tokens remain valid.

---

## Part 2 — Projects, users and roles

You will create two teams and three users.

| User | Project | Role | Purpose in this lab |
| --- | --- | --- | --- |
| candace | team-a | member | Operates team A's resources |
| baron | team-b | member | Operates team B's resources |
| ian | team-a | reader | Views team A without modifying anything |

### 2.1. Exploring what exists

```bash
openstack domain list
openstack project list
openstack user list
openstack role list
openstack role assignment list --names
```

**Q4.** Which projects and users did DevStack create? Which roles exist? What does the `Inherited` column mean?

### 2.2. Creating projects, users and assignments

**Step 1: create the projects**

```bash
openstack project create --domain Default --description "Team A" team-a
openstack project create --domain Default --description "Team B" team-b
```

**Step 2: create the users, without any role**

```bash
openstack user create --domain Default --project team-a --password 'Candace#2026' candace
openstack user create --domain Default --project team-b --password 'Baron#2026'   baron
openstack user create --domain Default --project team-a --password 'Ian#2026'     ian
```

**Step 3: try to authenticate as candace**

```bash
openstack --os-username candace --os-password 'Candace#2026' --os-project-name team-a token issue
```

> [!TIP]
> **Key takeaway:** a user who exists, with a correct password and a default project, cannot obtain a token as long as they have no role on that project: Keystone returns 401.
> - The default project (`--project` at creation) is only a preference, not an authorization.
> - It is the assignment of a role on a project (`openstack role add`) that grants the right to work in it.
> - Identity ≠ authorization: existing in Keystone grants access to nothing.

**Step 4: assign the roles**

```bash
openstack role add --project team-a --user candace member
openstack role add --project team-b --user baron   member
openstack role add --project team-a --user ian     reader
```

**Step 5: try to authenticate as candace (2nd attempt)**

```bash
openstack --os-username candace --os-password 'Candace#2026' --os-project-name team-a token issue
```

**Q5.** Does the `--project` option of `user create` give the user a role?

> [!NOTE]
> For a user to work in a project, an explicit **role assignment** (`role add`) is required: the user · role · project triple. Without it, Keystone even refuses to issue a token bound to that project, since the user has no role in it.

### 2.3. One profile per identity with `clouds.yaml`

- With `source openrc`, only one identity can be loaded at a time, and the script must be reloaded to switch.
- The `clouds.yaml` file solves this problem: it is a **connection address book**, where each **profile** groups everything needed to connect under one identity. You then select a profile by its name.
- This file is the standard format for OpenStack clients (CLI, Python SDK, Ansible, Terraform).

> [!IMPORTANT]
> **Prerequisite:** the users candace, baron and ian must have been created in 2.2, with the passwords below and a role on their project.

Create the `clouds.yaml` file in `~/.config/openstack`:

```bash
mkdir -p ~/.config/openstack
nano ~/.config/openstack/clouds.yaml
```

Copy and paste the content below. Replace `<ADMIN_PASSWORD>` with the admin user's password, declared in the `local.conf` file. Save with **Ctrl + O** then **Enter**, and exit with **Ctrl + X**.

```yaml
clouds:
  admin:
    auth:
      auth_url: http://localhost/identity
      username: admin
      password: '<ADMIN_PASSWORD>'
      project_name: admin
      user_domain_name: Default
      project_domain_name: Default
    identity_api_version: 3
  candace:
    auth:
      auth_url: http://localhost/identity
      username: candace
      password: 'Candace#2026'
      project_name: team-a
      user_domain_name: Default
      project_domain_name: Default
    identity_api_version: 3
  baron:
    auth:
      auth_url: http://localhost/identity
      username: baron
      password: 'Baron#2026'
      project_name: team-b
      user_domain_name: Default
      project_domain_name: Default
    identity_api_version: 3
  ian:
    auth:
      auth_url: http://localhost/identity
      username: ian
      password: 'Ian#2026'
      project_name: team-a
      user_domain_name: Default
      project_domain_name: Default
    identity_api_version: 3
```

> [!WARNING]
> Keep the quotes around the passwords. In YAML, `#` starts a comment: without quotes, `Candace#2026` would be read as `Candace`.

Restrict the file's permissions so that only its owner can read and modify it, since it contains passwords in clear text:

```bash
chmod 600 ~/.config/openstack/clouds.yaml
```

Clear the `OS_*` variables loaded by `openrc` (in the current shell, or open a second SSH session to your instance): otherwise, they take precedence over `clouds.yaml`.

```bash
unset $(env | grep '^OS_' | cut -d= -f1)
```

Test loading each profile:

```bash
openstack --os-cloud admin   token issue
openstack --os-cloud candace token issue
openstack --os-cloud baron   token issue
openstack --os-cloud ian     token issue
```

**Q6.** For each token, note the project and the user ID. Which profiles share the same project? What does this mean?

From now on, select the identity for the whole shell with `export OS_CLOUD=<profile>`: subsequent commands then run under this profile, without any option. There is no need to request a token beforehand: each command authenticates on its own.

> [!NOTE]
> **`openrc` or `clouds.yaml`?**
>
> | | `source ~/devstack/openrc <user> <project>` | `clouds.yaml` + `OS_CLOUD` / `--os-cloud` |
> |---|---|---|
> | Principle | Loads `OS_*` variables into the shell | Selects a named profile from a file |
> | Password | Always the **DevStack admin's** (`OS_PASSWORD`) | The one defined in the profile |
> | Switching identity | Run `source` again (and `export OS_PASSWORD=…` for a manually created user) | `export OS_CLOUD=<profile>`, or `--os-cloud <profile>` for a single command |

> [!WARNING]
> **Never mix the two.** The `OS_*` variables from `openrc` **take precedence** over `clouds.yaml`: if they are still loaded, you may act under a different identity than the one you chose. Before using `OS_CLOUD`, clear them:
>
> ```bash
> unset $(env | grep ^OS_ | cut -d= -f1)
> export OS_CLOUD=candace
> env | grep ^OS          # only OS_CLOUD should appear
> ```

### 2.4. Groups

Create an `ops` group, add candace to it, then give the group the `reader` role on team-b.

```bash
export OS_CLOUD=admin
openstack group create ops
openstack group add user ops candace
openstack role add --group ops --project team-b reader
```

List all of candace's roles:

```bash
openstack role assignment list --names --user candace
```

List all of candace's **effective** roles: those assigned to her directly and those she gets through group membership:

```bash
openstack role assignment list --names --effective --user candace
```

**Q7.** Why does the `--effective` option change the result? What is the benefit of groups when 40 students join a project?

Then remove the group's role, so as not to skew Part 3, and check:

```bash
openstack --os-cloud admin role remove --group ops --project team-b reader
openstack --os-cloud admin role assignment list --names --effective --user candace
```

Only the `member` role on team-a should appear.

---

## Part 3 — Isolation and access control

Each project is an isolated **tenant**: its networks, VMs and security groups belong to the project, not to the users.

> [!NOTE]
> **The RBAC model.** OpenStack applies role-based access control (*Role-Based Access Control*, RBAC): rights are not assigned directly to a user; instead, a **role** is assigned on a **project**. Two checks are chained on every request:
> 1. **The project** of the token determines what the user **sees**: without a role on a project, its resources are invisible (404). Only explicitly shared resources, such as the `public` network, are visible to everyone.
> 2. **The role** determines what they can **do**: a `reader` reads, a `member` creates and modifies, an `admin` administers. An action not allowed by the role is refused (403).

For each test, note the command, the expected result, the actual result and, in case of error, the HTTP code.

The identity to use is given at the start of each block (**[admin]**, **[candace]**, **[baron]**, **[ian]**). Select it with `export OS_CLOUD=<profile>`, or add `--os-cloud <profile>` to the command.

### 3.1. Candace deploys team A's infrastructure

**[candace]**

```bash
export OS_CLOUD=candace
openstack network create net-candace
openstack subnet create --network net-candace --subnet-range 10.10.1.0/24 --dns-nameserver 8.8.8.8 subnet-candace
openstack router create --external-gateway public router-candace
openstack router add subnet router-candace subnet-candace

IMG=$(openstack image list -f value -c Name | grep -i cirros | head -1)
openstack server create --flavor m1.tiny --image "$IMG" --network net-candace --wait vm-candace
openstack server list
```

### 3.2. Baron tries to access team A's resources

First, note the IDs of `vm-candace` and `net-candace` (displayed by candace), and substitute them in the following commands.

**[baron]**

```bash
export OS_CLOUD=baron
openstack server list
openstack network list
openstack server show <ID_vm-candace>
openstack server delete <ID_vm-candace>
openstack network show <ID_net-candace>
openstack server create --flavor m1.tiny --image "$IMG" --network <ID_net-candace> vm-intrus
```

**Q8.** Does Baron get "access denied" (403) or "not found" (404)? Why is it preferable, from a security standpoint, to respond with 404?

**Q9.** Which network does Baron see even though he did not create it? Which property of this network explains it (`openstack network show public`)?

> [!NOTE]
> **How to read it: who can see a network?**
> In the output of `openstack network show`, three fields determine which projects see a network:
>
> | Field | Meaning |
> |---|---|
> | `project_id` | **Owner** project of the network: its members always see it |
> | `shared` | If `True`: **all projects** can see the network and attach their VMs to it directly |
> | `router:external` | If `External` (or `True`): **external** network, leading outside the cloud. **All projects** see it, to connect their routers and get floating IPs from it, but VMs are not attached to it directly |
>
> To find a project's name from its ID: `openstack project list`
>
> Reminder: here, `public` is the network's **name**, not a property.

### 3.3. Ian, team A's reader

**[ian]**

```bash
export OS_CLOUD=ian
openstack server list
openstack server show vm-candace
openstack server stop vm-candace
openstack server create --flavor m1.tiny --image "$IMG" --network net-candace vm-ian
openstack network create net-ian
```

**Q10.** Which actions succeed for ian, and which fail? Note the error message you get. Compare with the code Baron got in Q8: why does ian get a refusal (403) rather than "not found" (404)?

### 3.4. What a member cannot do

**[candace]**

```bash
export OS_CLOUD=candace
openstack user list
openstack project create team-c
openstack flavor create --vcpus 8 --ram 16384 --disk 100 m1.geant
openstack quota set --instances 100 team-a
```

**Q11.** Fill in the table below from your tests. For a cell not yet tested, run the given command with the corresponding identity.

**Preparation**: get the CirrOS image name and the IDs of `vm-candace` and `net-candace`. The commands in the table use **IDs**: a resource belonging to another project cannot be found by its name.

```bash
IMG=$(openstack --os-cloud admin image list -f value -c Name | grep -i cirros | head -1)
VM_ID=$(openstack --os-cloud candace server show vm-candace -f value -c id)
NET_ID=$(openstack --os-cloud candace network show net-candace -f value -c id)
echo "$IMG | $VM_ID | $NET_ID"
```

In the last two columns, enter **Yes** if the result varies with the user's **project** (a 404 appears), or with their **role** (a 403 appears). An action can depend on both.

`<profile>` stands for the identity being tested: admin, candace, baron or ian.

| # | Action | Command | admin | candace | baron | ian | Depends on project? | Depends on role? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | View `vm-candace` | `openstack server show $VM_ID` | | | | | | |
| 2 | Create a VM in one's own project | `openstack server create --flavor m1.tiny --image "$IMG" --network shared --wait vm-test-<profile>` | | | | | | |
| 3 | Stop `vm-candace` | `openstack server stop $VM_ID` | | | | | | |
| 4 | Create a network in one's own project | `openstack network create net-test-<profile>` | | | | | | |
| 5 | View the `net-candace` network | `openstack network show $NET_ID` | | | | | | |
| 6 | List users | `openstack user list` | | | | | | |
| 7 | Create a flavor | `openstack flavor create --vcpus 1 --ram 256 --disk 1 test-flavor` | | | | | | |

> [!NOTE]
> **Row 2**: the `shared` network, created by DevStack, is visible to all projects. It lets you test VM creation with each identity, without a dedicated network per project.
>
> **Row 3**: all four profiles act on the same VM. After each successful stop, start it again before testing the next profile. Otherwise, a profile that is allowed to stop it will get a **409 Conflict** error (VM already stopped), unrelated to its rights:
>
> ```bash
> openstack --os-cloud candace server start $VM_ID
> ```

**Q12.** Based on the table, explain why baron gets 404s and ian gets 403s.

### 3.5. The admin case: seeing all projects

Admin has the `admin` role, which allows them to administer the whole cloud. Does that mean they see the resources of all projects?

Run these two commands and compare:

```bash
openstack --os-cloud admin server list
openstack --os-cloud admin server list --all-projects
```

Then display the project the admin token is bound to:

```bash
openstack --os-cloud admin token issue -c project_id
openstack --os-cloud admin project list
```

**Q13.** Does `vm-candace` appear in both lists? Which project is the admin token bound to? Explain why admin does not see `vm-candace` without `--all-projects`, even though they have the `admin` role.

### 3.6. Cleaning up resources

Each identity deletes the resources it created. For team A's infrastructure, follow the reverse order of creation: first the VM, then the router, then the network.

```bash
# Use Candace's identity
export OS_CLOUD=candace

# Delete Candace's VM and wait for the deletion to finish, to free its port on net-candace
openstack server delete --wait vm-candace

# Detach the subnet from the router, which deletes the router's interface (port 10.10.1.1 on subnet-candace)
openstack router remove subnet router-candace subnet-candace

# Remove the router's external gateway, which deletes its port on the public network
openstack router unset --external-gateway router-candace

# Delete the router, now without any interface or gateway
openstack router delete router-candace

# Delete the subnet-candace subnet
openstack subnet delete subnet-candace

# Delete Candace's network (its DHCP port is deleted automatically)
openstack network delete net-candace

# Delete the test VM created by Candace on the shared network
openstack server delete vm-test-candace

# Delete the test network created by Candace
openstack network delete net-test-candace

# Use Baron's identity
export OS_CLOUD=baron

# Delete the test VM created by Baron in his own project
openstack server delete vm-test-baron

# Delete the test network created by Baron in his own project
openstack network delete net-test-baron

# Use the admin identity
export OS_CLOUD=admin

# Delete the test VM created by admin in its own project
openstack server delete vm-test-admin

# Delete the test network created by admin in its own project
openstack network delete net-test-admin

# Delete the test flavor created by admin
openstack flavor delete test-flavor
```

> [!TIP]
> **If you get stuck**
> If a deletion fails or you are running out of time, the `clean_lab02.sh` script (available in this folder) runs all the cleanup commands above, in the right order:
>
> ```bash
> chmod +x clean_lab02.sh
> ./clean_lab02.sh
> ```
>
> The script skips resources that are already deleted: you can run it even after a partial cleanup. Read its content before running it: every command is commented.

### 3.7. Where are the access rules defined?

- You observed that candace can create a VM and ian cannot, and that only admin can use `--all-projects`. These decisions are not made by Keystone: Keystone only says **who** you are and **which roles** you have.
- It is **each service** (Nova, Neutron, Glance…) that then decides whether your roles allow the requested operation, by consulting its **access policy**.

| Concept | Meaning |
| --- | --- |
| **Access policy** | Set of rules specific to each service: for each API operation, the condition to meet |
| **Rule** | A line of the form `"name": "condition"` |
| **Default rules** | Written in the service's code; they apply as long as the administrator does not change them |
| **`policy.yaml`** | File (for example `/etc/nova/policy.yaml`) where the administrator can override some rules |

**Step 1: display the rules for two of the tested operations**

The `oslopolicy-sample-generator` tool displays all of a service's default rules. It is installed in DevStack's Python environment: call it by its full path.

```bash
POLICY=/opt/stack/data/venv/bin/oslopolicy-sample-generator

# Action: create a VM
$POLICY --namespace nova | grep 'servers:create"'

# Action: list the VMs of all projects (--all-projects)
$POLICY --namespace nova | grep all_tenants
```

**How to read a rule**

| Element | Meaning |
| --- | --- |
| `#` at the start of a line | Default value, active as long as a `policy.yaml` does not override it |
| `rule:<name>` | Reference: "apply the rule named `<name>`", defined elsewhere in the policy |
| `role:<role>` | The user must have this role |
| `project_id:%(project_id)s` | The project of the user's token must be the project of the target resource |
| `and` / `or` | Both conditions / either one |

**Step 2: break down the VM creation rule**

In step 1, the VM creation rule displays:

```
#"os_compute_api:servers:create": "rule:project_member_or_admin"
```

It contains no role: it refers to another rule, `project_member_or_admin`. To find out what it actually requires, display that rule:

```bash
$POLICY --namespace nova | grep '^#"project_member_or_admin"'
```

This rule in turn refers to two other rules. Display them as well:

```bash
$POLICY --namespace nova | grep -E '^#"(project_member_api|context_is_admin)"'
```

This time you get basic conditions (`role:…`, `project_id:…`): the breakdown is complete.

**Q14.**

a) Draw the VM creation rule as a tree, from `os_compute_api:servers:create` down to the basic conditions. Translate it into a plain English sentence.

```
os_compute_api:servers:create
└── rule:
    ├── rule: ---
    │     └── role: ---
    └── OR rule: ---
          └── role: ---
```

b) Using your tree, fill in the table (Yes / No), then explain why candace can create a VM in team-a, while ian (same project, `reader` role) and baron (`member` role, but project team-b) cannot.

| User | Has the `member` role? | Is their token bound to project team-a? | Has the `admin` role? | Creation allowed? |
| --- | --- | --- | --- | --- |
| candace | | | | |
| ian | | | | |
| baron | | | | |

For each refusal, state **which condition** of the tree is not met.

c) In step 1, which rule protects `--all-projects`? Explain why only admin can use it.
