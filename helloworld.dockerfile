FROM dockercloud/hello-world
RUN apk --no-cache add curl
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
      CMD curl -f http://localhost:80 || exit 1
