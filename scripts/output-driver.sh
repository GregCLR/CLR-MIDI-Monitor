#!/bin/zsh
# Explicit setup step only. Never executed by app launch or packaging.
set -eu
cd "$(dirname "$0")/.."
driver='outputs/CLR Output Monitor.plugin'
destination="$HOME/Library/Audio/MIDI Drivers/CLR Output Monitor.plugin"
case "${1:-}" in
  install)
    [[ -d "$driver" ]] || { echo 'Build the driver first with scripts/build-driver.sh'; exit 1; }
    [[ ! -e "$destination" && ! -L "$destination" ]] || { echo 'A CLR driver is already installed; remove it before replacing it.'; exit 1; }
    codesign --verify --strict "$driver"
    mkdir -p "$(dirname "$destination")"
    ditto "$driver" "$destination"
    codesign --verify --strict "$destination"
    echo 'Installed CLR driver for this user. No MIDI-server restart was performed.'
    ;;
  uninstall)
    [[ -d "$destination" && ! -L "$destination" ]] || { echo 'No CLR driver installed at the expected path.'; exit 1; }
    archive="$HOME/Library/Application Support/CLR MIDI Monitor/Disabled Drivers/CLR Output Monitor-$(date +%Y%m%d-%H%M%S).plugin"
    mkdir -p "$(dirname "$archive")"
    mv "$destination" "$archive"
    echo "Moved driver out of CoreMIDI's discovery folder: $archive"
    echo 'Already-loaded driver code remains loaded until CoreMIDI next restarts naturally.'
    ;;
  *) echo 'Usage: scripts/output-driver.sh install|uninstall'; exit 2;;
esac
