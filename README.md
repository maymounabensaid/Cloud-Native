

# Cloud-Native Infrastructures

Hands-on labs for the **Cloud-Native Infrastructures** module.



---

## Labs

| Lab | Topic | Services | Instructions |
| --- | --- | --- | --- |
| Lab 01 | Deploying and exploring an OpenStack infrastructure | DevStack, Horizon, CLI | [lab01](lab01/) |
| Lab 02 | Identity, projects and access control | Keystone | [lab02](lab02/) |
| Lab 03 | Compute and images | Nova, Glance | *coming soon* |
| Lab 04 | Storage | Cinder, Swift | *coming soon* |
| Lab 05 | Advanced networking | Neutron | *coming soon* |
| Lab 06 | Infrastructure as Code | OpenTofu | *coming soon* |


---

## Lab environment

All labs use **the same EC2 instance**, prepared in Lab 01:

- an AWS EC2 instance with nested virtualization (`r8i.large` type), running Ubuntu;
- OpenStack installed with **DevStack**;
- access over SSH, and to the Horizon web dashboard through the instance's public IP address.

> [!IMPORTANT]
> Keep your instance from one session to the next. **Stop** it at the end of each session to limit costs, but do not **Terminate** it.

---

## Repository layout

```
Cloud-Native/
├── README.md          
├── lab01/
│   ├── README.md      
│   └── README.fr.md   
└── lab02/
    ├── README.md      
    ├── README.fr.md   
    └── clean_lab02.sh 
```

Each `labXX/` folder contains the lab instructions along with any scripts used during the lab. 
