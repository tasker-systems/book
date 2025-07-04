FROM node:10-alpine

# Set working directory
WORKDIR /app

# Install GitBook CLI globally
RUN npm install -g gitbook-cli@2.3.2

# Copy package files first for better caching
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source files
COPY . .

# Pre-install GitBook to avoid runtime issues
RUN gitbook fetch 3.2.3

# Create a minimal book.json without plugins to avoid installation issues
RUN echo '{"title": "Tasker Engineering Stories", "plugins": [], "pluginsConfig": {}}' > book-minimal.json

# Expose port
EXPOSE 4000

# Default command - use the minimal config and build first
CMD ["sh", "-c", "cp book-minimal.json book.json && gitbook build && gitbook serve --port 4000 --host 0.0.0.0"]
