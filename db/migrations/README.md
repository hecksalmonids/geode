# Geode: db/migrations

This folder contains database migration files.

When initializing a Geode instance with `rake init`, this folder will contain a blank migration named 
`TIMESTAMP_create_database.rb` which serves simply to initialize the database with the `:schema_migrations` table.