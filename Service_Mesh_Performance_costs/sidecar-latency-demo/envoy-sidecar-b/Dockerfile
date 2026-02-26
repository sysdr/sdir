FROM envoyproxy/envoy:v1.29-latest
COPY envoy.yaml /etc/envoy/envoy.yaml
EXPOSE 8082 9902
CMD ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml", "--log-level", "info"]
