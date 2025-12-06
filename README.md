# 🚀 Projet d'Infrastructure Kubernetes (K8s)

Ce projet déploie un cluster Kubernetes auto-géré sur des machines virtuelles (VMs) en utilisant **Terraform** pour l'infrastructure et **Ansible** pour le provisionnement du logiciel (Kubernetes et Helm).

## 💡 Stack Technique

| Composant | Rôle | Version / Détails |
| :--- | :--- | :--- |
| **Virtualisation** | Hyperviseur de Base | **Libvirt / KVM** (via `dmacvicar/libvirt` provider) |
| **IaaS / IaC** | Infrastructure as Code | Terraform |
| **Système d'exploitation**| Base des VMs | Ubuntu 24.04 LTS (Noble Numbat) |
| **Orchestration** | Configuration Management | Ansible (avec structure par Rôles) |
| **Conteneurisation** | Moteur de conteneur | Containerd (avec SystemdCgroup=True) |
| **Kubernetes** | Moteur d'orchestration | v1.32.x |
| **Réseau (CNI)** | Communication inter-Pods | Calico (via Tigera Operator) |
| **Gestionnaire de paquets**| Déploiement d'applications K8s | Helm |

---

## 🎯 Architecture du Cluster

Le déploiement crée 3 nœuds configurés pour former un cluster Kubernetes minimal :

| Rôle Ansible | Nom de la VM | Adresse IP (Définie par `vm_ips`) | Services principaux |
| :--- | :--- | :--- | :--- |
| **Master** | `k8s-master` | `192.168.122.10` | `kube-apiserver`, `kube-controller-manager`, `etcd`, **Helm** |
| **Worker** | `k8s-worker-1` | `192.168.122.11` | `kubelet`, `kube-proxy`, `containerd` |
| **Worker** | `k8s-worker-2` | `192.168.122.12` | `kubelet`, `kube-proxy`, `containerd` |

L'utilisateur de connexion aux VMs est **`kube`**.
Il convient de modifier le chemin vers la clé publique dans variable ssh_pub_path du fichier variable.tf
---

## ⚙️ Prérequis

Avant de lancer le déploiement, assurez-vous que les outils suivants sont installés et configurés sur votre machine hôte :

1.  **Terraform** (`>= 1.0.0`)
2.  **Ansible** (`>= 2.10.0`)
3.  **Libvirt** (avec le bridge réseau `virbr0` ou un réseau équivalent gérant la plage `192.168.122.0/24`).
4.  **Clés SSH :** Votre clé publique SSH doit être configurée pour être injectée dans les VMs (via `cloud-init`) pour permettre la connexion par Ansible sous l'utilisateur `kube`.

---

## 💻 Configuration Spécifique Libvirt

Ce projet repose sur l'adressage IP statique géré côté Terraform/Libvirt via `cloud-init` et l'inventaire Ansible.

### Taille du Disque (Essentiel) ⚠️

L'image cloud par défaut est insuffisante pour un cluster K8s. **Toutes les VMs doivent utiliser une image source d'une taille minimale de 50 Go**.

* **Action Préalable Obligatoire :** Vous devez agrandir l'image QCOW2 avant de lancer `terraform apply`.
* **Commande pour Agrandir le Disque Source :**
    ```bash
    # Augmenter la taille du fichier QCOW2 à 50 Gigaoctets
    qemu-img resize noble-server-cloudimg-amd64.img 50G
    ```
    > **Note :** Le code Terraform s'appuiera sur cette image de base, puis le `cloud-init` se chargera de l'expansion du système de fichiers interne au premier boot.

### Réseau et Adressage

* **Réseau :** Les adresses IP des VMs sont fixes (`192.168.122.10-12`). Elles doivent correspondre à la plage de votre réseau **Libvirt/NAT par défaut** (`virbr0`).
* **Inventaire :** Terraform génère dynamiquement le fichier `ansible/hosts.ini` en utilisant les IPs définies dans `variables.tf`.

---

## 🛠️ Déploiement

Le déploiement est piloté entièrement par Terraform.

### 1. Initialisation du Projet

Placez-vous dans le répertoire `terraform/` et initialisez le projet :

```bash
cd terraform/
terraform init