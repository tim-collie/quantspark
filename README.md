# Deploying an AWS based webservice via IaC

![Quantspark (2)](https://github.com/tim-collie/quantspark/assets/43747594/c236b3af-aa96-4003-8bee-d2c26d884237)

This repository contains Terraform code to deploy asimple AWS based webservice. This document will cover infrastructure deployment, 
removal and design choices with a final section giving an idea of improvements with further time investment.

- Terraform 1.2.*
- AWS CLI
- AWS account with the necessary permissions

# Prerequisites

Prior to running this code the following have to be in place:

- **Suitable Authentication to AWS**: Either by locally a configured AWS key and key secret or via an assumed IAM role, access to deploy to the correct AWS account is required. 
- **Terraform**: A suitable local version of terraform, this code was prepared using 1.2.9 and it is recommended to use the same verion.

# Code structure

The Terraform code `main.tf` file creates a simple AWS infrastructure setup for a web application. It includes the following components:

- **VPC**: A Virtual Private Cloud (VPC) with 2 public distributed across different Availability Zones.

- **Subnets**: A public and private subnet is created in each of two availability zones, we place the ALB spanning the public zones, we host the webservers in the private zones to facilitate a degree of security.

- **EC2 Instances**: An Elastic Compute Cloud (EC2) instance launched as part of an Auto Scaling Group (ASG) and Launch Template.

- **VPC Endpoint**: A policy limited S3 endpoint to allow EC2 instances on private subnets without internet access to run yum update and install Apache2.

- **IAM Role**: An IAM role associated with the EC2 instances.

- **Key Pair**: For troubleshooting purposes after creating the SSH key used by the EC2 instances we place the private key into Secrets Manager

- **Application Load Balancer**: An Application Load Balancer configured with a Target Group, this Target Group is then in turn used in the Auto Scaling Group code to ensure the EC2 instances appear as targets.

- **Security Groups** one security group for the load balancer with port 80 (http) inbound from the internet, one security group for the webserver EC2 instances allowing traffic from the ALB on port 80 by referring to the ALB security group as the source of traffic. We can achieve this by the fact that the ALB is terminating traffic so is the effective source of all inbound HTTP traffic.

The Terraform code `providers.tf` file enables the controlled definition of the versions of providers we use.

The Terraform code `outputs.tf` file allows for creation of custom outputs both as a visual reference for engineers but also as data sources within other Terraform code.


# Deployment

To deploy the infrastructure:

1. Clone this repository to your local environment.

2. Navigate to the repository root and change to the application directory.

2. Run the following Terraform commands:

`terraform init`

`terraform plan`

`terraform apply`
   
3. Terraform will provide output on completion, which will include the DNS name of the Application Load Balancer (ALB). This fully qualified DNS name will allow access to the webservice over the internet.

4. Once the is confirmed as functional the following Terraform command with destroy the previously created AWS resources.
   
`terraform destroy`

# Design choices

The brief required the solution to be secure, resilient and cost efficient while being simple to understand and deploy.

I have selected EC2 as the platform to act as the webserver - this give the ability to be cost efficient by selecting instance sizes that fall into the free tier while also supporting autoscaling. We use autoscaling to maintain fault tolerance at the application level  by ensuring we always have at least two instances available, by default ths ASG will place instances into the two availability zones we use so we achieve fault tolerance within our selected AWS region. We place the EC2 instances on private subnets and secure via security groups, the instances themselves are deployed using a launch template giving a simple webserver solution via user data at launch time. 

We use an application load balancer to route traffic between the EC2 instances, this is the cornerstone of our fault tolerance over mulitple availability zones.

# Potential Improvements

- **Deployment**: Running Terraform from the command line is problematic as it provides minimal auditing and version control, it would be better to move this to a CI/CD platform such as Github Actions driving deployments through a PR process - this does increase complexity and would require planning around local Github Actions runner hosted within AWS and conderation of a well structured IAM setup. Currently the webserver is only serving unencrypted traffic, we have deployed an application load balancer and can use either an external certificate source or AWS based certificate authority to generate and deploy an SSL certificate for the ALB and handle SSL termination for HTTPS traffic at the ALB level in combination with public DNS either managed via Route53 or an external provider.
  
  The local deployment process also is creating local state files, to allow for consistent infrastructure the state file ideally should be held centrally in an S3 bucket. We also have no locking to ensure that competing deployments are impossible, this can also be catered for via a centrally located DynamoDB instance.     

- **Monitoring**: We have no monitoring in place, the expectation should be to capture logs within Cloudwatch and also provide alerting on instance availability issues via Cloudwatch Alarms and potentially SNS. We could consider 3rd party products such as Sumologic for log ingrestion or New Relic for a more complete monitoing solution.

- **Scaling**: This solution will only maintain the required number of instances, it's problematic to capture the memory and CPU utilization at the EC2 level to provide meaningful scaling out based on the application itself - as demand increases we could consider moving to either ECS or EKS, this might require a change in architecture of the application and increases the complexity of the infrastructure itself. Cloudfront would also provide a 

- **Infrastucture vs Application**: Currently we are deploying both from Terraform which isn't ideal, with a movement towards either ECS or EKS we could separate the application from the infrastructure, this would enable the deployment process to either follow a CI/CD driven blue/green deployment or canary deployment to minimize the downtime and risk involved in the deployment process.

- **Reusable Code**: The current code is very specific, ideally we should either be creating or sourcing Terraform modules for these tasks which we hold in a separate repo and used by default.
