terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# ============================
# STORAGE POOL
# ============================
resource "libvirt_pool" "k8s" {
  name = "k8s-pool"
  type = "dir"
  path = "/home/p-g/kvm-k8s"
}

# ============================
# VM DISKS (50GB IMAGE PREPARED)
# ============================
resource "libvirt_volume" "ubuntu" {
  count  = length(var.vm_names)
  name   = "${var.vm_names[count.index]}.qcow2"
  pool   = libvirt_pool.k8s.name
  source = var.image_path       # <-- IMAGE 50Go locale
  format = "qcow2"
}


# ============================
# CLOUD-INIT TEMPLATES 
# ============================
# Crée un template Cloud-Init pour chaque VM (Master à l'index 0, Workers après)
data "template_file" "cloud_init" {
  count    = length(var.vm_names)
  template = file("${path.module}/cloud_init.tpl") # Fichier unique
  vars = {
    hostname = var.vm_names[count.index]
    ssh_key  = file(var.ssh_pub_path)
    ip       = var.vm_ips[count.index]
    gateway  = var.gateway
    dns      = var.dns
  }
}

# ============================
# CLOUD-INIT DISKS 
# ============================
# Crée un ISO d'initialisation pour chaque VM
resource "libvirt_cloudinit_disk" "cloudinit" {
  count     = length(var.vm_names)
  name      = "cloudinit-${var.vm_names[count.index]}.iso"
  user_data = data.template_file.cloud_init[count.index].rendered
}

# ---------------------------------------------
# CONSOLIDATION DES DOMAINES LIBVIRT
# ---------------------------------------------

# ============================
# K8S VMs (MASTER ET WORKERS)
# ============================
resource "libvirt_domain" "k8s_vm" {
  count = length(var.vm_names)

  name   = var.vm_names[count.index] # Master à l'index 0
  memory = var.memory_mb
  vcpu   = var.vcpu

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = libvirt_volume.ubuntu[count.index].id
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit[count.index].id

  graphics { type = "spice" }
}

# ============================
# OUTPUTS
# ============================
output "master_ip" {
  value = var.vm_ips[0]
}

output "worker_ips" {
  value = slice(var.vm_ips, 1, length(var.vm_ips))
}


# ============================
# CREATION DE L'INVENTAIRE ANSIBLE
# ============================
resource "local_file" "ansible_inventory" {
  # Chemin vers le dossier Ansible
  filename = "ansible/inventory.ini"
  
  # Le contenu du fichier
  content = <<-EOT
[all:vars]
ansible_user=kube
ansible_connection=ssh
ansible_host_key_checking=False

[kube_master]
${var.vm_names[0]} ansible_host=${var.vm_ips[0]}

[kube_node]
${var.vm_names[1]} ansible_host=${var.vm_ips[1]}
${var.vm_names[2]} ansible_host=${var.vm_ips[2]}

[kube_cluster:children]
kube_master
kube_node
EOT

  # Assurez-vous d'ajouter une dépendance aux ressources qui créent les VMs
  # Exemple si vous utilisez 'libvirt_domain' :
  # depends_on = [
  #   libvirt_domain.master,
  #   libvirt_domain.workers
  # ]
}

resource "null_resource" "ansible_provisioning" {
  # Ce bloc déclenche Ansible APRÈS que l'inventaire soit écrit
  depends_on = [
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = "ansible-playbook -i ansible/inventory.ini ansible/site.yml"
  }
}