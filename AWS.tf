// aws configure :

provider "aws" {
  region     = "ap-south-1"
  profile    = "kranthi"
}

// RSA private key :

variable "EC2_Key" {default="keyname111"}
resource "tls_private_key" "mynewkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

// AWS key-pair :

resource "aws_key_pair" "generated_key" {
  key_name   = var.EC2_Key
  public_key = tls_private_key.mynewkey.public_key_openssh
}

// security group :

resource "aws_security_group" "mysg" {

depends_on = [
    aws_key_pair.generated_key,
  ]

  name         = "allow_http"
  description  = "Allow http inbound traffic"
 
  ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "httpdsecurity"
  }
}

// EC2 Instance and configuring httpd,git,php in it :

resource "aws_instance" "myterraformos1" {

depends_on = [
    aws_security_group.mysg,
  ]

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = var.EC2_Key
  security_groups = [ "${aws_security_group.mysg.name}" ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mynewkey.private_key_pem
    host     = aws_instance.myterraformos1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "OSterraform"
  }
}

// EBS volume :

resource "aws_ebs_volume" "volterraform" {
  availability_zone = aws_instance.myterraformos1.availability_zone
  size              = 1
  tags = {
    Name = "volforterraform"
  }
}

// mounting volume :

resource "aws_volume_attachment" "attachvol" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.volterraform.id
  instance_id = aws_instance.myterraformos1.id
  force_detach = true
}

// deploy github code in /var/www/html :

resource "null_resource" "mountingvol"  {

depends_on = [
    aws_volume_attachment.attachvol,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mynewkey.private_key_pem
    host     = aws_instance.myterraformos1.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/kranthi1234/AWS-Terraform/aws.tf /var/www/html/"
    ]
  }
}

// S3 bucket :

resource "aws_s3_bucket" "s3bucketjob1" {
bucket = "mynewbucketforjob1"
acl    = "public-read"
}

// Putting Objects in mynewbucketforjob1 :

resource "aws_s3_bucket_object" "s3_object" {
  bucket = aws_s3_bucket.s3bucketjob1.bucket
  key    = "snapcode.png"
  source = "C:/Users/Kranthi/Desktop/snapcode.png"
  acl    = "public-read"
}

// Cloud Front Distribution :

locals {
s3_origin_id = aws_s3_bucket.s3bucketjob1.id
}

resource "aws_cloudfront_distribution" "CloudFrontAccess" {

depends_on = [
    aws_s3_bucket_object.s3_object,
  ]

origin {
domain_name = aws_s3_bucket.s3bucketjob1.bucket_regional_domain_name
origin_id   = local.s3_origin_id
}

enabled             = true
is_ipv6_enabled     = true
comment             = "s3bucket-access"

default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}
# Cache behavior with precedence 0
ordered_cache_behavior {
path_pattern     = "/content/immutable/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD", "OPTIONS"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
headers      = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 86400
max_ttl                = 31536000
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
restrictions {
geo_restriction {
restriction_type = "blacklist"
locations        = ["CA"]
}
}
tags = {
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}
retain_on_delete = true
}

// Changing the html code and adding the image url in that.

resource "null_resource" "addingurl"  {
depends_on = [
    aws_cloudfront_distribution.CloudFrontAccess,
  ]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mynewkey.private_key_pem
    host     = aws_instance.myterraformos1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
	"echo '<img src='https://${aws_cloudfront_distribution.CloudFrontAccess.domain_name}/snapcode.png' width='300' height='330'>' | sudo tee -a /var/www/html/index.html"
    ]
  }
}

// EBS snapshot volume :

resource "aws_ebs_snapshot" "snap1" {
depends_on = [
    null_resource.addingurl,
  ]
  volume_id = aws_ebs_volume.volterraform.id

  tags = {
    Name = "job1snap"
  }
}

// deploying webapp :

resource "null_resource" "deploywebapp"  {
depends_on = [
    aws_ebs_snapshot.snap1,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.myterraformos1.public_ip}/index.html"
  	}
}
