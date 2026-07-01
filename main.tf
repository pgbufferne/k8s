terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.8"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# ============================
# IMAGE DE BASE (partagée entre toutes les VMs)
# ============================
resource "libvirt_volume" "base" {
  name = "ubuntu-24.04-base.qcow2"
  pool = var.pool_name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "file://${var.image_path}"
    }
  }

  # Évite l'erreur "volume existe déjà" en cas de re-apply sans destroy
  lifecycle {
    ignore_changes = [create]
  }
}

# ============================
# DISQUES VM — Clone COW (Copy-on-Write)
# Chaque VM ne stocke que ses différences vs l'image de base.
# Résultat : 1×50 Go (base) + 3× quelques Mo (deltas) au lieu de 3×50 Go.
# ============================
resource "libvirt_volume" "vm_disk" {
  count    = length(var.vm_names)
  name     = "${var.vm_names[count.index]}.qcow2"
  pool     = var.pool_name
  capacity = var.disk_size_gb * 1024 * 1024 * 1024  # Go → octets

  target = {
    format = { type = "qcow2" }
  }

  # Référence l'image de base comme backing store (COW)
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }

  depends_on = [libvirt_volume.base]
}

# ============================
# CLOUD-INIT : génération des ISOs de configuration
# ============================
resource "libvirt_cloudinit_disk" "cloudinit" {
  count = length(var.vm_names)
  name  = "cloudinit-${var.vm_names[count.index]}"

  user_data = templatefile("${path.module}/cloud_init.tpl", {
    hostname = var.vm_names[count.index]
    ssh_key  = file(var.ssh_pub_path)
    ip       = var.vm_ips[count.index]
    gateway  = var.gateway
    dns      = var.dns
  })

  # meta_data obligatoire en 0.9.x
  meta_data = yamlencode({
    "instance-id"    = var.vm_names[count.index]
    "local-hostname" = var.vm_names[count.index]
  })
}

# ============================
# CLOUD-INIT : upload des ISOs dans le pool
# ============================
resource "libvirt_volume" "cloudinit_iso" {
  count = length(var.vm_names)
  name  = "cloudinit-${var.vm_names[count.index]}.iso"
  pool  = var.pool_name

  create = {
    content = {
      url = libvirt_cloudinit_disk.cloudinit[count.index].path
    }
  }

  # Évite l'erreur "volume existe déjà" en cas de re-apply sans destroy
  lifecycle {
    ignore_changes = [create]
  }
}

# ============================
# VMs K8S (MASTER + WORKERS)
# ============================
resource "libvirt_domain" "k8s_vm" {
  count  = length(var.vm_names)
  name   = var.vm_names[count.index]
  type   = "kvm"
  memory = var.memory_mb * 1024  # MiB → KiB (attendu par libvirt 0.9.x)
  vcpu   = var.vcpu

  # host-passthrough expose tous les flags CPU de l'hôte (AES-NI, AVX...).
  # Sans ça, libvirt utilise qemu64 qui n'expose que x86_64 minimal —
  # les kernels récents peuvent bloquer au chargement des modules crypto.
  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    # Désactive Secure Boot : libvirt 10+ enrôle par défaut les clés
    # Microsoft (OVMF_CODE_4M.ms.fd) qui rejettent les kernels non signés.
    # Les images cloud Linux démarrent puis se bloquent à /init faute
    # de modules virtio. Ordre alphabétique OBLIGATOIRE (provider 0.9.x
    # compare strictement et lève "Provider produced inconsistent result").
    firmware_info = {
      features = [
        { enabled = "no", name = "enrolled-keys" },
        { enabled = "no", name = "secure-boot" },
      ]
    }
  }

  features = {
    acpi = true
  }

  devices = {
    disks = [
      # Disque OS (COW qcow2)
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = var.pool_name
            volume = libvirt_volume.vm_disk[count.index].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      # CDROM Cloud-Init
      {
        device = "cdrom"
        driver = {
          name = "qemu"
          type = "raw"
        }
        source = {
          volume = {
            pool   = var.pool_name
            volume = libvirt_volume.cloudinit_iso[count.index].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = { network = var.network_name }
        }
        wait_for_ip = {
          timeout = 300
          source  = "any"
        }
      }
    ]

    # Console série — indispensable pour debug (virsh console)
    serials = [
      {
        type = "pty"
        target = {
          port = 0
          type = "isa-serial"
        }
      }
    ]

    graphics = [
      {
        spice = {
          autoport = "yes"
        }
      }
    ]
  }

  running = true
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
# INVENTAIRE ANSIBLE (généré dynamiquement)
# ============================
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content  = <<-EOT
    [all:vars]
    ansible_user=kube
    ansible_connection=ssh
    ansible_host_key_checking=False

    [kube_master]
    ${var.vm_names[0]} ansible_host=${var.vm_ips[0]}

    [kube_node]
    %{for i in range(1, length(var.vm_names))}
    ${var.vm_names[i]} ansible_host=${var.vm_ips[i]}
    %{endfor}

    [kube_cluster:children]
    kube_master
    kube_node
  EOT

  depends_on = [libvirt_domain.k8s_vm]
}

# ============================
# PROVISIONING ANSIBLE
# ============================
resource "null_resource" "ansible_provisioning" {
  depends_on = [local_file.ansible_inventory]

  triggers = {
    inventory = local_file.ansible_inventory.content
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/site.yml"
  }
}
