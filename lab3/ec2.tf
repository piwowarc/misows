resource "aws_iam_instance_profile" "default" {
  name = "default"
  role = "${aws_iam_role.misows_role.name}"
}

locals {
  instance-userdata = <<EOF
#!/bin/bash
export PATH=$PATH:/usr/local/bin
apt-get -y update
apt-get -y install apache2
apt-get -y install awscli
aws s3 cp s3://misows2019/Znak_graficzny_AGH.svg.png /var/www/html
EOF
}

resource "aws_instance" "misows" {
  ami = "ami-0cc0a36f626a4fdf5"
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.default.name}"
  user_data_base64 = "${base64encode(local.instance-userdata)}"
  key_name = "misows"
  security_groups = ["misows"]
}