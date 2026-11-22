#!/bin/sh
# `factory <role> [args…]`: run the factory's LOGOS source on the pinned largo's interpreter.
# The project directory is read-only; everything the factory writes lives under MACSAD_WORK and
# MACSAD_RESULTS_DIR (/var/lib/macsad).
set -eu
cd /opt/macsad/factory
exec /usr/local/bin/largo run --interpret -- "$@"
