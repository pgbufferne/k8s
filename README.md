# Projet d'Infrastructure Kubernetes (K8s)

Ce projet déploie un cluster Kubernetes auto-géré sur des machines virtuelles (VMs) en utilisant **Terraform** pour l'infrastructure et **Ansible** pour le provisionnement logiciel.

Le déploiement est entièrement piloté par un `terraform apply` unique : Terraform crée les VMs, génère l'inventaire Ansible, puis déclenche automatiquement le playbook.

---

## Stack Technique

| Composant | Rôle | Version |
| :--- | :--- | :--- |
| **Libvirt / KVM** | Hyperviseur (provider `dmacvicar/libvirt`) | `0.9.8` |
| **Terraform** | Infrastructure as Code | `>= 1.0.0` |
| **Ubuntu** | Système d'exploitation des VMs | `24.04 LTS (Noble Numbat)` |
| **Ansible** | Configuration Management (rôles) | `>= 2.10.0` |
| **Containerd** | Moteur de conteneur | Dernière version stable apt |
| **Kubernetes** | Orchestration de conteneurs | `v1.36.x` |
| **Calico** | CNI — Communication inter-Pods (via Tigera Operator Helm) | `v3.29.1` |
| **Helm** | Gestionnaire de paquets Kubernetes | `v3.21.2` |
| **local-path-provisioner** | StorageClass par défaut (PV dynamiques hostPath) | `0.0.37` |

---

## Architecture du Cluster

3 VMs sont créées et configurées pour former un cluster Kubernetes minimal :

| Rôle | Nom VM | Adresse IP | Services |
| :--- | :--- | :--- | :--- |
| **Master** | `k8s-master` | `192.168.122.10` | `kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler`, Helm, Calico, local-path-provisioner |
| **Worker** | `k8s-worker-1` | `192.168.122.11` | `kubelet`, `kube-proxy`, `containerd` |
| **Worker** | `k8s-worker-2` | `192.168.122.12` | `kubelet`, `kube-proxy`, `containerd` |

- Réseau hôte : `192.168.122.0/24` (bridge `virbr0` Libvirt/NAT)
- Pod network CIDR : `192.168.0.0/16`
- Utilisateur SSH dans les VMs : `kube` (sudo sans mot de passe)

---

## Structure du Projet

```
.
├── main.tf                          # Ressources Terraform (VMs, volumes, cloud-init)
├── variables.tf                     # Variables Terraform
├── cloud_init.tpl                   # Template cloud-init (réseau statique, user kube)
└── ansible/
    ├── site.yml                     # Playbook principal (4 phases)
    ├── inventory.ini                # Généré automatiquement par Terraform
    ├── group_vars/
    │   └── all.yml                  # Variables globales (versions K8s, Calico, Helm)
    └── roles/
        ├── common/                  # Prérequis communs à tous les nœuds
        │   ├── tasks/main.yml       # Swap, modules kernel, sysctl, containerd, kubeadm
        │   └── handlers/main.yml    # Restart containerd
        ├── master/                  # Initialisation du master uniquement
        │   └── tasks/main.yml       # Helm, kubeadm init, Calico via Helm, token join
        └── worker/                  # Jonction des workers
            └── tasks/main.yml       # kubeadm join
```

---

## Prérequis

Sur la machine hôte avant tout déploiement :

1. **Terraform** `>= 1.0.0`
2. **Ansible** `>= 2.10.0` avec les collections :
   ```bash
   ansible-galaxy collection install kubernetes.core community.general
   ```
3. **Libvirt / KVM** avec le réseau NAT par défaut actif (`virbr0`, plage `192.168.122.0/24`) :
   ```bash
   virsh net-list --all   # "default" doit être "active"
   virsh net-start default
   ```
4. **Une image Ubuntu 24.04 cloud QCOW2** agrandie à 50 Go minimum (voir section suivante).
5. **Une paire de clés SSH ED25519** — le chemin vers la clé publique est configuré dans `variables.tf` (`ssh_pub_path`).

### Préparer l'image disque

Téléchargez l'image cloud Ubuntu 24.04 et placez-la à l'emplacement défini par `image_path` dans `variables.tf` :

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

> Aucun redimensionnement préalable nécessaire. Terraform crée les disques VM en COW avec la taille définie par `disk_size_gb` (50 Go par défaut), et cloud-init étend automatiquement le système de fichiers au premier boot.

### Stockage disque — mode COW

Terraform crée **1 volume de base** (copie de l'image source) et **3 disques VM en Copy-on-Write** via `backing_store`. Chaque disque VM ne stocke que ses différences par rapport à l'image de base :

- Sans COW : **3 × 50 Go = 150 Go**
- Avec COW : **1 × 50 Go + 3 × delta ≈ 55-60 Go** selon l'utilisation

---

## Configuration

### `variables.tf` — Paramètres principaux

| Variable | Défaut | Description |
| :--- | :--- | :--- |
| `image_path` | `/home/p-g/kvm/noble-server-cloudimg-amd64.img` | Chemin local vers l'image QCOW2 source |
| `ssh_pub_path` | `~/.ssh/id_ed25519.pub` | Clé publique SSH injectée dans les VMs |
| `pool_name` | `default` | Pool de stockage Libvirt |
| `network_name` | `default` | Réseau Libvirt (`virbr0`) |
| `vm_names` | `["k8s-master", "k8s-worker-1", "k8s-worker-2"]` | Noms des VMs |
| `vm_ips` | `["192.168.122.10", ".11", ".12"]` | IPs statiques (ordre : master, workers) |
| `memory_mb` | `4096` | RAM par VM en MiB |
| `vcpu` | `2` | CPUs par VM |
| `disk_size_gb` | `50` | Taille du disque de chaque VM en Go |
| `gateway` | `192.168.122.1` | Passerelle réseau |
| `dns` | `192.168.122.1` | Serveur DNS |

### `ansible/group_vars/all.yml` — Versions logicielles

```yaml
k8s_version: "1.36"
pod_network_cidr: "192.168.0.0/16"
calico_ver: "v3.29.1"
helm_version: "v3.21.2"
local_path_provisioner_ver: "0.0.37"
```

---

## Déploiement

### 1. Initialisation

```bash
terraform init
```

### 2. Vérification du plan

```bash
terraform plan -out=tfplan
```

### 3. Déploiement complet

```bash
terraform apply tfplan
```

Terraform enchaîne automatiquement :

1. Création du volume de base (copie de l'image source dans le pool)
2. Création des 3 disques VM en COW (`backing_store` sur le volume de base)
3. Génération et upload des ISOs cloud-init (réseau statique, user `kube`)
4. Démarrage des 3 VMs KVM (firmware EFI, Secure Boot désactivé, CPU host-passthrough)
5. Génération de `ansible/inventory.ini`
6. Exécution du playbook Ansible :
   - **Phase 0** — Attente SSH sur tous les nœuds (timeout 5 min)
   - **Phase 1** — Configuration commune : swap, modules kernel, sysctl, containerd, kubeadm/kubelet/kubectl
   - **Phase 2** — Master : Helm, `kubeadm init`, Calico via Helm, local-path-provisioner via Helm (StorageClass par défaut), génération du token join
   - **Phase 3** — Workers : `kubeadm join`

### 4. Destruction

```bash
terraform destroy
```

> En cas d'interruption partielle laissant des volumes orphelins dans le pool, nettoyez manuellement avant de relancer :
> ```bash
> virsh vol-delete cloudinit-k8s-master.iso   --pool default
> virsh vol-delete cloudinit-k8s-worker-1.iso --pool default
> virsh vol-delete cloudinit-k8s-worker-2.iso --pool default
> ```

---

## Vérification post-déploiement

```bash
ssh kube@192.168.122.10

# État du cluster
kubectl get nodes -o wide

# Tous les pods système (Calico et local-path-provisioner doivent être Running)
kubectl get pods -A

# Vérifier Calico
kubectl get pods -n calico-system
kubectl get pods -n tigera-operator

# Vérifier la StorageClass par défaut
kubectl get storageclass
```

Résultat attendu pour la StorageClass :

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

Résultat attendu :

```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   Xm    v1.36.x
k8s-worker-1   Ready    <none>          Xm    v1.36.x
k8s-worker-2   Ready    <none>          Xm    v1.36.x
```

---

## Notes techniques

**Disques COW via `backing_store`** — Les disques VM référencent l'image de base comme backing store QCOW2. Chaque VM ne stocke que ses écritures différentielles, économisant ~100 Go par rapport à 3 copies indépendantes.

**Firmware EFI + Secure Boot désactivé** — Les VMs démarrent en mode EFI (`firmware = "efi"`). Secure Boot est explicitement désactivé (`enrolled-keys: no`, `secure-boot: no`) car libvirt 10+ enrôle par défaut les clés Microsoft qui rejettent les kernels Linux non signés, bloquant le chargement des modules virtio. L'ordre alphabétique des features est obligatoire (contrainte du provider 0.9.x).

**CPU host-passthrough** — Expose tous les flags CPU de l'hôte aux VMs (AES-NI, AVX, SSE4...). Sans ça, libvirt utilise le profil `qemu64` minimaliste qui peut bloquer le chargement de modules crypto sur les kernels récents.

**Calico installé via Helm uniquement** — Le manifest `tigera-operator.yaml` n'est jamais appliqué manuellement. Helm gère l'intégralité des ressources avec les labels `app.kubernetes.io/managed-by: Helm` requis. Appliquer le manifest manuellement avant Helm provoquerait une erreur d'ownership sur le `ServiceAccount tigera-operator`.

**Volumes avec `lifecycle { ignore_changes = [create] }`** — Évite l'erreur "volume existe déjà" lors d'un `terraform apply` après une destruction partielle.

**Réseau statique via cloud-init** — Le fichier `/etc/netplan/50-cloud-init.yaml` (DHCP) est supprimé au boot et remplacé par `/etc/netplan/01-static.yaml` avec l'IP fixe définie dans `variables.tf`.

**StorageClass par défaut via local-path-provisioner** — Installé via Helm (chart `containeroo/local-path-provisioner`). Crée dynamiquement des PersistentVolumes en stockage local sur le nœud qui schedule le pod (`/opt/local-path-provisioner`). Défini comme StorageClass par défaut (`defaultClass: true`). Limitation : les données ne suivent pas si le pod est replanifié sur un autre nœud — adapté pour un cluster de lab, pas pour de la production HA.

**Helm installé depuis GitHub Releases** — Aucun dépôt apt tiers. Le binaire officiel est téléchargé depuis `get.helm.sh`, extrait et copié dans `/usr/local/bin/helm`.

**Mémoire en KiB** — Le provider libvirt 0.9.x attend la mémoire en KiB sans `memory_unit`. La variable `memory_mb` est multipliée par 1024 dans `main.tf`.
