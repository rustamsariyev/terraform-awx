variable "vsphere_user" {}
variable "vsphere_password" {}
variable "vsphere_server" {}
variable "vsphere_datacenter" {}
variable "vsphere_datastore" {}
variable "vsphere_resource_pool" {}
variable "vsphere_network" {}
variable "vm_template" {}
variable "vm_name" {}
variable "vm_vcpu" {}
variable "vm_memory" {}
variable "vm_mac_address" {}
variable "vm_disk1_size" {}
variable "vm_domain" {}
variable "vm_time_zone" {}
variable "account_id" {}
variable "docker_version" {}
variable "docker_edition" {}
variable "compose_version" {}
variable "ssh_user" {}

terraform {
  required_version = ">= 0.12"
}

provider "vsphere" {
  version        = "~> 1.12"
  user           = "${var.vsphere_user}"
  password       = "${var.vsphere_password}"
  vsphere_server = "${var.vsphere_server}"

  # if you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = "${var.vsphere_datacenter}"
}

data "vsphere_datastore" "datastore" {
  name          = "${var.vsphere_datastore}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.vsphere_resource_pool}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "${var.vsphere_network}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${var.vm_template}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

resource "vsphere_virtual_machine" "vm" {
  name             = "${var.vm_name}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"

  num_cpus = "${var.vm_vcpu}"
  memory   = "${var.vm_memory}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id     = "${data.vsphere_network.network.id}"
    adapter_type   = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
    use_static_mac = true
    mac_address    = "${var.vm_mac_address}"
  }

  disk {
    label            = "disk0"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "disk1"
    size             = "${var.vm_disk1_size}"
    eagerly_scrub    = false
    thin_provisioned = true
    unit_number      = 1
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${var.vm_name}"
        domain    = "${var.vm_domain}"
        time_zone = "${var.vm_time_zone}"
      }

      network_interface {}
    }
  }

  # Run commands with remote-exec over ssh
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.vm_name}.${var.vm_domain}",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get autoremove -y",
      "sudo mkdir -p /var/lib/docker/volumes",
      "sudo mkfs.ext4 /dev/sdb",
      "UUID=$(sudo blkid -o value -s UUID /dev/sdb)",
      "echo \"UUID=$UUID /var/lib/docker/volumes ext4 defaults 0 0\" | sudo tee -a /etc/fstab",
      "sudo mount -a",
      "sudo groupadd --gid ${var.account_id} docker",
      "sudo adduser --gid ${var.account_id} --uid ${var.account_id} --disabled-password -gecos \"docker\" docker",
      "sudo chmod 0700 /var/lib/docker/volumes",
      "sudo chown -R root:root /var/lib/docker/volumes",
      "sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu `lsb_release -cs` stable\"",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      #"sudo apt-get install -y docker-${var.docker_edition}=${var.docker_version}~${var.docker_edition}-0~ubuntu-`lsb_release -cs`",
      #"sudo apt-get install -y docker-${var.docker_edition}=${var.docker_version}~${var.docker_edition}-0~ubuntu",
      "sudo apt-get install -y docker-${var.docker_edition}=5:${var.docker_version}~3-0~ubuntu-`lsb_release -cs`",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ansible",
      "sudo curl -L https://github.com/docker/compose/releases/download/${var.compose_version}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo apt-add-repository -y ppa:ansible/ansible",
      "sudo apt-get update",
      "sudo apt-get install -y ansible",
      "sudo apt-get install -y python-pip",
      "pip install --user docker",
      "pip install --user docker-compose",      
      "pip install --upgrade ansible-tower-cli",
      "git clone https://github.com/ansible/awx.git",
      "cd awx/installer",
      "sudo ansible-playbook -i inventory install.yml"
    ]
  }

  connection {
    type        = "ssh"
    host        = "${self.default_ip_address}"
    private_key = "${file("~/.ssh/id_rsa")}"
    user        = "${var.ssh_user}"
    agent       = false
  }

  # provisioner "local-exec" {
  #   command = "ansible-galaxy --force install -r ../ansible/requirements.yml"
  # }
  #
  # provisioner "local-exec" {
  #   command = "ansible-playbook --ssh-extra-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' -u ${var.ssh_user} --private-key ~/.ssh/id_rsa -i ../ansible/inventory ../ansible/playbook.yml"
  # }
}
