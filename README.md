# This Template is creating the following resources using the official terraform community modules:

* An S3 bucket
* An IAM role
* An IAM policy attached to the role that allows it to perform any S3 actions on that bucket and the objects in it
* An EC2 instances(Autoscaling) with the IAM role attached.
  - Use the following information for the ec2 instance:
    - region=us-east-1
    - ami=`ami-029c0fbe456d58bd1`
    - instance_type=t2.micro
  - Create a key-pair resource that can be used to ssh into the system.

- Postgres RDS
- Application Load Balancer

# **Assumptions:**

##### Terraform:

1. Terraform version is `>= 0.12.6`
2. Terraform has all the necessary permissions to create, manage and remove the resources created in the template.

##### S3 Bucket:

1. S3 bucket and objects are private
2. S3 Bucket needs to be created in us-east-2 region
3. S3 Objects contain non-critical/trivial data
   1. S3 objects can be overwritten (object lock not enabled)
   2. Versioning is enabled
   3. Objects can be easily replaced
      1. lifecycle policy is set to delete noncurrent version objects after a certain period
   4. No need for non-api object level monitoring (Bucket is not used for static website)
      1. Object server access logs not enabled
      2. Cloudtrail object-level api logs enabled for the bucket

##### VPC:

1. The default VPC in the AWS account might have been deleted when the terraform template is deployed

##### EC2:

1. The EC2 Instance volume needed is 8Gb and because it is temporary.
2. The Key-pair generated is **TEMPORARY** and will not be used outside of testing SSH login to this instance for the interview as the private key is in the statefile in plain-text.
3. The ssh private key is created in the root of the terraform folder as ssh-pvt.pem.
   1. To log in from terraform folder root location:  `ssh -i ssh-pvt.pem ec2-user@publicip`

![Architecture Diagram](./diagram/john.png)
