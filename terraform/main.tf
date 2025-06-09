provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "deployer" {
  key_name   = "ec2-key"
  public_key = file(var.public_key_path)
}

resource "aws_security_group" "allow_traffic" {
  name        = "allow_web_ssh"
  description = "Allow SSH, HTTP, and custom ports"
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (Jenkins)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Tomcat"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Flask App"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.allow_traffic.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y

              # Install Git
              yum install git -y

              # Install Python 3 and pip3
              yum install python3 -y
              pip3 install --upgrade pip
              pip3 install flask

              # Install Java (required by Jenkins and Tomcat)
              amazon-linux-extras install java-openjdk11 -y

              # Install Jenkins
              wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              yum install jenkins -y
              systemctl enable jenkins
              systemctl start jenkins

              # Install Tomcat
              cd /opt
              curl -O https://downloads.apache.org/tomcat/tomcat-9/v9.0.85/bin/apache-tomcat-9.0.85.tar.gz
              tar -xzf apache-tomcat-9.0.85.tar.gz
              mv apache-tomcat-9.0.85 tomcat9
              chmod +x /opt/tomcat9/bin/*.sh
              nohup /opt/tomcat9/bin/startup.sh &

              # Sample Flask app
              mkdir -p /home/ec2-user/flaskapp
              cat << FLASKEOF > /home/ec2-user/flaskapp/app.py
              from flask import Flask
              app = Flask(__name__)

              @app.route('/')
              def hello():
                  return "Hello from Flask on EC2!"

              if __name__ == '__main__':
                  app.run(host='0.0.0.0', port=5000)
              FLASKEOF

              nohup python3 /home/ec2-user/flaskapp/app.py &
              EOF

  tags = {
    Name = "ec2-with-jenkins-tomcat-flask"
  }
}
