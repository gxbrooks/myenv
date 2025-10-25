# Notify if wake_on_kvm.sh hasn't been run
if [ ! -f /var/log/wake_on_kvm.log ]; then
  echo "⚠️ wake_on_kvm.sh has not been run on this system."
fi

