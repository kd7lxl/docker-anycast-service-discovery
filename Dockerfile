FROM alpine
RUN apk --no-cache add bash curl docker iproute2 jq
COPY docker-entrypoint.sh /
CMD ["/docker-entrypoint.sh"]


