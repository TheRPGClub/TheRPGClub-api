-- The application role running this script owns both local databases. Keeping
-- the test database separate lets Rails safely create, purge, and migrate it.
CREATE DATABASE rpgclub_api_test;
