FROM alpine:3.22
RUN apk add --no-cache chrony
COPY chrony.conf /etc/chrony/chrony.conf
EXPOSE 123/udp
HEALTHCHECK --interval=15s --timeout=3s --retries=3 CMD chronyc tracking >/dev/null || exit 1
ENTRYPOINT ["chronyd", "-d", "-x", "-f", "/etc/chrony/chrony.conf"]
