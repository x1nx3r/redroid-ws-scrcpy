FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    android-tools-adb \
    ca-certificates \
    git python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/NetrisTV/ws-scrcpy.git .
RUN npm install

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
