poorspray: The poor man kubespray
----------------------------------

1. install ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
2. set your inventory in invetory.ini
3. ansible-playbook -i inventory.ini reset_master.yml (just in case)
4. ansible-playbook -i inventory.ini install_stuff.yml
5. ansible-playbook -i inventory.ini set_master.yml
6. ansible-playbook -i inventory.ini set_nodes.yml

set_nodes.yml will change the hostnames to the inventory host names - so run it on your own risk



mlnx
=====
reset ip tables

ansible-playbook -i inventory.ini set_master.yml
ansible-playbook -i inventory.ini set_nodes.yml
ansible-playbook -i inventory.ini delete_proxy_ds.yml
ovn
rescale dns
sriov
multus



