# RoadSense API image (deployed on Render; runs anywhere that runs containers).
# Build: `just server-docker`. Migrations are embedded in the binary, so the image needs no other files.

FROM rust:1.96.0-slim-trixie AS build
WORKDIR /app
COPY . .
RUN cargo build --release --locked -p roadsense-api

FROM debian:trixie-slim
# CA certificates for TLS to the hosted database.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/roadsense-api /usr/local/bin/roadsense-api
USER nobody
ENV RUST_LOG=info
# The host sets PORT (Render: 10000); the server listens on it.
CMD ["roadsense-api"]
