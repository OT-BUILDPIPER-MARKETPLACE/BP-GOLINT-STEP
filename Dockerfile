FROM golang:1.22-alpine

# ---------------------------------------------------------------------
# Create BuildPiper user + directories
# ---------------------------------------------------------------------
RUN addgroup -g 65522 buildpiper && \
    adduser -u 65522 -G buildpiper -D -h /home/buildpiper buildpiper && \
    mkdir -p \
      /app \
      /bp/data \
      /bp/execution_dir \
      /bp/workspace \
      /opt/buildpiper/shell-functions \
      /opt/buildpiper/data \
      /src/reports \
      /home/buildpiper/reports \
      /usr/local/bin && \
    chown -R buildpiper:buildpiper /app /bp /opt /home/buildpiper /src /usr/local/bin /tmp

# ---------------------------------------------------------------------
# Install required packages
# ---------------------------------------------------------------------
RUN apk add --no-cache bash jq curl git gettext libintl

# ---------------------------------------------------------------------
# Install golangci-lint
# ---------------------------------------------------------------------
ENV GOLANGCI_LINT_VERSION=v1.60.1
RUN curl -sSfL \
    https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
    | sh -s -- -b /usr/local/bin ${GOLANGCI_LINT_VERSION}

# ---------------------------------------------------------------------
# Copy BuildPiper shell functions + script
# ---------------------------------------------------------------------
WORKDIR /app
COPY --chown=buildpiper:buildpiper build.sh ./build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/ /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data /opt/buildpiper/data

RUN chmod +x /app/build.sh

# ---------------------------------------------------------------------
# Switch to non-root and run
# ---------------------------------------------------------------------
USER buildpiper
ENTRYPOINT ["./build.sh"]
