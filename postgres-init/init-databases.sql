-- PostgreSQL init script
-- Runs automatically on first boot via /docker-entrypoint-initdb.d/
-- Creates the two application databases alongside the default 'default_db'

CREATE DATABASE n8n_backend;
CREATE DATABASE project_data;
