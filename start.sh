#!/bin/env bash
set -euo pipefail

# --- Utility Functions ---

# Function to display a message
display_message() {
  echo "$1"
}

# Function to prompt the user for input
get_user_input() {
  read -r -p "$1" response
  echo "$response"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# --- Installation and Configuration Functions ---

# Function to check OS type and install tmux if needed
check_and_install_tmux() {
  if ! command_exists tmux; then
    display_message "tmux not found. Installing..."

    # Detect operating system
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      # Linux distributions
      if command_exists apt-get; then
        display_message "Detected apt package manager"

        # Check if apt is locked and wait if needed
        apt_locked=true
        max_attempts=5
        attempt=1

        while $apt_locked && [ $attempt -le $max_attempts ]; do
          display_message "Attempt $attempt of $max_attempts to acquire apt lock..."

          # Check if apt is locked
          if sudo lsof /var/lib/apt/lists/lock > /dev/null 2>&1 || sudo lsof /var/lib/dpkg/lock > /dev/null 2>&1 || sudo lsof /var/lib/dpkg/lock-frontend > /dev/null 2>&1; then
            display_message "APT is locked by another process. Waiting 30 seconds before retrying..."
            if sudo lsof /var/lib/apt/lists/lock > /dev/null 2>&1; then
              display_message "Process holding apt lists lock:"
              sudo lsof /var/lib/apt/lists/lock
            fi
            if sudo lsof /var/lib/dpkg/lock > /dev/null 2>&1; then
              display_message "Process holding dpkg lock:"
              sudo lsof /var/lib/dpkg/lock
            fi
            sleep 30
            ((attempt++))
          else
            apt_locked=false
          fi
        done

        if $apt_locked; then
          display_message "Could not acquire apt lock after $max_attempts attempts."
          display_message "You may need to manually fix the lock issue with:"
          display_message "  sudo rm /var/lib/apt/lists/lock"
          display_message "  sudo rm /var/lib/dpkg/lock"
          display_message "  sudo rm /var/lib/dpkg/lock-frontend"
          display_message "WARNING: Only use these commands if you're sure no apt process is running!"
          display_message "Try installing tmux manually with: sudo apt-get install tmux"
          return 1
        fi

        # Proceed with installation
        sudo apt-get update && sudo apt-get install -y tmux
      elif command_exists dnf; then
        display_message "Detected dnf package manager"
        sudo dnf install -y tmux
      elif command_exists yum; then
        display_message "Detected yum package manager"
        sudo yum install -y tmux
      elif command_exists pacman; then
        display_message "Detected pacman package manager"
        sudo pacman -S --noconfirm tmux
      elif command_exists zypper; then
        display_message "Detected zypper package manager"
        sudo zypper install -y tmux
      else
        display_message "No supported package manager found. Please install tmux manually."
        return 1
      fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      if command_exists brew; then
        display_message "Detected Homebrew package manager"
        brew install tmux
      elif command_exists port; then
        display_message "Detected MacPorts package manager"
        sudo port install tmux
      else
        display_message "No supported package manager found on macOS."
        display_message "Please install Homebrew (https://brew.sh/) or MacPorts, then run this script again."
        return 1
      fi
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
      # Windows with Git Bash or similar
      display_message "Windows detected. Please install tmux manually or use WSL."
      return 1
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
      # FreeBSD
      sudo pkg install -y tmux
    else
      display_message "Unsupported operating system: $OSTYPE"
      return 1
    fi

    # Verify installation
    if ! command_exists tmux; then
      display_message "Failed to install tmux. Please install it manually."
      display_message "Checking if we can continue without tmux..."
      return 1
    else
      display_message "tmux installed successfully."
      return 0
    fi
  else
    display_message "tmux is already installed."
    return 0
  fi
}

# Function to check if we can continue without tmux
can_continue_without_tmux() {
  # Check for alternative terminal multiplexers
  if command_exists screen; then
    user_choice=$(get_user_input "Found 'screen' as an alternative to tmux. Would you like to use it instead? (y/n): ")
    if [[ "$user_choice" == "y" ]]; then
      display_message "Will use 'screen' instead of tmux."
      USE_SCREEN=true
      return 0
    fi
  fi

  user_choice=$(get_user_input "This script can run multiple services without terminal multiplexing, but you'll need to open separate terminals.  Would you like to continue? (y/n): ")
  if [[ "$user_choice" == "y" ]]; then
    display_message "Continuing without terminal multiplexing."
    return 0
  else
    display_message "Exiting as requested."
    return 1
  fi
}

# Function to check if virtual environment exists and create if needed
check_virtual_env() {
  local venv_dir="$1"
  local venv_activate="$2"
  local requirements="$3"

  if [[ ! -f "$venv_activate" ]]; then
    display_message "Virtual environment not found at $venv_dir, creating..."
    # Check if python3 is installed
    if command_exists python3; then
      python3 -m venv "$venv_dir"
    elif command_exists python; then
      python -m venv "$venv_dir"
    else
      display_message "Python not found. Please install Python 3."
      exit 1
    fi
  fi

  # Check if requirements file exists
  if [[ ! -f "$requirements" ]]; then
    display_message "Warning: Requirements file ($requirements) not found."
    # Create an empty requirements.txt file to prevent errors
    touch "$requirements"
  fi
}

# Function to check and install Bun if needed
check_and_install_bun() {
  if ! command_exists bun; then
    user_choice=$(get_user_input "Bun not found. Would you like to install it? (y/n): ")

    if [[ "$user_choice" != "y" ]]; then
      display_message "Skipping Bun installation."
      return 1
    fi

    display_message "Installing Bun..."

    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
      # macOS or Linux
      if command_exists curl; then
        curl -fsSL https://bun.sh/install | bash
        # Source the updated profile to make bun available in the current session
        if [[ -f "$HOME/.bashrc" ]]; then
          source "$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
          source "$HOME/.zshrc"
        fi
        # Also try to export the PATH directly
        export PATH="$HOME/.bun/bin:$PATH"
      elif command_exists wget; then
        wget -qO- https://bun.sh/install | bash
        # Source the updated profile to make bun available in the current session
        if [[ -f "$HOME/.bashrc" ]]; then
          source "$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
          source "$HOME/.zshrc"
        fi
        # Also try to export the PATH directly
        export PATH="$HOME/.bun/bin:$PATH"
      else
        display_message "Neither curl nor wget found. Please install either curl or wget first, then run this script again."
        display_message "Checking for alternative JS runtimes..."
        return 1
      fi
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
      # Windows - prefer wget
      if command_exists wget; then
        wget -qO- https://bun.sh/install | bash
      elif command_exists curl; then
        curl -fsSL https://bun.sh/install | bash
      else
        display_message "Neither wget nor curl found. Please install either wget or curl first, then run this script again."
        display_message "Checking for alternative JS runtimes..."
        return 1
      fi
    else
      display_message "Unsupported operating system for automatic Bun installation."
      display_message "Please install Bun manually: https://bun.sh/docs/installation"
      display_message "Checking for alternative JS runtimes..."
      return 1
    fi

    # Try to find bun in its installation directory if it's not in PATH
    if ! command_exists bun; then
      if [[ -f "$HOME/.bun/bin/bun" ]]; then
        display_message "Found Bun at $HOME/.bun/bin/bun"
        export PATH="$HOME/.bun/bin:$PATH"
      fi
    fi

    # Verify installation
    if ! command_exists bun; then
      display_message "Failed to install Bun. Please install it manually: https://bun.sh/docs/installation"
      display_message "Checking for alternative JS runtimes..."
      return 1
    else
      display_message "Bun installed successfully."
      return 0
    fi
  else
    display_message "Bun is already installed."
    return 0
  fi
}

# Function to determine the best available JS runtime/package manager
detect_js_runtime() {
  # Prefer Bun if available
  if command_exists bun; then
    echo "bun"
    return
  fi

  # Check if Bun is installed but not in PATH
  if [[ -f "$HOME/.bun/bin/bun" ]]; then
    export PATH="$HOME/.bun/bin:$PATH"
    echo "bun"
    return
  fi

  # Check for other package managers in order of preference
  if command_exists pnpm; then
    echo "pnpm"
    return
  fi

  if command_exists yarn; then
    echo "yarn"
    return
  fi

  if command_exists npm; then
    echo "npm"
    return
  fi

  echo "none"
}

# --- Service Startup Functions ---

# Function to start frontend service
start_frontend() {
  display_message "Starting Frontend service..."
  cd "$FRONTEND_DIR" || exit 1
  case "$JS_RUNTIME" in
  "bun")
bun install && bun run build && bun start
    ;;
  "pnpm")
    pnpm install && pnpm run build && pnpm start
    ;;
  "yarn")
    yarn install && yarn build && yarn start
    ;;
  "npm")
    npm install && npm run build && npm start
    ;;
  esac
}

# Function to start backend service
start_backend() {
  display_message "Starting Backend service..."
  cd "$BACKEND_DIR" || exit 1

  if [[ ! -d "$BACKEND_DIR" ]]; then
    display_message "Backend directory does not exist."
    return 1
  fi
  # Check if requirements.txt exists, if not create it

  source "$BACKEND_VENV" && pip install -r requirements.txt && python main.py
}

# Function to start server service
start_server() {
  display_message "Starting Server service..."
  cd "$SERVER_DIR" || exit 1
  case "$JS_RUNTIME" in
  "bun")
    # Check if package.json exists and has start script
    if ! grep -q '"start"' package.json 2>/dev/null; then
      display_message "Warning: No start script found in package.json"
      bun install && bun run dev
    else
      bun install && bun start
    fi
    ;;
  "pnpm")
    pnpm install && pnpm start
    ;;
  "yarn")
    yarn install && yarn start
    ;;
  "npm")
    npm install && npm start
    ;;
  esac
}

# Function to start ML service
start_ml() {
  display_message "Starting ML service..."
  cd "$ML_DIR" || exit 1

  if [[ ! -d "$ML_DIR" ]]; then
    display_message "ML directory does not exist."
    return 1
  fi
  # Check if train.py exists, if not create a simple version

# Function to start all services without tmux
start_all_with_bg() {
  display_message "Starting all services in background. Press Ctrl+C to stop all services."

  # Start frontend in background
  (
    cd "$FRONTEND_DIR" && case "$JS_RUNTIME" in
    "bun") bun install && bun run build && bun run start;;
    "pnpm") pnpm install && pnpm run build && pnpm start;;
    "yarn") yarn install && yarn build && yarn start;;
    "npm") npm install && npm run build && npm start;;
    esac
  ) &
  FRONTEND_PID=$!

  # Check if backend requirements.txt exists, if not create it
  if [[ ! -f "$BACKEND_DIR/requirements.txt" ]]; then
    mkdir -p "$BACKEND_DIR"
    touch "$BACKEND_DIR/requirements.txt"
    display_message "Created empty requirements.txt file for backend"
  fi

  # Start backend in background
  (
    cd "$BACKEND_DIR" && source "$BACKEND_VENV" && 
    pip install -r requirements.txt && 
    python main.py
  ) &
  BACKEND_PID=$!

  if [[ -f "$SERVER_DIR/package.json" ]] && ! grep -q '"start"' "$SERVER_DIR/package.json" 2>/dev/null; then
    # Start server with dev command
    (cd "$SERVER_DIR" && case "$JS_RUNTIME" in
      "bun") bun install && bun run dev;;
      "pnpm") pnpm install && pnpm run dev;;
      "yarn") yarn install && yarn dev;;
      "npm") npm install && npm run dev;;
      esac) &
  else
    # Start server normally
    (cd "$SERVER_DIR" && case "$JS_RUNTIME" in
      "bun") bun install && bun start;;
      "pnpm") pnpm install && pnpm start;;
      "yarn") yarn install && yarn start;;
      "npm") npm install && npm start;;
      esac) &
  fi
  else
    # Start server normally
    (
      cd "$SERVER_DIR" && case "$JS_RUNTIME" in
      "bun") bun install && bun start;;
      "pnpm") pnpm install && pnpm start;;
      "yarn") yarn install && yarn start;;
      "npm") npm install && npm start;;
      esac
    ) &
  fi
  SERVER_PID=$!

  # Check if ML train.py exists, if not create a simple version
  if [[ ! -f "$ML_DIR/train.py" ]]; then
    mkdir -p "$ML_DIR"
    cat > "$ML_DIR/train.py" << 'EOF'
# Simple placeholder train.py
print("ML service started")
while True:
    # Keep the service running
    import time
    time.sleep(10)
EOF
    display_message "Created placeholder train.py file for ML service"
  fi

  # Check if ML requirements.txt exists, if not create it
  if [[ ! -f "$ML_DIR/requirements.txt" ]]; then
    mkdir -p "$ML_DIR"
    touch "$ML_DIR/requirements.txt"
    display_message "Created empty requirements.txt file for ML service"
  fi

  # Start ML service in background
  (cd "$ML_DIR" && source "$ML_VENV" && pip install -r requirements.txt && python train.py) &
  ML_PID=$!

  display_message "All services started with PIDs:"
  display_message "Frontend: $FRONTEND_PID"
  display_message "Backend: $BACKEND_PID"
  display_message "Server: $SERVER_PID"
  display_message "ML: $ML_PID"

  # Function to handle script termination
  cleanup() {
    display_message "Stopping all services..."
    kill $FRONTEND_PID $BACKEND_PID $SERVER_PID $ML_PID 2>/dev/null
    wait
    display_message "All services stopped."
    exit 0
  }

  # Set up the trap for clean exit
  trap cleanup SIGINT SIGTERM

  # Keep script running
  display_message "Press Ctrl+C to stop all services"
  wait
}

# Function to run all services with GNU Screen
start_all_with_screen() {
  SESSION="mono_repo"

  # Kill any existing session
  screen -X -S $SESSION quit 2>/dev/null

  # Start a new screen session
  screen -dmS $SESSION

  # Start frontend
  screen -S $SESSION -X screen -t "frontend"
  screen -S $SESSION -p "frontend" -X stuff "cd $FRONTEND_DIR && case \"\$JS_RUNTIME\" in
        \"bun\") bun install && bun run build && bun run start;;
        \"pnpm\") pnpm install && pnpm run build && pnpm start;;
        \"yarn\") yarn install && yarn build && yarn start;;
        \"npm\") npm install && npm run build && npm start;;
    esac\n"

  # Check if backend requirements.txt exists, if not create it
  if [[ ! -f "$BACKEND_DIR/requirements.txt" ]]; then
    mkdir -p "$BACKEND_DIR"
    touch "$BACKEND_DIR/requirements.txt"
  fi

  # Start backend
  screen -S $SESSION -X screen -t "backend"
  screen -S $SESSION -p "backend" -X stuff "cd $BACKEND_DIR && source $BACKEND_VENV && pip install -r requirements.txt && python main.py\n"

  # Check if server package.json has start script
  start_cmd="start"
  if [[ -f "$SERVER_DIR/package.json" ]] && ! grep -q '"start"' "$SERVER_DIR/package.json" 2>/dev/null; then
    start_cmd="dev"
  fi

  # Start server
  screen -S $SESSION -X screen -t "server"
  screen -S $SESSION -p "server" -X stuff "cd $SERVER_DIR && case \"\$JS_RUNTIME\" in
        \"bun\") bun install && bun run $start_cmd;;
        \"pnpm\") pnpm install && pnpm run $start_cmd;;
        \"yarn\") yarn install && yarn $start_cmd;;
        \"npm\") npm install && npm run $start_cmd;;
    esac\n"

  # Check if ML train.py exists, if not create a simple version
  if [[ ! -f "$ML_DIR/train.py" ]]; then
    mkdir -p "$ML_DIR"
    cat > "$ML_DIR/train.py" << 'EOF'
# Simple placeholder train.py
print("ML service started")
while True:
    # Keep the service running
    import time
    time.sleep(10)
EOF
  fi

  # Check if ML requirements.txt exists, if not create it
  if [[ ! -f "$ML_DIR/requirements.txt" ]]; then
    mkdir -p "$ML_DIR"
    touch "$ML_DIR/requirements.txt"
  fi

  # Start ML
  screen -S $SESSION -X screen -t "ml"
  screen -S $SESSION -p "ml" -X stuff "cd $ML_DIR && source $ML_VENV && pip install -r requirements.txt && python train.py\n"

  # Display a message
  display_message "Starting mono repo development environment with screen..."
  display_message "Using $JS_RUNTIME as JavaScript runtime"
  display_message "Use 'screen -r $SESSION' to reconnect if detached."

  # Attach to the session
  screen -r $SESSION
}

# --- Main Script ---

# Set default values
USE_TMUX=false
USE_SCREEN=false

# Define project paths
PROJECT_ROOT=$(pwd)
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BACKEND_DIR="$PROJECT_ROOT/backend"
SERVER_DIR="$PROJECT_ROOT/server"
ML_DIR="$PROJECT_ROOT/ml"

# Define virtual environment paths
BACKEND_VENV_DIR="${BACKEND_VENV_DIR:-$BACKEND_DIR/venv}"
ML_VENV_DIR="${ML_VENV_DIR:-$ML_DIR/venv}"
BACKEND_VENV="$BACKEND_VENV_DIR/bin/activate"
ML_VENV="$ML_VENV_DIR/bin/activate"

# Check if directories exist
for dir in "$FRONTEND_DIR" "$BACKEND_DIR" "$SERVER_DIR" "$ML_DIR"; do
  if [[ ! -d "$dir" ]]; then
    while true; do
      user_choice=$(get_user_input "Warning: Directory $dir does not exist. Would you like to create it? (y/n): ")
      case $user_choice in
        [yY])
          mkdir -p "$dir"
          display_message "Created $dir"
          break
          ;;
        [nN])
          display_message "Skipping $dir"
          break
          ;;
        *)
          display_message "Invalid input. Please enter 'y' or 'n'."
          ;;
      esac
    done
  fi
done

# Check virtual environments
check_virtual_env "$BACKEND_VENV_DIR" "$BACKEND_VENV" "$BACKEND_DIR/requirements.txt"
check_virtual_env "$ML_VENV_DIR" "$ML_VENV" "$ML_DIR/requirements.txt"

# Attempt to install Bun (preferred runtime)
check_and_install_bun

# Determine JS runtime to use
JS_RUNTIME=$(detect_js_runtime)
display_message "Using $JS_RUNTIME as JavaScript runtime"

if [[ "$JS_RUNTIME" == "none" ]]; then
  display_message "No JavaScript runtime found. Please install Bun (preferred), npm, yarn, or pnpm."
  exit 1
fi

# Main menu
while true; do
  clear
  display_message "============================================"
  display_message "      Mono Repo Development Environment     "
  display_message "============================================"
  display_message "Available services:"
  display_message "1) Frontend"
  display_message "2) Backend"
  display_message "3) Server"
  display_message "4) ML"
  display_message "5) All services"
  display_message "6) Configure"
  display_message "7) Exit"
  display_message "============================================"
  display_message "Current settings:"
  display_message "- JavaScript runtime: $JS_RUNTIME"
  if $USE_TMUX; then
    display_message "- Terminal multiplexer: tmux"
  elif $USE_SCREEN; then
    display_message "- Terminal multiplexer: screen"
  else
    display_message "- Terminal multiplexer: none"
  fi
  display_message "============================================"

  menu_choice=$(get_user_input "Select an option: ")

  case $menu_choice in
  1)
    start_frontend
    ;;
  2)
    start_backend
    ;;
  3)
    start_server
    ;;
  4)
    start_ml
    ;;
  5)
    # Start all services
    if $USE_TMUX; then
      # Using tmux
      SESSION="mono_repo"

      # Kill any existing session
      tmux kill-session -t "$SESSION" 2>/dev/null

      # Create a new session
      tmux new-session -d -s "$SESSION"

      # Start frontend
      tmux rename-window -t "$SESSION" "frontend"
      case "$JS_RUNTIME" in
      "bun")
        tmux send-keys -t "$SESSION" "cd $FRONTEND_DIR && bun install && bun run build && bun run start" C-m
        ;;
      "pnpm")
        tmux send-keys -t "$SESSION" "cd $FRONTEND_DIR && pnpm install && pnpm run build && pnpm start" C-m
        ;;
      "yarn")
        tmux send-keys -t "$SESSION" "cd $FRONTEND_DIR && yarn install && yarn build && yarn start" C-m
        ;;
      "npm")
        tmux send-keys -t "$SESSION" "cd $FRONTEND_DIR && npm install && npm run build && npm start" C-m
        ;;
      esac

      # Check if backend requirements.txt exists, if not create it
      if [[ ! -f "$BACKEND_DIR/requirements.txt" ]]; then
        mkdir -p "$BACKEND_DIR"
        touch "$BACKEND_DIR/requirements.txt"
      fi

      # Start backend (Python)
      tmux new-window -t "$SESSION" -n "backend"
      tmux send-keys -t "$SESSION" "cd $BACKEND_DIR && source $BACKEND_VENV && pip install -r requirements.txt && python main.py" C-m

      # Check if server package.json has start script
      start_cmd="start"
      if [[ -f "$SERVER_DIR/package.json" ]] && ! grep -q '"start"' "$SERVER_DIR/package.json" 2>/dev/null; then
        start_cmd="dev"
      fi

      # Start server
      tmux new-window -t "$SESSION" -n "server"
      case "$JS_RUNTIME" in
      "bun")
        tmux send-keys -t "$SESSION" "cd $SERVER_DIR && bun install && bun run $start_cmd" C-m
        ;;
      "pnpm")
        tmux send-keys -t "$SESSION" "cd $SERVER_DIR && pnpm install && pnpm run $start_cmd" C-m
        ;;
      "yarn")
        tmux send-keys -t "$SESSION" "cd $SERVER_DIR && yarn install && yarn $start_cmd" C-m
        ;;
      "npm")
        tmux send-keys -t "$SESSION" "cd $SERVER_DIR && npm install && npm run $start_cmd" C-m
        ;;
      esac

      # Check if ML train.py exists, if not create a simple version
      if [[ ! -f "$ML_DIR/train.py" ]]; then
        mkdir -p "$ML_DIR"
        cat > "$ML_DIR/train.py" << 'EOF'
# Simple placeholder train.py
print("ML service started")
while True:
    # Keep the service running
    import time
    time.sleep(10)
EOF
      fi

      # Check if ML requirements.txt exists, if not create it
      if [[ ! -f "$ML_DIR/requirements.txt" ]]; then
        mkdir -p "$ML_DIR"
        touch "$ML_DIR/requirements.txt"
      fi

      # Start ML (Python)
      tmux new-window -t "$SESSION" -n "ml"
      tmux send-keys -t "$SESSION" "cd $ML_DIR && source $ML_VENV && pip install -r requirements.txt && python train.py" C-m

      # Set default window to frontend
      tmux select-window -t "$SESSION:0"

      # Display a message
      display_message "Starting mono repo development environment with tmux..."
      display_message "Using $JS_RUNTIME as JavaScript runtime"
      display_message "Use 'tmux attach-session -t $SESSION' to reconnect if detached."

      # Attach to the session
      tmux attach-session -t "$SESSION"
    elif $USE_SCREEN; then
      start_all_with_screen
    else
      start_all_with_bg
    fi
    ;;
  6)
    # Configuration submenu
    while true; do
      clear
      display_message "============================================"
      display_message "            Configuration Menu              "
      display_message "============================================"
      display_message "1) Change JavaScript runtime"
      display_message "2) Toggle terminal multiplexer"
      display_message "3) Back to main menu"
      display_message "============================================"

      config_choice=$(get_user_input "Select an option: ")

      case $config_choice in
      1)
        display_message "Select JavaScript runtime:"
        display_message "1) Bun (recommended)"
        display_message "2) pnpm"
        display_message "3) yarn"
        display_message "4) npm"

        runtime_choice=$(get_user_input "Select runtime: ")

        case $runtime_choice in
        1)
          if command_exists bun; then
            JS_RUNTIME="bun"
          else
        runtime_choice=$(get_user_input "Select runtime: ")
          fi
          ;;
        2)
          if command_exists pnpm; then
            JS_RUNTIME="pnpm"
          else
            display_message "pnpm not found. Please install it first."
            read -p "Press Enter to continue..."
          fi
          ;;
        3)
          if command_exists yarn; then
            JS_RUNTIME="yarn"
          else
            display_message "yarn not found. Please install it first."
            read -p "Press Enter to continue..."
          fi
          ;;
        4)
          if command_exists npm; then
            JS_RUNTIME="npm"
          else
            display_message "npm not found. Please install it first."
            read -p "Press Enter to continue..."
          fi
          ;;
        *)
          display_message "Invalid choice."
          read -p "Press Enter to continue..."
          ;;
        esac
        ;;
      2)
        display_message "Select terminal multiplexer:"
        display_message "1) tmux (recommended)"
        display_message "2) screen"
        display_message "3) none (use background processes)"

        multi_choice=$(get_user_input "Select multiplexer: ")

        case $multi_choice in
        1)
          if command_exists tmux; then
            USE_TMUX=true
            USE_SCREEN=false
          else
            check_and_install_tmux && USE_TMUX=true && USE_SCREEN=false
          fi
          ;;
        2)
          if command_exists screen; then
            USE_TMUX=false
            USE_SCREEN=true
          else
            display_message "screen not found. Please install it first."
            read -p "Press Enter to continue..."
          fi
          ;;
        3)
          USE_TMUX=false
          USE_SCREEN=false
          ;;
        *)
          display_message "Invalid choice."
          read -p "Press Enter to continue..."
          ;;
        esac
        ;;
      3)
        break
        ;;
      *)
        display_message "Invalid choice."
        read -p "Press Enter to continue..."
        ;;
      esac
    done
    ;;
  7)
    display_message "Exiting..."
    exit 0
    ;;
  *)
    display_message "Invalid choice."
    read -p "Press Enter to continue..."
    ;;
  esac
done