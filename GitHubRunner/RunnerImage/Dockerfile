FROM ghcr.io/actions/actions-runner:latest

USER root

# Install curl, jq, Azure CLI, and Node.js
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    zip \
    apt-transport-https \
    lsb-release \
    nodejs && \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && apt-get install -y azure-cli && \
    ln -s /usr/bin/nodejs /usr/local/bin/node && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install .NET SDK
RUN apt-get update && apt-get install -y wget \
    && wget https://dot.net/v1/dotnet-install.sh -O /usr/local/bin/dotnet-install.sh \
    && chmod +x /usr/local/bin/dotnet-install.sh \
    && /usr/local/bin/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy over the start.sh script
COPY start.sh start.sh

# Make the script executable
RUN chmod +x start.sh

# Since the config and run script for actions are not allowed to be run by root,
# set the user to "runner" so all subsequent commands are run as the runner user
USER runner

# Set the entrypoint to the start.sh script
ENTRYPOINT ["./start.sh"]