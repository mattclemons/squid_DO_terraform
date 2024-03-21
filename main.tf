terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.5.0"
    }
  }
}

provider "digitalocean" {
  token = "ADD_YOUR_API_KEY"
}

resource "digitalocean_droplet" "centos_example" {
  count    = 3
  image    = "centos-7-x64" # Replace with the correct slug for your desired CentOS version
  name     = "centos-droplet-${count.index}"
  region   = "nyc3"
  size     = "s-1vcpu-1gb"
  ssh_keys = [digitalocean_ssh_key.example.id]

  user_data = <<-EOF
    #!/bin/bash
    yum -y update
    yum -y install squid
    sudo sed -i '1 i\# blacklist config' /etc/squid/squid.conf
    sudo sed -i '2 i\acl blacklist dstdomain "/etc/squid/blocked.txt"' /etc/squid/squid.conf
    sudo sed -i '/acl Safe_ports port 777/a #ACL Blocklist' /etc/squid/squid.conf
    sudo sed -i '/#ACL Blocklist/a http_access deny all blacklist' /etc/squid/squid.conf
    sudo sed -i 's/\http_access allow localhost\>/http_access allow all/g' /etc/squid/squid.conf
    sudo touch /etc/squid/blocked.txt
    sudo bash -c "echo '.examplemalwaredomain.com' > /etc/squid/blocked.txt"
    sudo bash -c "echo .internetbadguys.com >> /etc/squid/blocked.txt"
    sudo bash -c "echo .examplebotnetdomain.com >> /etc/squid/blocked.txt"
    sudo yum install squid httpd-tools
    sudo systemctl enable squid
    sudo systemctl restart squid
  EOF
}

resource "digitalocean_loadbalancer" "example" {
  name   = "example-lb"
  region = "nyc3"

  forwarding_rule {
    entry_port     = 80
    entry_protocol = "http"

    target_port     = 3128
    target_protocol = "http"
  }

  healthcheck {
    port     = 3128
    protocol = "tcp"
    # Note: DigitalOcean's Load Balancer does not support inspecting specific HTTP response codes for health checks.
  }

  droplet_ids = [for droplet in digitalocean_droplet.centos_example : droplet.id]
}

output "load_balancer_ip" {
  value = digitalocean_loadbalancer.example.ip
}

resource "digitalocean_firewall" "squid_firewall" {
  name = "squid-firewall"

  # Allow SSH access from anywhere
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"] # IPv4 and IPv6
  }

  # Allow inbound traffic on port 3128 from the Load Balancer only
  # Assuming the Load Balancer is tagged as 'load-balancer', replace with actual tag if different
  inbound_rule {
    protocol       = "tcp"
    port_range     = "3128"
    source_addresses = ["4.2.2.2/32"] #you'll have to go into DO and set the Loadbalancer IP.
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"] # IPv4 and IPv6
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"] # IPv4 and IPv6
  }

  # Associate the firewall with Droplets by tags, names, or IDs
  # Example: Apply to Droplets tagged as 'squid'
  droplet_ids = flatten([digitalocean_droplet.centos_example.*.id])
}

resource "digitalocean_ssh_key" "example" {
  name       = "example_key"
  public_key = file("~/.ssh/digitalocean.pub")
}

