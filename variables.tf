variable "ssh_pub_path" {
  description = "Chemin vers la clé publique SSH injectée dans les VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vm_names" {
  description = "Noms des VMs du cluster"
  type        = list(string)
  default     = ["k8s-master", "k8s-worker-1", "k8s-worker-2"]
}

variable "memory_mb" {
  description = "RAM par VM en MiB (multiplié par 1024 pour libvirt qui attend des KiB)"
  type        = number
  default     = 4096
}

variable "vcpu" {
  description = "Nombre de vCPUs par VM"
  type        = number
  default     = 2
}

variable "image_path" {
  description = "Chemin local vers l'image QCOW2 Ubuntu 24.04"
  type        = string
  default     = "/home/p-g/kvm/noble-server-cloudimg-amd64.img"
}

variable "disk_size_gb" {
  description = "Taille du disque de chaque VM en Go"
  type        = number
  default     = 50
}

variable "pool_name" {
  description = "Nom du pool de stockage libvirt"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Nom du réseau libvirt (bridge virbr0)"
  type        = string
  default     = "default"
}

variable "vm_ips" {
  description = "Adresses IP statiques des VMs (ordre : master, worker-1, worker-2)"
  type        = list(string)
  default     = [
    "192.168.122.10",
    "192.168.122.11",
    "192.168.122.12",
  ]
}

variable "gateway" {
  description = "Passerelle réseau (virbr0)"
  type        = string
  default     = "192.168.122.1"
}

variable "dns" {
  description = "Serveur DNS"
  type        = string
  default     = "192.168.122.1"
}
