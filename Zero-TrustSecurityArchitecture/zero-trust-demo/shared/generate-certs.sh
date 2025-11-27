#!/bin/bash
mkdir -p certs

# Generate CA
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout certs/ca-key.pem -out certs/ca-cert.pem \
  -subj "/CN=Zero-Trust-CA"

# Generate service certificates
for service in identity policy proxy service; do
  openssl req -newkey rsa:2048 -nodes \
    -keyout certs/${service}-key.pem \
    -out certs/${service}-req.pem \
    -subj "/CN=${service}"
  
  openssl x509 -req -in certs/${service}-req.pem \
    -CA certs/ca-cert.pem -CAkey certs/ca-key.pem \
    -CAcreateserial -out certs/${service}-cert.pem \
    -days 365
done
