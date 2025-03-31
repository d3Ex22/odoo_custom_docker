#!/bin/bash

# -----------------------------------------------------------------------------
# Script to run pip inside the Odoo Docker container with forwarded arguments.
# Usage:
#   pip_odoo.sh install <package>
#   pip_odoo.sh list
#   pip_odoo.sh uninstall <package>
# -----------------------------------------------------------------------------

docker exec -it odoo pip "$@"
