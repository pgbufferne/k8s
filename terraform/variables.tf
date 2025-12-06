variable "user" {
  description = "Nom d'utilisateur hôte"
  type        = string
  default     = "p-g"
}

variable "ssh_pub_path" {
  description = "Clé publique SSH"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "vm_names" {
  type = list(string)
  default = [
    "k8s-master",
    "k8s-worker-1",
    "k8s-worker-2"
  ]
}

variable "memory_mb" { default = 4096 }
variable "vcpu"      { default = 2 }

variable "image_path" {
  description = "Chemin image QCOW2 Ubuntu 24"
  default     = "/home/p-g/kvm/noble-server-cloudimg-amd64.img"
}

variable "vm_ips" {
  type = list(string)
  default = [
    "192.168.122.10", # master
    "192.168.122.11", # worker
    "192.168.122.12"  # worker
  ]
}

variable "gateway" { default = "192.168.122.1" }
variable "dns"     { default = "192.168.122.1" }

