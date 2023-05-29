terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.0"

    }
  }
  backend "s3" {
    bucket = "terraform-state1234"
    key    = "us-east-2/env-spin/terraform.tfstate"
    region = "us-east-1"
  }
}



provider "aws" {
  region = "us-east-2"
  alias  = "ohio"

}

provider "aws" {
  region = "us-east-1"
  alias  = "root"

}



module "vpc-dr" {

  source = "git::https://github.com/shreyansh2953/terraform-aws-vpc.git?ref=master"

  my_vpc_cidr = "10.240.16.0/26"
  my_tags = {
    Name = "frk-dr"
    Env  = "dr"
  }
  my_subnets = ["10.240.16.0/27", "10.240.16.32/27"]
  isIGW      = false
  isNAT      = false

  providers = {
    aws = aws.ohio
  }

}


module "vpc-test-dev" {

  source = "git::https://github.com/shreyansh2953/terraform-aws-vpc.git?ref=master"

  my_vpc_cidr = "10.240.16.64/26"
  my_tags = {
    Name = "frk-test-dev"
    Env  = "test-dev"
  }
  my_subnets = ["10.240.16.64/27", "10.240.16.96/27"]
  isIGW      = false
  isNAT      = false

  providers = {
    aws = aws.ohio
  }

}

module "vpc-veeam" {

  source = "git::https://github.com/shreyansh2953/terraform-aws-vpc.git?ref=master"

  my_vpc_cidr = "10.240.16.128/26"
  my_tags = {
    Name = "frk-veeam"
    Env  = "veeam"
  }
  my_subnets = ["10.240.16.128/27", "10.240.16.160/27"]
  isIGW      = true
  isNAT      = true

  providers = {
    aws = aws.ohio
  }

}

module "vpc-bubble-dr" {

  source = "git::https://github.com/shreyansh2953/terraform-aws-vpc.git?ref=master"

  my_vpc_cidr = "10.240.16.192/26"
  my_tags = {
    Name = "frk-bubble-dr"
    Env  = "bubble-dr"
  }
  my_subnets = ["10.240.16.192/27", "10.240.16.224/27"]
  isIGW      = false
  isNAT      = false

  providers = {
    aws = aws.ohio
  }

}

module "transient-Gateway" {
  source = "git::https://github.com/shreyansh2953/terraform-aws-tgw.git?ref=master"
  providers = {
    aws = aws.ohio
  }
  dr-vpc-id       = module.vpc-dr.vpc_id
  test-dev-vpc-id = module.vpc-test-dev.vpc_id
  veeam-vpc-id    = module.vpc-veeam.vpc_id

  depends_on = [module.vpc-dr, module.vpc-test-dev, module.vpc-veeam]
}

module "vpn-client" {
  source = "git::https://github.com/shreyansh2953/terraform-aws-vpnClient.git?ref=master"

  providers = {
    aws = aws.ohio
  }
  bubble-dr-vpc-id       = module.vpc-bubble-dr.vpc_id
  server-certificate-arn = "arn:aws:acm:us-east-2:680851586535:certificate/ea065b38-9515-4cbe-9b0f-1a974ac3c03a"
  client-certificate-arn = "arn:aws:acm:us-east-2:680851586535:certificate/e8e917a7-7bba-48ed-bf55-51304dd9370e"
  client_cidr_block      = "20.0.0.0/22"
  split_tunnel           = true

  depends_on = [module.vpc-bubble-dr]
}

module "s3-endpoint" {
  source = "git::https://github.com/shreyansh2953/terraform-aws-s3endpoint.git?ref=master"
  providers = {
    aws = aws.ohio
  }
  veeam-vpc-id = module.vpc-veeam.vpc_id

  depends_on = [module.vpc-veeam]

}



module "tgw-peering-module" {
  source = "git::https://github.com/shreyansh2953/terraform-aws-tgwPeering.git?ref=master"
  providers = {
    aws      = aws.ohio
    aws.root = aws.root
  }
  onPrem-routes           = ["192.168.0.0/16"]
  root-tgw-id             = "tgw-02bb29b774e7dd96e"
  tgw_id                  = module.transient-Gateway.tgw_id
  dr-vpc-id               = module.vpc-dr.vpc_id
  test-dev-vpc-id         = module.vpc-test-dev.vpc_id
  veeam-vpc-id            = module.vpc-veeam.vpc_id
  default_tgw_route_table = false
  root-tgw-route_table_id = "tgw-rtb-098de1ba82e83d486"

  depends_on = [module.vpc-dr, module.vpc-test-dev, module.vpc-veeam, module.transient-Gateway]
}

module "ram" {
  source = "git::https://github.com/shreyansh2953/terraform-aws-resourceaccessmanager.git?ref=master"
  providers = {
    aws = aws.ohio
  }
  tgw_arn    = module.transient-Gateway.tgw_arn
  account_id = "789796813748"

  depends_on = [module.transient-Gateway, module.vpn-client, module.s3-endpoint, module.tgw-peering-module]
}


