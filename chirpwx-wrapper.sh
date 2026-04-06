#!/bin/bash
exec /app/bin/chirpwx.py --no-install-desktop-app --config-dir "$XDG_CONFIG_HOME" "$@"
