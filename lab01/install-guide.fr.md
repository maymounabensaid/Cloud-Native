 

# TP01 — Guide d'installation illustré

Ce guide détaille, avec des captures d'écran de la console AWS, la préparation de l'instance EC2 et l'installation de DevStack. Il accompagne les sections 1 et 2 de l'**[énoncé du TP01](README.fr.md)**.

---

## 1. Provisionnement de l'instance EC2

**Nom** : `DevStack` — **AMI** : Ubuntu **26.04 LTS**

<img src="img/vm1.png" width="85%">

**Type d'instance** : `r8i.large` (2 vCPU, 16 Go de RAM)

<img src="img/vm2.png" width="85%">

**Paire de clés** : créez une nouvelle paire de clés nommée `devstack`

<img src="img/vm3.png" width="85%">

<img src="img/vm4.png" width="85%">

**Groupe de sécurité** : créez un nouveau groupe `DevStack SG` avec les règles suivantes :

- SSH (port 22) — depuis n'importe où
- HTTP (port 80) — depuis n'importe où

<img src="img/vm5.png" width="85%">

<img src="img/vm6.png" width="85%">

<img src="img/vm7.png" width="85%">

<img src="img/vm8.png" width="85%">

**Stockage** : **50 Go**

<img src="img/vm30.png" width="85%">

---

## 2. Association d'une adresse IP élastique

<img src="img/vm10.png" width="85%">

<img src="img/vm11.png" width="85%">

<img src="img/vm12.png" width="85%">

<img src="img/vm13.png" width="85%">

<img src="img/vm14.png" width="85%">

---

## 3. Activation de la virtualisation imbriquée (*nested virtualization*)

> [!IMPORTANT]
> L'instance doit être **arrêtée** (*Stop*, pas *Terminate*) pour modifier ses options CPU.

<img src="img/vm16.png" width="85%">

<img src="img/vm17.png" width="85%">

<img src="img/vm18.png" width="85%">

<img src="img/vm19.png" width="85%">

<img src="img/vm20.png" width="85%">

---

## 4. Connexion SSH

<img src="img/vm21.png" width="85%">

<img src="img/vm22.png" width="85%">

<img src="img/vm23.png" width="85%">

---

## 5. Installation de DevStack

1. Mettez à jour le système, puis redémarrez :

   ```bash
   sudo apt update
   sudo apt upgrade -y
   sudo reboot
   ```

   Attendez une minute, puis reconnectez-vous en SSH.

2. Installez les outils de base :

   ```bash
   sudo apt install -y git curl net-tools
   ```

3. Téléchargez DevStack :

   ```bash
   git clone https://opendev.org/openstack/devstack
   ```

4. Créez le fichier `local.conf` :

   ```bash
   cd devstack
   nano local.conf
   ```

   Copiez-collez le contenu suivant :

   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=secret
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   ```

   <img src="img/vm24.png" width="85%">

5. Lancez l'installation :

   ```bash
   ./stack.sh
   ```

   <img src="img/vm25.png" width="85%">

---

## 6. Vérification des services (CLI)

Chargez les identifiants OpenStack dans le shell courant, puis listez les services :

```bash
cd ~/devstack
source openrc admin admin
openstack service list
```

<img src="img/vm26.png" width="85%">

<img src="img/vm27.png" width="85%">

---

## 7. Accès à l'interface graphique Horizon

- URL : `http://<IP_élastique_de_l_instance>`
- Utilisateur : `admin`
- Mot de passe : `secret` (valeur définie dans `local.conf`)

<img src="img/vm28.png" width="85%">

<img src="img/vm29.png" width="85%">

---

L'installation est terminée. Reprenez l'**[énoncé du TP01](README.fr.md)** à la section 3.
