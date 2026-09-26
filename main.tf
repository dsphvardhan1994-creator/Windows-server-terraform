terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "windows" {
  name        = "${var.name}-windows"
  description = "Allow all inbound IPv4 traffic."
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name}-windows-sg" }
}

resource "aws_iam_role" "instance" {
  name = "${var.name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Name = "${var.name}-ec2-ssm-role" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Broad account-wide AWS access on the VM, as requested.
resource "aws_iam_role_policy_attachment" "administrator" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-ec2-ssm-profile"
  role = aws_iam_role.instance.name
}

resource "aws_instance" "windows" {
  ami                         = data.aws_ssm_parameter.windows_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.windows.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true
  monitoring                  = true
  user_data_replace_on_change = true
  user_data = <<-POWERSHELL
    <powershell>
    $ErrorActionPreference = 'Stop'
    $encodedPassword = '${base64encode(var.windows_password)}'
    $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword))
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    if (Get-LocalUser -Name '${var.windows_username}' -ErrorAction SilentlyContinue) {
      Set-LocalUser -Name '${var.windows_username}' -Password $securePassword
    } else {
      New-LocalUser -Name '${var.windows_username}' -Password $securePassword -PasswordNeverExpires -AccountNeverExpires -Description 'Local administrator for Fleet Manager access'
    }
    Add-LocalGroupMember -Group 'Administrators' -Member '${var.windows_username}' -ErrorAction SilentlyContinue
    $installer = Join-Path $env:TEMP 'python-installer.exe'
    Invoke-WebRequest -Uri '${var.python_installer_url}' -OutFile $installer
    $process = Start-Process -FilePath $installer -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Python installer exited with code $($process.ExitCode)" }
    $python = 'C:\Program Files\Python314\python.exe'
    & $python -m pip install --upgrade pip boto3
    if ($LASTEXITCODE -ne 0) { throw 'pip failed to install boto3' }
    </powershell>
  POWERSHELL
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  tags = { Name = var.name, Environment = var.environment }
  depends_on = [aws_iam_role_policy_attachment.ssm_core, aws_iam_role_policy_attachment.administrator]
}

# Attach this policy to the AWS identity that will open Fleet Manager.
resource "aws_iam_policy" "fleet_manager_operator" {
  name        = "${var.name}-fleet-manager-operator"
  description = "Permissions for Fleet Manager Remote Desktop connections."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:GetPasswordData"], Resource = "*" },
      { Effect = "Allow", Action = ["ssm:DescribeInstanceProperties", "ssm:GetCommandInvocation", "ssm:GetInventorySchema"], Resource = "*" },
      { Effect = "Allow", Action = ["ssm-guiconnect:CancelConnection", "ssm-guiconnect:GetConnection", "ssm-guiconnect:StartConnection", "ssm-guiconnect:ListConnections"], Resource = "*" },
      {
        Effect = "Allow", Action = ["ssm:StartSession"],
        Resource = ["arn:aws:ec2:${var.aws_region}:*:instance/*", "arn:aws:ssm:${var.aws_region}:*:managed-instance/*", "arn:aws:ssm:${var.aws_region}::document/AWS-StartPortForwardingSession"],
        Condition = { "ForAnyValue:StringEquals" = { "aws:CalledVia" = "ssm-guiconnect.amazonaws.com" } }
      },
      {
        Effect = "Allow", Action = ["ssmmessages:OpenDataChannel"], Resource = "arn:aws:ssm:${var.aws_region}:*:session/*",
        Condition = { "ForAnyValue:StringEquals" = { "aws:CalledVia" = "ssm-guiconnect.amazonaws.com" } }
      },
      {
        Effect = "Allow", Action = ["ssm:TerminateSession"], Resource = "*",
        Condition = { StringLike = { "ssm:resourceTag/aws:ssmmessages:session-id" = ["$${aws:userid}"] } }
      }
    ]
  })
  tags = { Name = "${var.name}-fleet-manager-operator" }
}
