variable "my_s3_bucket_name" {
  default = "fhfdjidfjdffd"
}

variable "key_name" {
  default = "myjohnec2key"
}

variable "image-id" {
  default = "ami-029c0fbe456d58bd1"
}

variable "instance-type" {
  default = "t2.micro"
}

variable "certificate-arn" {
  type        = string
  description = "Enter the certificate arn for the loadbalancer"
}

variable "dbuser" {
  description = "Postgres rds database user"
  default     = "dbuser"
}

variable "dbpassword" {
  description = "Postgres rds database password"
  default     = "Pasrd123db12"
}



