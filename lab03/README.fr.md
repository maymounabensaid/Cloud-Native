# Lab 03 — Compute & Images : Nova et Glance

**Module : Infrastructures Cloud Natives**
**Environnement :** instance EC2 r8i.large avec DevStack 


---

## Objectifs



- Gérer des images avec **Glance** : import, formats, propriétés, visibilité et partage entre projets ;
- Définir des **gabarits (flavors)** adaptés à un besoin ;
- Personnaliser une instance au démarrage avec **cloud-init** et le **service de métadonnées** ;
- Piloter le **cycle de vie** d'une instance Nova (stop, pause, suspend, shelve, resize) et expliquer l'effet de chaque opération ;
- Créer un **snapshot d'instance** et redéployer à partir de celui-ci ;
- Observer côté hyperviseur (**libvirt / KVM**) ce que Nova a réellement créé.

 

---

## Partie 0 — Remise en état de l'environnement

Si l'instance EC2 a été arrêtée depuis la dernière séance, vérifiez que les services OpenStack sont bien repartis.

```bash
sudo systemctl list-units 'devstack@*' --no-pager
source ~/devstack/openrc admin admin       
openstack compute service list
openstack hypervisor list
openstack network agent list
```

Tous les services doivent être `up` / `enabled`. Si un service est arrêté :

```bash
sudo systemctl restart devstack@<service>
```

> **Q1.** Quels services Nova apparaissent dans `openstack compute service list` ? Expliquez en une phrase le rôle de chacun (`nova-scheduler`, `nova-conductor`, `nova-compute`).

---

## Partie 1 — Glance : gestion des images

### 1.1 Explorer les images existantes

```bash
openstack image list
openstack image show <id-image-cirros>
```

> **Q2.** Relevez le format disque (`disk_format`), le format conteneur (`container_format`), la taille, la visibilité et le propriétaire de l'image CirrOS.

### 1.2 Importer une image Ubuntu cloud

```bash
wget https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img
qemu-img info ubuntu-24.04-minimal-cloudimg-amd64.img
```

> **Q3.** Quel est le format réel du fichier selon `qemu-img info` ? Comparez sa taille sur disque (*disk size*) et sa taille virtuelle (*virtual size*). Pourquoi ces deux valeurs diffèrent-elles ?

Créez l'image dans Glance :

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

Vérifiez où Glance a stocké l'image (backend `file` par défaut dans DevStack) :

```bash
openstack image show ubuntu-24.04-minimal -c id -c status -c checksum
sudo ls -lh /opt/stack/data/glance/images/
```

> **Q4.** Quel est le nom du fichier stocké par Glance ? Quel lien a-t-il avec l'image ? À quoi servent `--min-disk` et `--min-ram` ?

### 1.3 Visibilité et partage entre projets

Glance propose quatre niveaux de visibilité : `private`, `shared`, `community`, `public`.

#### a) Créer un projet et un utilisateur de test (rappel du Lab 02)

Avec les identifiants `admin` :

```bash
source ~/devstack/openrc admin admin
openstack project create projet-lab03
openstack user create etudiant-lab03 --project projet-lab03 --password Lab03Pass
openstack role add --project projet-lab03 --user etudiant-lab03 member
```

> **Important :** un administrateur voit toutes les images, quelle que soit leur visibilité. Pour observer réellement l'effet du partage, il faut se placer du point de vue d'un utilisateur **non administrateur**.

#### b) Vérifier que l'image est invisible pour le nouveau projet

Ouvrez un **second terminal** sur l'instance EC2 et connectez-vous en tant que `etudiant-lab03` :

```bash
source ~/devstack/openrc admin admin
export OS_USERNAME=etudiant-lab03
export OS_PASSWORD=Lab03Pass
export OS_PROJECT_NAME=projet-lab03
openstack token issue -c project_id -c user_id
openstack image list
```

#### c) Partager l'image avec le projet

Dans le **premier terminal** (admin) :

```bash
openstack image set --shared ubuntu-24.04-minimal
openstack image add project ubuntu-24.04-minimal projet-lab03
openstack image member list ubuntu-24.04-minimal
```

#### d) Accepter le partage

Dans le **second terminal** (`etudiant-lab03`) :

```bash
openstack image list
openstack image set --accept <id-image-ubuntu>
openstack image list
```

Vérifiez à nouveau le statut du membre dans le premier terminal :

```bash
openstack image member list ubuntu-24.04-minimal
```

> **Q5.** L'image est-elle visible pour `etudiant-lab03` **avant** le partage ? Après le partage mais **avant** l'acceptation ? Après l'acceptation ? Quel est le statut du membre (`pending`, `accepted`, `rejected`) à chaque étape ?
>
> **Q6.** Quelle différence entre une image `shared` et une image `community` ? Qui peut rendre une image `public` et pourquoi cette opération est-elle réservée à ce rôle ?
---

## Partie 2 — Les gabarits (flavors)

```bash
openstack flavor list
```

Créez deux gabarits (avec les identifiants `admin`) :

```bash
openstack flavor create lab03.small  --vcpus 1 --ram 1024 --disk 5
openstack flavor create lab03.medium --vcpus 2 --ram 2048 --disk 8
```

Créez un gabarit privé, réservé au projet du Lab 02 :

```bash
openstack flavor create lab03.private --vcpus 1 --ram 512 --disk 4 --private
openstack flavor set lab03.private --project <projet-lab02>
```

> **Q7.** Peut-on lancer l'image Ubuntu avec le gabarit `m1.tiny` ? Testez puis expliquez le message obtenu en lien avec `--min-disk` et `--min-ram`.
>
> **Q8.** Le gabarit `lab03.private` apparaît-il dans `openstack flavor list` lorsqu'on est connecté avec un autre projet ? À quoi sert un gabarit privé dans un cloud d'entreprise ?

---

## Partie 3 — Personnalisation au démarrage : cloud-init et métadonnées

### 3.1 Préparer le réseau et l'accès à l'instance 

Toutes les commandes de cette partie sont exécutées avec les identifiants `admin` (premier terminal).

#### a) Réseau privé, sous-réseau et routeur

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

#### b) Groupe de sécurité

Autorisez SSH, HTTP et le ping :

```bash
openstack security group create sg-lab03 --description "SSH, HTTP et ICMP pour le Lab 03"
openstack security group rule create --protocol tcp --dst-port 22 sg-lab03
openstack security group rule create --protocol tcp --dst-port 80 sg-lab03
openstack security group rule create --protocol icmp sg-lab03
openstack security group rule list sg-lab03
```

#### c) Paire de clés

```bash
openstack keypair create cle-lab03 > cle-lab03.pem
chmod 600 cle-lab03.pem
```
### 3.2 Écrire le fichier user-data

Créez le fichier `web-init.yaml` :

```bash
nano web-init.yaml`
```
Collez le contenu suivant :

```bash
#cloud-config
hostname: vm-web
write_files:
  - path: /var/www/index.html
    content: |
      <h1>Lab 03 - Instance configuree par cloud-init</h1>
runcmd:
  - cd /var/www && nohup python3 -m http.server 80 > /var/log/web.log 2>&1 &
```

Signification des directives :

| Directive       | Rôle                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------- |
| `#cloud-config` | Première ligne **obligatoire** : indique à cloud-init que le fichier est au format cloud-config (YAML)              |
| `hostname`      | Nom d'hôte attribué à la VM                                                                                         |
| `write_files`   | Crée des fichiers dans la VM (ici la page d'accueil du site)                                                        |
| `runcmd`        | Commandes exécutées en `root` à la fin du premier démarrage (ici, lancement d'un serveur web Python sur le port 80) |
Vérifiez le fichier :

```bash
ls -l web-init.yaml
cat web-init.yaml
sudo cloud-init schema --config-file web-init.yaml
```

La dernière commande valide la syntaxe du fichier avec l'outil cloud-init installé sur l'instance EC2. Le résultat attendu est `Valid schema web-init.yaml`.


### 3.3 Lancer l'instance

```bash
openstack server create vm-web \
    --image ubuntu-24.04-minimal \
    --flavor lab03.small \
    --network net-lab03 \
    --security-group sg-lab03 \
    --key-name cle-lab03 \
    --user-data web-init.yaml \
    --wait

openstack floating ip create public
openstack server add floating ip vm-web <ip-flottante>
```

Suivez le démarrage via la console :

```bash
openstack console log show vm-web | grep -i cloud-init
```

Testez la connectivité, puis le service web depuis l'hôte EC2. Si ce n'est pas déjà fait, activez d'abord le bridge externe `br-ex` :

```bash
sudo ip addr add 172.24.4.1/24 dev br-ex
sudo ip link set br-ex up
ping -c 3 <ip-flottante>
curl -m 10 http://<ip-flottante>
```

Testez le service web depuis l'hôte EC2 :

```bash
curl http://<ip-flottante>
```

### 3.4 Le service de métadonnées

Connectez-vous à la VM :

```bash
ssh -i cle-lab03.pem ubuntu@<ip-flottante>
ubuntu@vm-web:~$ cloud-init status --long
ubuntu@vm-web:~$ curl http://169.254.169.254/openstack/latest/meta_data.json
ubuntu@vm-web:~$ curl http://169.254.169.254/openstack/latest/user_data
```

> **Q9.** Comment la VM récupère-t-elle sa configuration au démarrage ? Quel composant répond à l'adresse `169.254.169.254` ?
>
> **Q10.** Le contenu de `user_data` est lisible par tout processus de la VM. Quelle conséquence pour la sécurité ? Que ne faut-il jamais y placer ?
>
> **Q11.** Comparez cette approche avec AWS EC2 : quel est l'équivalent du user-data et du service de métadonnées ?

