#!/bin/bash

set -e

INSTALL_DIR="${HOME}/.local/bin"
TEMP_DIR="/tmp/dagrobin-install"

detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        CYGWIN*|MINGW*|MSYS*) echo "windows";;
        *)          echo "unknown";;
    esac
}

install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "Rust already installed"
    fi
}

install_dagrobin() {
    echo "Installing dagRobin..."
    
    if command -v dagRobin &> /dev/null; then
        echo "dagRobin already installed"
        return
    fi
    
    if [ -d "${TEMP_DIR}/dagRobin" ]; then
        rm -rf "${TEMP_DIR}/dagRobin"
    fi
    
    git clone https://github.com/afa7789/dagRobin.git "${TEMP_DIR}/dagRobin"
    cd "${TEMP_DIR}/dagRobin"
    cargo build --release
    
    mkdir -p "${INSTALL_DIR}"
    cp target/release/dagRobin "${INSTALL_DIR}/"
    
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    echo "dagRobin installed successfully"
}

install_differ_helper() {
    echo "Installing differ_helper..."
    
    if command -v differ_helper &> /dev/null; then
        echo "differ_helper already installed"
        return
    fi
    
    if [ -d "${TEMP_DIR}/differ_helper" ]; then
        rm -rf "${TEMP_DIR}/differ_helper"
    fi
    
    git clone https://github.com/afa7789/differ_helper "${TEMP_DIR}/differ_helper"
    cd "${TEMP_DIR}/differ_helper"
    make install
    
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    echo "differ_helper installed successfully"
}

add_to_path() {
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        case "$(detect_os)" in
            macos|linux)
                if [ -f "$HOME/.zshrc" ]; then
                    echo "export PATH=\"\${PATH}:${INSTALL_DIR}\"" >> "$HOME/.zshrc"
                    echo "Added ${INSTALL_DIR} to PATH in ~/.zshrc"
                elif [ -f "$HOME/.bashrc" ]; then
                    echo "export PATH=\"\${PATH}:${INSTALL_DIR}\"" >> "$HOME/.bashrc"
                    echo "Added ${INSTALL_DIR} to PATH in ~/.bashrc"
                fi
                ;;
            windows)
                echo "Please add ${INSTALL_DIR} to your PATH manually"
                ;;
        esac
    fi
}

main() {
    OS=$(detect_os)
    echo "Detected OS: ${OS}"
    
    case "$OS" in
        macos|linux)
            install_rust
            install_dagrobin
            install_differ_helper
            add_to_path
            ;;
        windows)
            echo "Windows not fully supported yet. Please install manually:"
            echo "1. Install Rust: https://rustup.rs"
            echo "2. Install dagRobin: cargo install from https://github.com/afa7789/dagRobin"
            echo "3. Install differ_helper: git clone and make install from https://github.com/afa7789/differ_helper"
            exit 1
            ;;
        *)
            echo "Unknown OS"
            exit 1
            ;;
    esac
    
    echo ""
    echo "Installation complete!"
    echo "Please restart your terminal or run: source ~/.zshrc (or ~/.bashrc)"
}

main "$@"
