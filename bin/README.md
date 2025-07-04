# GitBook Build Scripts

This directory contains scripts for building and serving the GitBook site using Docker to ensure Node.js compatibility.

## Prerequisites

- **Docker**: Install Docker Desktop from https://docs.docker.com/get-docker/
- **Basic familiarity with command line**

### Installing Docker

#### macOS
1. Download Docker Desktop from https://docs.docker.com/desktop/mac/install/
2. Install and start Docker Desktop
3. Verify installation: `docker --version`

#### Linux
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to docker group (optional, avoids sudo)
sudo usermod -aG docker $USER
```

#### Windows
1. Download Docker Desktop from https://docs.docker.com/desktop/windows/install/
2. Install and start Docker Desktop
3. Verify installation: `docker --version`

## Scripts

### `build-site.sh`

Main script for building and serving the GitBook site using Docker.

#### Usage

```bash
# Build static site
./bin/build-site.sh build

# Start development server
./bin/build-site.sh serve

# Clean up Docker resources
./bin/build-site.sh clean

# Show help
./bin/build-site.sh help
```

#### Commands

- **`build`** - Builds static GitBook site to `_book/` directory
- **`serve`** - Starts development server on port 4000 with live reload
- **`clean`** - Removes Docker containers and optionally images
- **`help`** - Shows usage information

#### npm Scripts

You can also use the npm scripts for convenience:

```bash
# Start development server with Docker
npm run serve-docker

# Build static site with Docker
npm run build-docker

# Clean up Docker resources
npm run docker-clean
```

## Quick Start

1. **Install Docker** (see Prerequisites above)
2. **Clone the repository** and navigate to the project directory
3. **Build and serve the site**:
   ```bash
   ./bin/build-site.sh serve
   ```
4. **Open your browser** to http://localhost:4000

## How It Works

1. **Docker Image**: Uses Node.js 14 Alpine for GitBook CLI compatibility
2. **Volume Mounting**: Mounts project directory for live reload during development
3. **Port Mapping**: Maps container port 4000 to host port 4000
4. **Automatic Cleanup**: Cleans up containers when script exits

## Troubleshooting

### Docker Not Found
```
Error: Docker is not installed
```
**Solution**: Install Docker from https://docs.docker.com/get-docker/

### Docker Not Running
```
Error: Docker is not running
```
**Solution**: Start Docker Desktop or Docker daemon

### Port Already in Use
```
Error: Port 4000 already in use
```
**Solution**: Stop other services using port 4000 or modify the PORT variable in the script

### Permission Denied
```
Error: Permission denied
```
**Solution**: Make the script executable:
```bash
chmod +x bin/build-site.sh
```

### Build Fails
If the Docker build fails, try:
```bash
# Clean up and rebuild
./bin/build-site.sh clean
./bin/build-site.sh build
```

## Development Notes

- The Docker image is cached after first build for faster subsequent runs
- Use `./bin/build-site.sh clean` to remove containers and free up space
- The script automatically handles container cleanup on exit (Ctrl+C)
- Static builds are output to `_book/` directory and can be served with any web server
- First build may take a few minutes to download Node.js image and install dependencies

## Alternative Serving

After building static files, you can serve them without Docker:

```bash
# Using http-server (already in package.json)
npm run serve-alt

# Using Python (if available)
cd _book && python -m http.server 4000

# Using any other static file server
cd _book && your-favorite-server
```

## Fallback: Native Node.js

If Docker isn't available, you can still try the native approach:

```bash
# Install Node.js 14 using nvm
nvm install 14
nvm use 14

# Install dependencies and serve
npm install
npm run serve
```

Note: This may not work on all systems due to GitBook CLI compatibility issues with modern Node.js versions.
