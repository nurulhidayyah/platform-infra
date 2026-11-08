#!/bin/sh
# Role dan database sonarqube di Postgres platform. Jalan di container
# sonarqube-db setiap `make up`, sebelum SonarQube start; aman diulang, dan
# kata sandinya selalu diselaraskan dengan env/sonarqube.env.
set -eu
export PGHOST=platform-postgres PGUSER="$POSTGRES_USER" PGPASSWORD="$POSTGRES_PASSWORD" PGDATABASE=postgres
psql -v ON_ERROR_STOP=1 -qAt -v pw="$SONAR_JDBC_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE sonarqube LOGIN CONNECTION LIMIT 30'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sonarqube')\gexec
SELECT format('ALTER ROLE sonarqube PASSWORD %L', :'pw')\gexec
SELECT 'CREATE DATABASE sonarqube OWNER sonarqube'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sonarqube')\gexec
REVOKE CONNECT, TEMPORARY ON DATABASE sonarqube FROM PUBLIC;
SQL
echo "database sonarqube siap"
