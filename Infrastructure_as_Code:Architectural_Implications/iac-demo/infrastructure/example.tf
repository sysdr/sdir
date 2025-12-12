# Example Terraform Configuration

resource "aws_instance" "web_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"
  
  tags = {
    Name = "web-server-01"
    Environment = "production"
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "postgres-db"
  engine         = "postgresql"
  engine_version = "14.5"
  instance_class = "db.t3.medium"
}

resource "aws_s3_bucket" "backup" {
  bucket = "backup-bucket"
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    enabled = true
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}
