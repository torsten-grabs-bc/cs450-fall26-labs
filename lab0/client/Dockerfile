# Official Alpine image from Docker Hub, plus curl and bash.
FROM alpine:3.20
RUN apk add --no-cache bash curl
COPY kv /usr/local/bin/kv
RUN chmod +x /usr/local/bin/kv
WORKDIR /work
CMD ["sleep", "infinity"]
