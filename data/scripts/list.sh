#!/bin/bash
docker exec db psql -d postgres -U odoo -c "\l"