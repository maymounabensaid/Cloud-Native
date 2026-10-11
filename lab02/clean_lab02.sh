#!/bin/bash
# =============================================================
# clean_lab02.sh — Nettoyage des ressources de la partie 3 (TP2)
# Ordre : VM -> routeur -> sous-réseau -> réseau
# Le script continue même si une ressource est déjà supprimée.
# =============================================================

# Exécute une commande et affiche un message si elle échoue
run() {
    echo "-> $*"
    "$@" || echo "   (ignoré : ressource absente ou déjà supprimée)"
}

# -------------------------------------------------------------
echo "=== Nettoyage des ressources de Candace ==="
# Utiliser l'identité de Candace (membre du projet de l'équipe A)
export OS_CLOUD=candace

# Supprimer la VM de Candace et attendre la fin de la suppression, pour libérer son port sur net-candace
run openstack server delete --wait vm-candace

# Détacher le sous-réseau du routeur, ce qui supprime l'interface du routeur (port 10.10.1.1)
run openstack router remove subnet router-candace subnet-candace

# Retirer la passerelle externe du routeur, ce qui supprime son port sur le réseau public
run openstack router unset --external-gateway router-candace

# Supprimer le routeur, désormais sans interface ni passerelle
run openstack router delete router-candace

# Supprimer le sous-réseau 10.10.1.0/24
run openstack subnet delete subnet-candace

# Supprimer le réseau de Candace (son port DHCP est supprimé automatiquement)
run openstack network delete net-candace

# Supprimer la VM de test créée par Candace sur le réseau shared (ligne 2 du tableau Q11)
run openstack server delete --wait vm-test-candace

# Supprimer le réseau de test créé par Candace (ligne 4 du tableau Q11)
run openstack network delete net-test-candace

# -------------------------------------------------------------
echo "=== Nettoyage des ressources de Baron ==="
# Utiliser l'identité de Baron (membre d'un autre projet)
export OS_CLOUD=baron

# Supprimer la VM de test créée par Baron dans son propre projet
run openstack server delete --wait vm-test-baron

# Supprimer le réseau de test créé par Baron dans son propre projet
run openstack network delete net-test-baron

# -------------------------------------------------------------
echo "=== Nettoyage des ressources d'admin ==="
# Utiliser l'identité admin
export OS_CLOUD=admin

# Supprimer la VM de test créée par admin dans son propre projet
run openstack server delete --wait vm-test-admin

# Supprimer le réseau de test créé par admin dans son propre projet
run openstack network delete net-test-admin

# Supprimer le flavor de test créé par admin (ligne 7 du tableau Q11)
run openstack flavor delete test-flavor

# -------------------------------------------------------------
echo "=== Vérification finale (admin) ==="
openstack server list --all-projects
openstack network list
openstack router list

echo "Nettoyage terminé."
