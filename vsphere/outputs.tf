output "vm_name" {
  value = "${vsphere_virtual_machine.vm.name}.${var.vm_domain}"
}

output "vm_ip" {
  value = "${vsphere_virtual_machine.vm.default_ip_address}"
}

