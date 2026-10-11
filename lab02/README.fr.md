[EN English](README.md) | 🇫🇷 Français

# TP02 — Keystone : identité, projets et contrôle d'accès

## Objectifs du TP

Ce TP porte sur Keystone, le service d'identité d'OpenStack. Vous allez découvrir comment un client s'authentifie et trouve les services du cloud, puis comment Keystone, avec les autres services, isole les projets et contrôle ce que chaque utilisateur peut faire.

À l'issue du TP, vous serez capable de :

**Partie 1 — De la CLI aux API REST**

1. Charger une identité avec `openrc` et expliquer le rôle des variables `OS_*`.
2. Expliquer ce que sont un jeton, le catalogue de services et un endpoint, et comment ils s'articulent.
3. Lire la sortie de la CLI en mode `--debug` pour reconstituer l'échange HTTP entre le client et les services (découverte de version, authentification, appel métier).
4. Interroger une API OpenStack directement avec `curl` et un jeton, et expliquer l'effet de sa révocation.

**Partie 2 — Projets, utilisateurs et rôles**

5. Décrire l'organisation de Keystone : domaines, projets, utilisateurs, groupes et rôles.
6. Créer des projets et des utilisateurs, et leur attribuer des rôles.
7. Gérer plusieurs identités avec le fichier `clouds.yaml`.

**Partie 3 — Isolation et contrôle d'accès**

8. Vérifier l'isolation entre projets (multi-tenancy) : un utilisateur ne voit pas les ressources d'un autre projet.
9. Observer le contrôle d'accès basé sur les rôles (RBAC) : distinguer les droits des rôles `admin`, `member` et `reader`, et interpréter les refus (403) et les ressources introuvables (404).
10. Lire la politique d'accès d'un service pour expliquer pourquoi une opération est autorisée ou refusée.

---

## Partie 1 — De la CLI aux API REST d'OpenStack

La CLI `openstack` n'est qu'un client HTTP : elle demande un jeton à Keystone, lit le catalogue pour trouver l'URL du service, puis appelle son API REST.

### 1.1. Charger son identité : `source openrc`

Avant toute commande, la CLI doit savoir qui vous êtes et où se trouve Keystone. DevStack fournit pour cela le script `openrc` :

```bash
cd ~/devstack
source openrc admin admin        # syntaxe : source openrc <utilisateur> <projet>
env | grep ^OS_                  # affiche les variables chargées
```

| Élément | Rôle |
| --- | --- |
| `source` | Exécute le script **dans le terminal courant** : les variables qu'il définit restent disponibles pour les commandes suivantes. Lancé sans `source` (`./openrc`), le script s'exécuterait dans un sous-shell et les variables disparaîtraient à la fin. |
| `openrc` | Script de DevStack qui définit les variables d'environnement `OS_*`. |
| 1er argument (`admin`) | Nom de l'**utilisateur**. |
| 2e argument (`admin`) | Nom du **projet** auquel le jeton sera lié (*scope*). |

**Principales variables chargées :**

| Variable | Contenu | Utilisée pour |
| --- | --- | --- |
| `OS_AUTH_URL` | `http://<IP>/identity` | La **seule adresse** que la CLI connaît au départ : celle de Keystone |
| `OS_USERNAME` / `OS_PASSWORD` | Identifiants de l'utilisateur | Le corps de la requête d'authentification |
| `OS_PROJECT_NAME` | Projet visé | Le *scope* du jeton |
| `OS_USER_DOMAIN_NAME`, `OS_PROJECT_DOMAIN_NAME` | Domaine (`Default`) | Identifier sans ambiguïté l'utilisateur et le projet |
| `OS_REGION_NAME` | `RegionOne` | Choisir les endpoints de la bonne région dans le catalogue |

> [!TIP]
> **À retenir :** ces variables ne contiennent pas de jeton, mais des identifiants. La CLI les envoie à Keystone à chaque commande pour obtenir un nouveau jeton. Elles n'existent que dans le terminal où elles ont été chargées : il faut refaire `source openrc` dans chaque nouveau terminal ou nouvelle connexion SSH.

### 1.2. Jeton (token), catalogue et endpoints

#### 1.2.1. Jeton (token)

Lancez la commande ci-dessous :

```bash
openstack token issue
```

| Commande | Ce qu'elle fait | Service interrogé | Ce qu'elle affiche | À retenir |
| --- | --- | --- | --- | --- |
| `openstack token issue` | Demande un **nouveau jeton** à Keystone avec les identifiants chargés (`openrc` ou `clouds.yaml`) et l'affiche en clair. | Keystone | `expires` : date et heure d'expiration ; `id` : le jeton lui-même ; `project_id` : projet auquel le jeton est lié (*scope*) ; `user_id` : utilisateur authentifié. | Le jeton est une **preuve d'identité temporaire** : par défaut, Keystone le rend valable 1 heure. Il est lié à **un seul projet** : changer de projet impose un nouveau jeton. |

**Q1.** Quelle est la durée de validité du jeton ? À quel projet est-il lié (*scope*) ?

> [!NOTE]
> La commande `source openrc` ne charge pas de jeton, elle charge des identifiants (nom d'utilisateur, mot de passe, projet, URL de Keystone) dans des variables d'environnement `OS_*`.
> Ces variables n'expirent pas : la CLI s'en sert pour demander un nouveau jeton à chaque commande. L'expiration au bout d'une heure ne la gêne donc jamais.

**Pourquoi cette commande ?**

- Chaque commande `openstack` (ex. `openstack server list`) demande automatiquement un **nouveau jeton** à Keystone, l'utilise, puis le jette, sans vous le montrer.
- `openstack token issue` fait uniquement la première étape : elle **demande un jeton et l'affiche**. Elle sert à :
  - vérifier l'authentification : si elle échoue, le problème vient de Keystone ou de vos variables `OS_*` (vérifiez avec `env | grep ^OS`), pas des autres services ;
  - observer le contenu d'un jeton : utilisateur (`user_id`), projet (`project_id`) et date d'expiration (`expires`, 1 h par défaut) ;
  - réutiliser le jeton pour appeler directement les API REST (voir section 1.3).

> [!TIP]
> **À retenir :** toute requête vers un service OpenStack passe d'abord par Keystone pour obtenir un jeton. Le jeton est ensuite envoyé dans l'en-tête HTTP `X-Auth-Token`.

#### 1.2.2. Catalogue

Lancez la commande ci-dessous :

```bash
openstack catalog list
```

| Commande | Ce qu'elle fait | Service interrogé | Ce qu'elle affiche | À retenir |
| --- | --- | --- | --- | --- |
| `openstack catalog list` | Affiche le **catalogue de services** que Keystone renvoie avec chaque jeton. | Keystone (le catalogue fait partie de la réponse d'authentification) | `Name` : nom du service (`nova`, `glance`…) ; `Type` : type normalisé (`compute`, `image`…) ; `Endpoints` : pour chaque région et interface, l'URL du service. | C'est l'**annuaire** du cloud : la CLI, Horizon ou Terraform y cherchent l'URL d'un service par son **type**. Il dépend du jeton : un utilisateur ne voit que les services auxquels son projet a accès. |

#### 1.2.3. Endpoints

Lancez la commande ci-dessous :

```bash
openstack endpoint list --interface public
```

| Commande | Ce qu'elle fait | Service interrogé | Ce qu'elle affiche | À retenir |
| --- | --- | --- | --- | --- |
| `openstack endpoint list --interface public` | Liste les **endpoints** enregistrés dans Keystone, filtrés sur l'interface `public`. | Keystone | `ID`, `Region`, `Service Name`, `Service Type`, `Enabled`, `Interface`, `URL` : une ligne par endpoint. | Même information que le catalogue, mais vue **côté administration** : une ligne par endpoint, avec son ID, ce qui permet de le modifier ou le supprimer. L'interface `public` sert aux utilisateurs ; `internal` sert aux échanges entre services ; `admin` sert aux opérations d'administration. Cette commande demande en général le rôle `admin`. |

**Q2.** Comparez les sorties de `openstack catalog list` et de `openstack endpoint list --interface public` :

> a) Les URL sont-elles les mêmes dans les deux sorties ? Relevez le cas du service `nova_legacy` : quelle différence observez-vous entre les deux commandes, et comment l'expliquez-vous ?

> b) Tous les services utilisent la même adresse IP. Comment le serveur sait-il à quel service transmettre une requête ?

> c) Relancez `openstack endpoint list` **sans** l'option `--interface public`. Le résultat change-t-il ? Quelles interfaces DevStack a-t-il déclarées ? Pourquoi un cloud de production déclarerait-il aussi une interface `internal` ?
>
> *Dans Keystone, un même service peut être enregistré avec plusieurs adresses, une par interface, c'est-à-dire selon qui l'appelle et depuis quel réseau.*

> d) Changez d'identité en chargeant l'utilisateur `demo` du projet `demo`, puis relancez les trois commandes :

```bash
source ~/devstack/openrc demo demo
openstack token issue
openstack catalog list
openstack endpoint list --interface public
```

> Comparez avec les résultats obtenus en tant qu'admin : qu'est-ce qui change dans le jeton ? Dans l'URL de `nova_legacy` ? Que se passe-t-il pour `endpoint list`, et pourquoi ?
>
> Revenez ensuite à l'identité admin : `source ~/devstack/openrc admin admin`.

### 1.3. Interroger l'API sans la CLI

La CLI n'est qu'un client HTTP. Vous allez faire vous-même ses deux étapes : obtenir un jeton, puis appeler un service.

> [!IMPORTANT]
> Vérifiez que vous utilisez l'identité admin : `source ~/devstack/openrc admin admin`

#### 1.3.1. Jeton et URL de Nova (récupérés une fois avec la CLI)

```bash
export TOKEN=$(openstack token issue -f value -c id)
export NOVA=$(openstack endpoint list --service compute --interface public -f value -c URL)
```

| Élément | Rôle |
| --- | --- |
| `export TOKEN=…` | Crée la variable d'environnement `TOKEN`, réutilisable ensuite avec `$TOKEN`. |
| `$( … )` | Exécute la commande entre parenthèses et remplace l'expression par son résultat. |
| `openstack token issue` | Demande un nouveau jeton à Keystone. |
| `-f value` | *Format* : affiche les valeurs brutes, sans tableau ni bordures. Autres formats : `table` (par défaut), `json`, `yaml`, `shell`. |
| `-c id` | *Column* : ne garde que la colonne `id`, qui contient le jeton. |
| `openstack endpoint list --service compute --interface public` | Cherche dans Keystone l'URL publique du service `compute` (Nova), stockée dans `NOVA`. |

#### 1.3.2. Appel direct à l'API de Nova

```bash
curl -s  -H "X-Auth-Token: $TOKEN" $NOVA/servers
curl -si $NOVA/servers | head -1
```

| Élément | Commande 1 : avec jeton | Commande 2 : sans jeton |
| --- | --- | --- |
| `curl` | Envoie une requête HTTP `GET` à l'URL indiquée. | Idem. |
| `-s` | *Silent* : masque la barre de progression. | Idem. |
| `-i` | — | *Include* : affiche aussi les en-têtes de la réponse, dont la ligne de statut HTTP. |
| `-H "X-Auth-Token: $TOKEN"` | Ajoute l'en-tête qui porte le jeton : la preuve d'identité. | **Absent** : aucune preuve d'identité n'est envoyée. |
| `$NOVA/servers` | Ressource « liste des instances » de l'API Nova. | Idem. |
| `\| head -1` | — | Ne garde que la première ligne de la réponse : le code HTTP. |
| **Résultat** | `{"servers": []}` : Nova accepte la requête et renvoie la liste. | `HTTP/1.1 401 Unauthorized` : Nova refuse, faute de jeton. |

> [!NOTE]
> Une seule commande CLI, `openstack server list`, enchaîne automatiquement plusieurs requêtes HTTP : négociation de version, authentification auprès de Keystone, recherche du service dans le catalogue, puis appel à Nova. Elle met ensuite la réponse en forme. Avec `curl`, chacune de ces étapes doit être faite à la main.
>
> **La CLI est une abstraction des API REST.**

#### 1.3.3. Révocation d'un jeton

```bash
export TOKEN2=$(openstack token issue -f value -c id)
openstack token revoke $TOKEN2
curl -s -H "X-Auth-Token: $TOKEN2" $NOVA/servers
curl -s -H "X-Auth-Token: $TOKEN"  $NOVA/servers
openstack server list
```

| Élément | Rôle |
| --- | --- |
| `export TOKEN2=…` | Obtient un **second jeton**, indépendant du premier. |
| `openstack token revoke $TOKEN2` | Demande à Keystone d'invalider ce jeton. N'affiche rien en cas de succès. |
| `curl … $TOKEN2 …` | Appelle Nova avec le jeton révoqué → `HTTP/1.1 401 Unauthorized` : Nova fait valider le jeton par Keystone, qui le déclare révoqué. |
| `curl … $TOKEN …` | Même appel avec le premier jeton → `HTTP/1.1 200 OK` : seul le jeton révoqué est refusé. |
| `openstack server list` | Fonctionne normalement : la CLI n'utilise ni `$TOKEN` ni `$TOKEN2`, elle obtient un nouveau jeton avec les identifiants d'`openrc`. |

> [!TIP]
> **À retenir :**
> - Le jeton est la preuve d'identité obligatoire pour toute requête métier. Il est délivré par Keystone, présenté dans l'en-tête `X-Auth-Token`, et vérifié par le service appelé auprès de Keystone. Sans jeton valide, aucun service n'exécute de requête, même une simple lecture.
> - Un jeton a une durée de vie limitée (expiration) et peut être invalidé à tout moment (révocation). Il ne contient pas le mot de passe : on peut couper un accès sans changer les identifiants de l'utilisateur.
> - Révoquer un jeton n'affecte que ce jeton : les autres jetons du même utilisateur restent valides.

---

## Partie 2 — Projets, utilisateurs et rôles

Vous allez créer deux équipes et trois utilisateurs.

| Utilisateur | Projet | Rôle | Usage dans le TP |
| --- | --- | --- | --- |
| candace | team-a | member | Opère les ressources de l'équipe A |
| baron | team-b | member | Opère les ressources de l'équipe B |
| ian | team-a | reader | Consulte l'équipe A sans rien modifier |

### 2.1. Explorer l'existant

```bash
openstack domain list
openstack project list
openstack user list
openstack role list
openstack role assignment list --names
```

**Q4.** Quels projets et utilisateurs DevStack a-t-il créés ? Quels rôles existent ? Que signifie la colonne `Inherited` ?

### 2.2. Créer projets, utilisateurs et attributions

**Étape 1 : créer les projets**

```bash
openstack project create --domain Default --description "Équipe A" team-a
openstack project create --domain Default --description "Équipe B" team-b
```

**Étape 2 : créer les utilisateurs, sans rôle**

```bash
openstack user create --domain Default --project team-a --password 'Candace#2026' candace
openstack user create --domain Default --project team-b --password 'Baron#2026'   baron
openstack user create --domain Default --project team-a --password 'Ian#2026'     ian
```

**Étape 3 : tenter de s'authentifier en tant que candace**

```bash
openstack --os-username candace --os-password 'Candace#2026' --os-project-name team-a token issue
```

> [!TIP]
> **À retenir :** un utilisateur qui existe, avec un mot de passe correct et un projet par défaut, ne peut pas obtenir de jeton tant qu'il n'a aucun rôle sur ce projet : Keystone répond 401.
> - Le projet par défaut (`--project` à la création) n'est qu'une préférence, pas une autorisation.
> - C'est l'attribution d'un rôle sur un projet (`openstack role add`) qui donne le droit d'y travailler.
> - Identité ≠ autorisation : exister dans Keystone ne donne accès à rien.

**Étape 4 : attribuer les rôles**

```bash
openstack role add --project team-a --user candace member
openstack role add --project team-b --user baron   member
openstack role add --project team-a --user ian     reader
```

**Étape 5 : tenter de s'authentifier en tant que candace (2e tentative)**

```bash
openstack --os-username candace --os-password 'Candace#2026' --os-project-name team-a token issue
```

**Q5.** L'option `--project` de `user create` donne-t-elle un rôle à l'utilisateur ?

> [!NOTE]
> Pour qu'un utilisateur puisse travailler dans un projet, il faut une **attribution de rôle** explicite (`role add`) : le triplet utilisateur · rôle · projet. Sans elle, Keystone refuse même de délivrer un jeton lié à ce projet, puisque l'utilisateur n'y a aucun rôle.

### 2.3. Un profil par identité avec `clouds.yaml`

- Avec `source openrc`, on ne peut charger qu'une identité à la fois, et il faut recharger le script pour en changer.
- Le fichier `clouds.yaml` règle ce problème : c'est un **carnet de connexions**, où chaque **profil** regroupe tout ce qu'il faut pour se connecter sous une identité. On choisit ensuite le profil par son nom.
- Ce fichier est le format standard des clients OpenStack (CLI, SDK Python, Ansible, Terraform).

> [!IMPORTANT]
> **Prérequis :** les utilisateurs candace, baron et ian doivent avoir été créés en 2.2, avec les mots de passe ci-dessous et un rôle sur leur projet.

Créez le fichier `clouds.yaml` dans `~/.config/openstack` :

```bash
mkdir -p ~/.config/openstack
nano ~/.config/openstack/clouds.yaml
```

Copiez-collez le contenu ci-dessous. Remplacez `<ADMIN_PASSWORD>` par le mot de passe de l'utilisateur admin, déclaré dans le fichier `local.conf`. Enregistrez avec **Ctrl + O** puis **Entrée**, et quittez avec **Ctrl + X**.

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
> Gardez les apostrophes autour des mots de passe. En YAML, `#` commence un commentaire : sans apostrophes, `Candace#2026` serait lu `Candace`.

Modifiez les permissions d'accès du fichier pour qu'il ne soit lisible et modifiable que par son propriétaire, car il contient des mots de passe en clair :

```bash
chmod 600 ~/.config/openstack/clouds.yaml
```

Videz les variables `OS_*` chargées par `openrc` (dans le terminal courant, ou dans une seconde connexion SSH à votre instance) : sinon, elles prennent le pas sur `clouds.yaml`.

```bash
unset $(env | grep '^OS_' | cut -d= -f1)
```

Testez le chargement de chaque profil :

```bash
openstack --os-cloud admin   token issue
openstack --os-cloud candace token issue
openstack --os-cloud baron   token issue
openstack --os-cloud ian     token issue
```

**Q6.** Pour chaque jeton, relevez le projet et l'identifiant utilisateur. Quels profils partagent le même projet ? Qu'est-ce que cela signifie ?

Pour la suite, choisissez l'identité de tout le terminal avec `export OS_CLOUD=<profil>` : les commandes suivantes s'exécutent alors sous ce profil, sans option. Inutile de demander un jeton au préalable : chaque commande s'authentifie elle-même.

> [!NOTE]
> **`openrc` ou `clouds.yaml` ?**
>
> | | `source ~/devstack/openrc <user> <projet>` | `clouds.yaml` + `OS_CLOUD` / `--os-cloud` |
> |---|---|---|
> | Principe | Charge des variables `OS_*` dans le terminal | Choisit un profil nommé dans un fichier |
> | Mot de passe | Toujours celui de l'**admin DevStack** (`OS_PASSWORD`) | Celui défini dans le profil |
> | Changer d'identité | Refaire un `source` (et un `export OS_PASSWORD=…` pour un utilisateur créé à la main) | `export OS_CLOUD=<profil>`, ou `--os-cloud <profil>` pour une seule commande |

> [!WARNING]
> **Ne mélangez jamais les deux.** Les variables `OS_*` d'`openrc` sont **prioritaires** sur `clouds.yaml` : si elles sont encore chargées, vous risquez d'agir sous une autre identité que celle choisie. Avant d'utiliser `OS_CLOUD`, videz-les :
>
> ```bash
> unset $(env | grep ^OS_ | cut -d= -f1)
> export OS_CLOUD=candace
> env | grep ^OS          # seule OS_CLOUD doit apparaître
> ```

### 2.4. Groupes

Créez un groupe `ops`, ajoutez-y candace, puis donnez au groupe le rôle `reader` sur team-b.

```bash
export OS_CLOUD=admin
openstack group create ops
openstack group add user ops candace
openstack role add --group ops --project team-b reader
```

Listez tous les rôles de candace :

```bash
openstack role assignment list --names --user candace
```

Listez tous les rôles **effectifs** de candace : ceux qui lui sont attribués directement et ceux qu'elle obtient par son appartenance à un groupe :

```bash
openstack role assignment list --names --effective --user candace
```

**Q7.** Pourquoi l'option `--effective` change-t-elle le résultat ? Quel est l'intérêt des groupes quand 40 étudiants rejoignent un projet ?

Retirez ensuite le rôle du groupe, pour ne pas fausser la partie 3, puis vérifiez :

```bash
openstack --os-cloud admin role remove --group ops --project team-b reader
openstack --os-cloud admin role assignment list --names --effective --user candace
```

Seul le rôle `member` sur team-a doit apparaître.

---

## Partie 3 — Isolation et contrôle d'accès

Chaque projet est un **locataire** (*tenant*) isolé : ses réseaux, VM et groupes de sécurité appartiennent au projet, et non aux utilisateurs.

> [!NOTE]
> **Le modèle RBAC.** OpenStack applique un contrôle d'accès basé sur les rôles (*Role-Based Access Control*, RBAC) : on n'attribue pas des droits directement à un utilisateur, mais un **rôle** sur un **projet**. Deux contrôles s'enchaînent à chaque requête :
> 1. **Le projet** du jeton détermine ce que l'utilisateur **voit** : sans rôle sur un projet, ses ressources sont invisibles (404). Seules les ressources explicitement partagées, comme le réseau `public`, sont visibles par tous.
> 2. **Le rôle** détermine ce qu'il peut **faire** : un `reader` lit, un `member` crée et modifie, un `admin` administre. Une action non autorisée par le rôle est refusée (403).

Pour chaque test, notez la commande, le résultat attendu, le résultat obtenu et, en cas d'erreur, le code HTTP.

L'identité utilisée est indiquée au début de chaque bloc (**[admin]**, **[candace]**, **[baron]**, **[ian]**). Choisissez-la avec `export OS_CLOUD=<profil>`, ou ajoutez `--os-cloud <profil>` à la commande.

### 3.1. Candace déploie l'infrastructure de l'équipe A

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

### 3.2. Baron tente d'accéder aux ressources de l'équipe A

Notez d'abord l'ID de `vm-candace` et celui de `net-candace` (affichés par candace), et remplacez-les dans les commandes suivantes.

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

**Q8.** Baron reçoit-il « accès refusé » (403) ou « introuvable » (404) ? Pourquoi est-il préférable, du point de vue sécurité, de répondre 404 ?

**Q9.** Quel réseau Baron voit-il alors qu'il ne l'a pas créé ? Quelle propriété de ce réseau l'explique (`openstack network show public`) ?

> [!NOTE]
> **Clés de lecture : qui peut voir un réseau ?**
> Dans la sortie de `openstack network show`, trois champs déterminent quels projets voient un réseau :
>
> | Champ | Signification |
> |---|---|
> | `project_id` | Projet **propriétaire** du réseau : ses membres le voient toujours |
> | `shared` | Si `True` : **tous les projets** peuvent voir le réseau et y brancher directement leurs VM |
> | `router:external` | Si `External` (ou `True`) : réseau **externe**, vers l'extérieur du cloud. **Tous les projets** le voient, pour y relier leurs routeurs et y prendre des IP flottantes, mais on n'y branche pas de VM directement |
>
> Pour retrouver le nom d'un projet à partir de son ID : `openstack project list`
>
> Rappel : ici, `public` est le **nom** du réseau, pas une propriété.

### 3.3. Ian, lecteur de l'équipe A

**[ian]**

```bash
export OS_CLOUD=ian
openstack server list
openstack server show vm-candace
openstack server stop vm-candace
openstack server create --flavor m1.tiny --image "$IMG" --network net-candace vm-ian
openstack network create net-ian
```

**Q10.** Quelles actions réussissent pour ian, et lesquelles échouent ? Relevez le message d'erreur obtenu. Comparez avec le code obtenu par baron en Q8 : pourquoi ian reçoit-il un refus (403) et non « introuvable » (404) ?

### 3.4. Ce qu'un membre ne peut pas faire

**[candace]**

```bash
export OS_CLOUD=candace
openstack user list
openstack project create team-c
openstack flavor create --vcpus 8 --ram 16384 --disk 100 m1.geant
openstack quota set --instances 100 team-a
```

**Q11.** Complétez le tableau ci-dessous à partir de vos tests. Pour une case non encore testée, lancez la commande indiquée avec l'identité correspondante.

**Préparation** : récupérez le nom de l'image CirrOS et les identifiants de `vm-candace` et `net-candace`. Les commandes du tableau utilisent les **ID** : une ressource d'un autre projet ne peut pas être retrouvée par son nom.

```bash
IMG=$(openstack --os-cloud admin image list -f value -c Name | grep -i cirros | head -1)
VM_ID=$(openstack --os-cloud candace server show vm-candace -f value -c id)
NET_ID=$(openstack --os-cloud candace network show net-candace -f value -c id)
echo "$IMG | $VM_ID | $NET_ID"
```

Dans les deux dernières colonnes, indiquez **Oui** si le résultat varie selon le **projet** de l'utilisateur (apparition de 404), ou selon son **rôle** (apparition de 403). Une action peut dépendre des deux.

`<profil>` désigne l'identité testée : admin, candace, baron ou ian.

| # | Action | Commande | admin | candace | baron | ian | Dépend du projet ? | Dépend du rôle ? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Voir `vm-candace` | `openstack server show $VM_ID` | | | | | | |
| 2 | Créer une VM dans son projet | `openstack server create --flavor m1.tiny --image "$IMG" --network shared --wait vm-test-<profil>` | | | | | | |
| 3 | Arrêter `vm-candace` | `openstack server stop $VM_ID` | | | | | | |
| 4 | Créer un réseau dans son projet | `openstack network create net-test-<profil>` | | | | | | |
| 5 | Voir le réseau `net-candace` | `openstack network show $NET_ID` | | | | | | |
| 6 | Lister les utilisateurs | `openstack user list` | | | | | | |
| 7 | Créer un flavor | `openstack flavor create --vcpus 1 --ram 256 --disk 1 test-flavor` | | | | | | |

> [!NOTE]
> **Ligne 2** : le réseau `shared`, créé par DevStack, est visible par tous les projets. Il permet de tester la création d'une VM avec chaque identité, sans réseau propre à chaque projet.
>
> **Ligne 3** : les quatre profils agissent sur la même VM. Après chaque arrêt réussi, démarrez-la de nouveau avant de tester le profil suivant. Sinon, un profil qui a le droit de l'arrêter obtiendra une erreur **409 Conflict** (VM déjà arrêtée), sans rapport avec ses droits :
>
> ```bash
> openstack --os-cloud candace server start $VM_ID
> ```

**Q12.** À partir du tableau, expliquez pourquoi baron obtient des 404, et ian des 403.

### 3.5. Le cas d'admin : voir tous les projets

Admin a le rôle `admin`, qui lui permet d'administrer tout le cloud. Voit-il pour autant les ressources de tous les projets ?

Lancez ces deux commandes et comparez :

```bash
openstack --os-cloud admin server list
openstack --os-cloud admin server list --all-projects
```

Affichez ensuite le projet auquel le jeton d'admin est lié :

```bash
openstack --os-cloud admin token issue -c project_id
openstack --os-cloud admin project list
```

**Q13.** `vm-candace` apparaît-elle dans les deux listes ? À quel projet le jeton d'admin est-il lié ? Expliquez pourquoi admin ne voit pas `vm-candace` sans `--all-projects`, alors qu'il a le rôle `admin`.

### 3.6. Nettoyage des ressources

Chaque identité supprime les ressources qu'elle a créées. Pour l'infrastructure de l'équipe A, respectez l'ordre inverse de sa création : d'abord la VM, puis le routeur, puis le réseau.

```bash
# Utiliser l'identité de Candace
export OS_CLOUD=candace

# Supprimer la VM de Candace et attendre la fin de la suppression, pour libérer son port sur net-candace
openstack server delete --wait vm-candace

# Détacher le sous-réseau du routeur, ce qui supprime l'interface du routeur (port 10.10.1.1 sur subnet-candace)
openstack router remove subnet router-candace subnet-candace

# Retirer la passerelle externe du routeur, ce qui supprime son port sur le réseau public
openstack router unset --external-gateway router-candace

# Supprimer le routeur, désormais sans interface ni passerelle
openstack router delete router-candace

# Supprimer le sous-réseau subnet-candace
openstack subnet delete subnet-candace

# Supprimer le réseau de Candace (son port DHCP est supprimé automatiquement)
openstack network delete net-candace

# Supprimer la VM de test créée par Candace sur le réseau shared
openstack server delete vm-test-candace

# Supprimer le réseau de test créé par Candace
openstack network delete net-test-candace

# Utiliser l'identité de Baron
export OS_CLOUD=baron

# Supprimer la VM de test créée par Baron dans son propre projet
openstack server delete vm-test-baron

# Supprimer le réseau de test créé par Baron dans son propre projet
openstack network delete net-test-baron

# Utiliser l'identité admin
export OS_CLOUD=admin

# Supprimer la VM de test créée par admin dans son propre projet
openstack server delete vm-test-admin

# Supprimer le réseau de test créé par admin dans son propre projet
openstack network delete net-test-admin

# Supprimer le flavor de test créé par admin
openstack flavor delete test-flavor
```

> [!TIP]
> **En cas de blocage**
> Si une suppression échoue ou si vous manquez de temps, le script `clean_lab02.sh` (disponible dans ce dossier) exécute toutes les commandes de nettoyage ci-dessus, dans le bon ordre :
>
> ```bash
> chmod +x clean_lab02.sh
> ./clean_lab02.sh
> ```
>
> Le script ignore les ressources déjà supprimées : vous pouvez le lancer même après un nettoyage partiel. Lisez son contenu avant de l'exécuter : chaque commande y est commentée.

### 3.7. Où sont définies les règles d'accès ?

- Vous avez constaté que candace peut créer une VM et ian non, et que seul admin peut utiliser `--all-projects`. Ces décisions ne sont pas prises par Keystone : Keystone dit seulement **qui** vous êtes et **quels rôles** vous avez.
- C'est **chaque service** (Nova, Neutron, Glance…) qui décide ensuite si vos rôles autorisent l'opération demandée, en consultant sa **politique d'accès** (*policy*).

| Notion | Signification |
| --- | --- |
| **Politique d'accès** (*policy*) | Ensemble de règles propre à chaque service : pour chaque opération de l'API, la condition à remplir |
| **Règle** | Une ligne de la forme `"nom": "condition"` |
| **Règles par défaut** | Écrites dans le code du service ; elles s'appliquent tant que l'administrateur ne les modifie pas |
| **`policy.yaml`** | Fichier (par exemple `/etc/nova/policy.yaml`) où l'administrateur peut remplacer certaines règles |

**Étape 1 : afficher les règles de deux opérations testées**

L'outil `oslopolicy-sample-generator` affiche toutes les règles par défaut d'un service. Il est installé dans l'environnement Python de DevStack : on l'appelle par son chemin complet.

```bash
POLICY=/opt/stack/data/venv/bin/oslopolicy-sample-generator

# Action : créer une VM
$POLICY --namespace nova | grep 'servers:create"'

# Action : lister les VM de tous les projets (--all-projects)
$POLICY --namespace nova | grep all_tenants
```

**Clés de lecture d'une règle**

| Élément | Signification |
| --- | --- |
| `#` en début de ligne | Valeur par défaut, active tant qu'un `policy.yaml` ne la remplace pas |
| `rule:<nom>` | Renvoi : « appliquer la règle nommée `<nom>` », définie ailleurs dans la politique |
| `role:<rôle>` | L'utilisateur doit avoir ce rôle |
| `project_id:%(project_id)s` | Le projet du jeton de l'utilisateur doit être celui de la ressource visée |
| `and` / `or` | Les deux conditions / l'une des deux |

**Étape 2 : décomposer la règle de création d'une VM**

À l'étape 1, la règle de création d'une VM affiche :

```
#"os_compute_api:servers:create": "rule:project_member_or_admin"
```

Elle ne contient aucun rôle : elle renvoie à une autre règle, `project_member_or_admin`. Pour savoir ce qu'elle exige vraiment, il faut afficher cette règle :

```bash
$POLICY --namespace nova | grep '^#"project_member_or_admin"'
```

Cette règle renvoie elle-même à deux autres règles. Affichez-les à leur tour :

```bash
$POLICY --namespace nova | grep -E '^#"(project_member_api|context_is_admin)"'
```

Vous obtenez cette fois des conditions de base (`role:…`, `project_id:…`) : la décomposition est terminée.

**Q14.**

a) Représentez la règle de création d'une VM sous forme d'arbre, de `os_compute_api:servers:create` jusqu'aux conditions de base. Traduisez-la en une phrase en français.

```
os_compute_api:servers:create
└── rule:
    ├── rule: ---
    │     └── role: ---
    └── OU rule: ---
          └── role: ---
```

b) À l'aide de votre arbre, complétez le tableau (Oui / Non), puis expliquez pourquoi candace peut créer une VM dans team-a, alors que ian (même projet, rôle `reader`) et baron (rôle `member`, mais projet team-b) ne le peuvent pas.

| Utilisateur | A le rôle `member` ? | Son jeton est-il lié au projet team-a ? | A le rôle `admin` ? | Création autorisée ? |
| --- | --- | --- | --- | --- |
| candace | | | | |
| ian | | | | |
| baron | | | | |

Pour chaque refus, indiquez **quelle condition** de l'arbre n'est pas remplie.

c) À l'étape 1, quelle règle protège `--all-projects` ? Expliquez pourquoi seul admin peut l'utiliser.
