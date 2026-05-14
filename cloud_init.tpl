#cloud-config

# Métadonnées et Utilisateur
hostname: ${hostname}
manage_etc_hosts: true

users:
  - name: kube
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_key}
 
# --- 1. Installation des Paquets de Base (Natif) ---
package_update: true
package_upgrade: true

packages:
  # Outils essentiels pour le débogage et Ansible
  - curl
  - gnupg
  - net-tools
  - vim

# --- 2. Configuration Réseau Statique (Écriture du Fichier) ---
write_files: 
  - path: /etc/netplan/01-static.yaml 
    permissions: '0644' 
    content: | 
      network: 
        version: 2 
        ethernets: 
          ens3: 
            dhcp4: false 
            addresses:
              - ${ip}/24 
            routes: 
              - to: default 
                via: ${gateway} 
            nameservers: 
              addresses: [${dns}] 
              
# --- 3. Commandes Séquentielles Critiques (Minimaliste runcmd) ---
runcmd:
  # CORRECTION CRITIQUE DU RÉSEAU : Supprimer le fichier DHCP conflictuel et appliquer l'IP statique
  - rm -f /etc/netplan/50-cloud-init.yaml
  - netplan apply
  
  # # Configuration critique pour Kubernetes (doit être fait au boot)
  # # Modules kernel
  # - echo "overlay" > /etc/modules-load.d/containerd.conf
  # - echo "br_netfilter" >> /etc/modules-load.d/containerd.conf
  # - modprobe overlay
  # - modprobe br_netfilter
  
  # # Paramètres sysctl
  # - echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/k8s.conf
  # - echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.d/k8s.conf
  # - echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.d/k8s.conf
  # - sysctl --system