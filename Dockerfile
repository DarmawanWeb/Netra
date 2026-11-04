# NETRA as one image: the dashboard export (fe/) built into the service (be/). Needs the
# submodules: git submodule update --init.
FROM node:20-alpine AS web
WORKDIR /fe
COPY fe/package.json fe/package-lock.json ./
RUN npm ci --no-audit --no-fund --ignore-scripts
COPY fe/ ./
RUN npm run postinstall && npm run build

FROM golang:1.22-alpine AS build
WORKDIR /be
COPY be/go.mod be/go.sum ./
RUN go mod download
COPY be/ ./
COPY --from=web /fe/out ./internal/web/dist
ARG VERSION=dev
ARG COMMIT=""
RUN LDFLAGS="-s -w -X github.com/DarmawanWeb/netra-fleet-be/internal/version.Version=${VERSION} \
      -X github.com/DarmawanWeb/netra-fleet-be/internal/version.Commit=${COMMIT}" && \
    CGO_ENABLED=0 go build -tags webui -trimpath -ldflags="$LDFLAGS" -o /out/netra ./cmd/netra && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/netra-license ./cmd/netra-license && \
    mkdir -p /out/data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/netra /netra
# netra-license inspect checks a license file on site (issuing needs the vendor's key).
COPY --from=build /out/netra-license /netra-license
# The data volume must be writable by the nonroot user (uid 65532).
COPY --from=build --chown=65532:65532 /out/data /data
ENV NETRA_DATA_DIR=/data NETRA_ADDR=:8080
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["/netra"]
CMD ["serve"]
