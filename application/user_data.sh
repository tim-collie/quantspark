#!/bin/bash
set -x
echo "test"
sudo dnf update -y
sudo dnf install -y httpd
sudo mkdir -p /var/www/html
sudo sudo chown apache:apache html
echo '<html><body><h1>Hello World</h1></body></html>' > /var/www/html/index.html
sudo systemctl start httpd
sudo systemctl enable httpd