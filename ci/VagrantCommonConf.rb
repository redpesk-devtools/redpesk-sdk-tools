# -*- mode: ruby -*-
# vi: set ft=ruby :
#
Vagrant.configure("2") do |config|

  config.vm.provider "virtualbox" do |vb|
  #   # Display the VirtualBox GUI when booting the machine
  #   vb.gui = true
  #
  #   # Customize the amount of memory on the VM:
    vb.memory = "2048"
    vb.customize ["modifyvm", :id, '--nested-hw-virt','on']

  #   # disable USB 2.0 support in VirtualBox
    vb.customize ["modifyvm", :id, "--usb", "on"]
    vb.customize ["modifyvm", :id, "--usbehci", "off"]
  end

  config.vm.synced_folder "../../", "/home/vagrant/ci"
  
  #localbuilder CI
  config.vm.provision  "install-redpesk-localbuilder", type: "file" , source: "../../../install-redpesk-localbuilder.sh", destination: "/home/vagrant/"
  config.vm.provision  "test-localbuilder-script"    , type: "shell", path: "../../test_localbuilder.sh", upload_path: "/home/vagrant/test_localbuilder.sh", privileged: false
  
  #SDK CI
  config.vm.provision  "install-redpesk-sdk"      , type: "file",  source: "../../../install-redpesk-sdk.sh" , destination: "/home/vagrant/"
  config.vm.provision  "test-sdk-VAR-script"      , type: "file",  source: "../../test_SDK_var.sh"             , destination: "/home/vagrant/"
  config.vm.provision  "test-sdk-script"          , type: "shell", path: "../../test_SDK.sh"              , upload_path: "/home/vagrant/test_SDK.sh" , privileged: false
  
end
