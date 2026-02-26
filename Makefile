# Makefile for MacStats

.PHONY: all build dev clean install run release help

# Default target
all: build

# Build for release
build:
	@echo "🚀 Building MacStats for release..."
	@./build.sh

# Build for development
dev:
	@echo "🔧 Building MacStats for development..."
	@./dev-build.sh

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf build/
	@rm -rf DerivedData/
	@rm -rf ~/Library/Developer/Xcode/DerivedData/MacStats-*
	@pkill -f MacStats || true
	@echo "✅ Clean completed!"

# Run the application (with clean build)
run: clean dev
	@echo "🚀 Running MacStats..."
	@./run.sh

# Install dependencies (if needed)
install:
	@echo "📦 Checking dependencies..."
	@if ! command -v xcodebuild &> /dev/null; then \
		echo "❌ Xcode command line tools not found"; \
		echo "Please install with: xcode-select --install"; \
		exit 1; \
	fi
	@if ! command -v create-dmg &> /dev/null; then \
		echo "⚠️  create-dmg not found (optional for DMG creation)"; \
		echo "Install with: brew install create-dmg"; \
	fi
	@echo "✅ Dependencies check completed!"

# Build, sign, notarize, and create a GitHub release
release:
	@echo "📦 Building and releasing MacStats..."
	@./build.sh release

# Show help
help:
	@echo "MacStats Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  build    - Build for release distribution"
	@echo "  dev      - Build for development"
	@echo "  run      - Clean build and run the application"
	@echo "  release  - Build, sign, notarize, and create GitHub release"
	@echo "  clean    - Clean build artifacts"
	@echo "  install  - Check and install dependencies"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Usage examples:"
	@echo "  make build   # Build release version"
	@echo "  make dev     # Build development version"
	@echo "  make clean   # Clean all build files"