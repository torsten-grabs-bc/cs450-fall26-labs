FROM alpine:3.20
RUN apk add --no-cache bash curl
COPY kv /usr/local/bin/kv
RUN sed -i 's/\r$//' /usr/local/bin/kv && chmod +x /usr/local/bin/kv
WORKDIR /work
CMD ["sleep", "infinity"]
