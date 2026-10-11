#!/bin/bash
# =============================================================
# clean_lab02.sh — Cleanup of the Part 3 resources (Lab 02)
# Order: VM -> router -> subnet -> network
# The script keeps going even if a resource is already deleted.
# =============================================================

# Run a command and print a message if it fails
run() {
    echo "-> $*"
    "$@" || echo "   (skipped: resource missing or already deleted)"
}

# -------------------------------------------------------------
echo "=== Cleaning up Candace's resources ==="
# Use Candace's identity (member of team A's project)
export OS_CLOUD=candace

# Delete Candace's VM and wait for the deletion to finish, to free its port on net-candace
run openstack server delete --wait vm-candace

# Detach the subnet from the router, which deletes the router's interface (port 10.10.1.1)
run openstack router remove subnet router-candace subnet-candace

# Remove the router's external gateway, which deletes its port on the public network
run openstack router unset --external-gateway router-candace

# Delete the router, now without any interface or gateway
run openstack router delete router-candace

# Delete the 10.10.1.0/24 subnet
run openstack subnet delete subnet-candace

# Delete Candace's network (its DHCP port is deleted automatically)
run openstack network delete net-candace

# Delete the test VM created by Candace on the shared network (row 2 of the Q11 table)
run openstack server delete --wait vm-test-candace

# Delete the test network created by Candace (row 4 of the Q11 table)
run openstack network delete net-test-candace

# -------------------------------------------------------------
echo "=== Cleaning up Baron's resources ==="
# Use Baron's identity (member of another project)
export OS_CLOUD=baron

# Delete the test VM created by Baron in his own project
run openstack server delete --wait vm-test-baron

# Delete the test network created by Baron in his own project
run openstack network delete net-test-baron

# -------------------------------------------------------------
echo "=== Cleaning up admin's resources ==="
# Use the admin identity
export OS_CLOUD=admin

# Delete the test VM created by admin in its own project
run openstack server delete --wait vm-test-admin

# Delete the test network created by admin in its own project
run openstack network delete net-test-admin

# Delete the test flavor created by admin (row 7 of the Q11 table)
run openstack flavor delete test-flavor

# -------------------------------------------------------------
echo "=== Final check (admin) ==="
openstack server list --all-projects
openstack network list
openstack router list

echo "Cleanup complete."
