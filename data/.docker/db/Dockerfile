ARG POSTGRES_VERSION=17
FROM postgres:${POSTGRES_VERSION}

# PostgreSQL versions par Odoo:
# Odoo 19.0: PostgreSQL 15-17
# Odoo 18.0: PostgreSQL 14-17
# Odoo 17.0: PostgreSQL 13-16
# Odoo 16.0: PostgreSQL 12-15
# Odoo 15.0: PostgreSQL 12-14

# Install pgvector extension (required for Odoo 17+)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-$PG_MAJOR-pgvector && \
    rm -rf /var/lib/apt/lists/*
