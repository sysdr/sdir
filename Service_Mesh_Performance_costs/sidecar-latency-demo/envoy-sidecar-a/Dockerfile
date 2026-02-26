FROM envoyproxy/envoy:v1.29-latest
COPY envoy.yaml /etc/envoy/envoy.yaml
EXPOSE 8081 9090 9901
CMD ["/usr/local/bin/envoy", "-c", "/etc/envoy/envoy.yaml", "--log-level", "info"]
