
# Stage 1: Build the Go application
FROM golang:1.24-alpine AS builder

WORKDIR /src

# Install certificates for HTTPS calls, if needed
RUN apk add --no-cache ca-certificates

# Internal Go module proxy
ENV GOPROXY=https://artifactory.example.com/artifactory/api/go/go-virtual
ENV GOSUMDB=off

COPY go.mod go.sum ./

RUN go mod download

COPY . .

# Build a static Linux binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/app .

# Stage 2: Minimal production runtime
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /

COPY --from=builder --chown=65532:65532 /out/app /app

EXPOSE 8080

USER 65532:65532

ENTRYPOINT ["/app"]
