# Official Alpine image from Docker Hub, plus curl and bash.
FROM alpine:3.20
RUN apk add --no-cache bash curl
COPY kv /usr/local/bin/kv
# Strip any CR the host's git checkout added. Belt and braces alongside
# .gitattributes: this fixes a working tree that was cloned before that file
# existed, so a rebuild is enough and nobody has to re-clone.
RUN sed -i 's/\r$//' /usr/local/bin/kv && chmod +x /usr/local/bin/kv
WORKDIR /work
CMD ["sleep", "infinity"]
