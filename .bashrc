# Auto-run wake_on_kvm.sh if it hasn't been run
if [ ! -f /var/log/wake_on_kvm.log ]; then
  echo "⚠️ wake_on_kvm.sh has not been run on this system."
  echo "🔄 Running wake_on_kvm.sh automatically..."
  
  # Get the directory where this .bashrc is located
  BASHRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WAKE_SCRIPT="$BASHRC_DIR/wake_on_kvm.sh"
  
  if [ -f "$WAKE_SCRIPT" ]; then
    # Run the script in the background to avoid blocking the shell
    nohup "$WAKE_SCRIPT" > /dev/null 2>&1 &
    echo "✅ wake_on_kvm.sh started in background"
  else
    echo "❌ wake_on_kvm.sh not found at $WAKE_SCRIPT"
  fi
fi

