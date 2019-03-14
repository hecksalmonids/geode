# Required gems across the entire framework
require 'bundler/setup'

# Required gems and files across the CLI
require 'thor'
require 'irb'
require 'sequel'
require_relative 'geode/generator'
Sequel.extension :inflector, :migration, :schema_dumper

# Set database path as environment variable
ENV['DB_PATH'] = File.expand_path('db/data.db')

# Geode's main CLI; contains tasks related to Geode functionality
class Geode < Thor
  # Throws exit code 1 on errors
  def self.exit_on_failure?
    true
  end

  # Throws an error if an unknown flag is provided
  check_unknown_options!

  map %w(-r -s) => :start
  desc 'start [-d], [-a], [--load-only=one two three]', 'Load crystals and start the bot'
  long_desc <<~LONG_DESC.strip
  Loads crystals and starts the bot. With no options, this loads only the crystals in main.
  
  Note: If two crystals with the same name are found by --load-only, an error will be thrown as crystals must
  have unique names.
  LONG_DESC
  option :dev, type:    :boolean,
               aliases: '-d',
               desc:    'Loads dev crystals instead of main'
  option :all, type:    :boolean,
               aliases: '-a',
               desc:    'Loads all crystals (main and dev)'
  option :load_only, type: :array,
                     desc: 'Loads only the given crystals (searching both main and dev)'
  def start
    # Validates that only one option is given
    raise Error, 'ERROR: Only one of -d, -a and --load-only can be given' if options.count { |_k, v| v } > 1

    # Selects the crystals to load, throwing an error if a crystal given in load_only is not found
    if options[:dev]
      ENV['CRYSTALS_TO_LOAD'] = Dir['app/dev/*.rb'].join(',')
    elsif options[:all]
      ENV['CRYSTALS_TO_LOAD'] = (Dir['app/main/*.rb'] + Dir['app/dev/*.rb']).join(',')
    elsif options[:load_only]
      all_crystal_paths = Dir['app/main/*.rb'] + Dir['app/dev/*.rb']
      ENV['CRYSTALS_TO_LOAD'] = options[:load_only].map do |crystal_name|
        if (paths = all_crystal_paths.select { |p| File.basename(p, '.*').camelize == crystal_name }).empty?
          raise Error, "ERROR: Crystal #{crystal_name} not found"
        elsif paths.size > 1
          raise Error, "ERROR: Multiple crystals with name #{crystal_name} found"
        else paths[0]
        end
      end.join(',')
    else
      ENV['CRYSTALS_TO_LOAD'] = Dir['app/main/*.rb'].join(',')
    end

    # Loads the bot script
    load File.expand_path('app/bot.rb')
  end

  desc 'generate {crystal|model|migration} ARGS', 'Generate a Geode crystal, model or migration'
  long_desc <<~LONG_DESC.strip
  Generates a Geode crystal, model or migration.

  When generating a crystal, the format is 
  'generate crystal [-m], [--main], [--without-commands], [--without-events] names...'
  \x5When generating a model, the format is 'generate model name [fields...]'
  \x5When generating a migration, the format is 'generate migration [--with-up-down] name'

  If a model is being generated, the model's fields should be included in the format 'name:type'
  (i.e. generate model name:string number:integer), similar to Rails.
  \x5The allowed field types are: #{Generators::ModelGenerator::VALID_FIELD_TYPES.join(', ')}
  LONG_DESC
  option :main, type:    :boolean,
         aliases: '-m',
         desc:    'Generates a crystal in the main folder instead of dev (crystal generation only)'
  option :without_commands, type: :boolean,
         desc: 'Generates a crystal without a CommandContainer (crystal generation only)'
  option :without_events, type: :boolean,
         desc: 'Generates a crystal without an EventContainer (crystal generation only)'
  option :with_up_down, type: :boolean,
         desc: 'Generates a migration with up/down blocks instead of a change block (migration generation only)'
  def generate(type, *args)
    # Cases generation type
    case type
    when 'crystal'
      # Validates that --with-up-down is not given when a crystal is being generated
      raise Error, 'ERROR: Option --with-up-down should not be given when generating a crystal' if options[:with_up_down]

      # Validates that both of --without-events and --without-commands are not given
      if options[:without_events] && options[:without_commands]
        raise Error, 'ERROR: Only one of --without-events, --without-commands can be given'
      end

      # Iterates through the given names and generates crystals for each
      args.each do |crystal_name|
        generator = Generators::CrystalGenerator.new(
            crystal_name,
            without_commands: options[:without_commands],
            without_events: options[:without_events]
        )
        generator.generate_in(options[:main] ? 'app/main' : 'app/dev')
      end

    when 'model'
      # Validates that none of the options are given when a model is being generated
      raise Error, 'ERROR: No options should be given when generating a model' unless options.empty?

      name = args[0]
      fields = args[1..-1]

      # Validates that a name is given
      raise Error, 'ERROR: Model name must be given' unless name

      # If fields were given, validates that they have the correct format and the type is valid
      # and maps the array to the correct format for the generator
      if fields
        fields.map! do |field_str|
          unless (field_name, field_type = field_str.split(':')).size == 2
            raise Error, "ERROR: #{field_str} is not in the correct format of name:type"
          end
          unless Generators::ModelGenerator::VALID_FIELD_TYPES.include?(field_type)
            raise Error, "ERROR: #{field_str} has an invalid type"
          end
          [field_name, field_type]
        end

        # If fields were not given, sets fields equal to an empty array
      else
        fields = []
      end

      # Generates model
      generator = Generators::ModelGenerator.new(name, fields)
      generator.generate_in 'app/models', 'db/migrations'

    when 'migration'
      # Validates that no invalid option is given when generating a migration
      raise Error, 'ERROR: Option -m, --main should not be given when generating a migration' if options[:main]
      raise Error, 'ERROR: Option --without-commands should not be given when generating a migration' if options[:without_commands]
      raise Error, 'ERROR: Option --without-events should not be given when generating a migration' if options[:without_events]

      # Validates that exactly one argument (the migration name) is given
      raise Error, 'ERROR: Migration name must be given' if args.size < 1
      raise Error, 'ERROR: Only one migration name can be given' if args.size > 1

      # Generates migration
      generator = Generators::MigrationGenerator.new(args[0], with_up_down: options[:with_up_down])
      generator.generate_in 'db/migrations'

    else raise Error, 'ERROR: Generation type must be crystal, model or migration'
    end
  end

  desc 'destroy {crystal|model|migration} NAME(S)', 'Destroy Geode crystals, models or migrations'
  long_desc <<~LONG_DESC.strip
  Destroys a Geode crystal, model or migration. 
  Destruction of models must be done one at a time; however multiple crystals or migrations may be deleted at a time.

  When destroying a model, the migration that created its table and every migration afterward will be deleted 
  provided the model's table does not already exist in the database; otherwise, a new migration will be created 
  that drops the model's table.

  When destroying migrations, provide either the version number or name.

  Note: Destroying migrations is unsafe; avoid doing it unless you are sure of what you are doing.
  LONG_DESC
  def destroy(type, *args)
    # Validates that arguments have been given
    raise Error, 'ERROR: At least one name must be given' if args.empty?

    # Cases destruction type
    case type
    when 'crystal'
      all_crystal_paths = Dir['app/main/*.rb'] + Dir['app/dev/*.rb']

      # Validates that crystals with the given names all exist and gets their file paths
      crystals_to_delete = args.map do |crystal_name|
        if (crystal_path = all_crystal_paths.find { |p| File.basename(p, '.*').camelize == crystal_name })
          [crystal_name, crystal_path]
        else raise Error, "ERROR: Crystal #{crystal_name} not found"
        end
      end

      # Deletes all given crystals, printing deletions to console
      crystals_to_delete.each do |crystal_name, crystal_path|
        File.delete(crystal_path)
        puts "- Deleted crystal #{crystal_name}"
      end

    when 'model'
      # Validates that only one model name is given
      raise Error, 'ERROR: Only one model can be deleted at a time' unless args.size == 1

      model_name = args[0]

      # Validates that model exists
      raise Error, "ERROR: Model #{model_name} not found" unless File.exists?("app/models/#{model_name.underscore}.rb")

      # Deletes model, printing deletion to console
      File.delete("app/models/#{model_name.underscore}.rb")
      puts "- Deleted model file for model #{model_name}"

      # Loads the database
      Sequel.sqlite(ENV['DB_PATH']) do |db|
        # If model's table exists in the database, generates new migration dropping the model's table
        if db.table_exists?(model_name.tableize.to_sym)
          generator = Generators::DestroyModelMigrationGenerator.new(model_name, db)
          generator.generate_in('db/migrations')

        # Otherwise, deletes the migration adding the model's table and every migration that follows
        else
          initial_migration_index = Dir['db/migrations/*.rb'].index do |path|
            path.include? "add_#{model_name.tableize}_table_to_database"
          end

          Dir['db/migrations/*.rb'][initial_migration_index..-1].each do |migration_path|
            migration_name = File.basename(migration_path)[15..-4].camelize
            migration_version = File.basename(migration_path).to_i
            File.delete(migration_path)
            puts "- Deleted migration version #{migration_version} (#{migration_name})"
          end
        end
      end

    when 'migration'
      all_migration_paths = Dir['db/migrations/*.rb']

      # Validates that migrations with the given names or versions all exist and gets their names, versions
      # and file paths
      migrations_to_delete = args.map do |migration_key|
        migration_path = all_migration_paths.find do |path|
          filename = File.basename(path)
          filename.to_i == migration_key.to_i || filename[15..-4].camelize == migration_key
        end

        if (migration_path)
          migration_name = File.basename(migration_path)[15..-4].camelize
          migration_version = File.basename(migration_path).to_i
          [migration_name, migration_version, migration_path]
        else raise Error, "ERROR: Migration #{migration_key} not found"
        end
      end

      # Deletes all given migrations, printing deletions to console
      migrations_to_delete.each do |migration_name, migration_version, migration_path|
        File.delete(migration_path)
        puts "- Deleted migration version #{migration_version} (#{migration_name})"
      end
    end
  end
end

# Geode's database management; contains tasks related to modifying the database
class Database < Thor
  namespace :db

  # Throws exit code 1 on errors
  def self.exit_on_failure?
    true
  end

  # Throws an error if an unknown flag is provided
  check_unknown_options!

  desc 'migrate [--version=N], [-s]', "Migrate this Geode's database or display migration status"
  long_desc <<~LONG_DESC.strip
  Migrates this Geode's database, or displays migration status. With no options, the database is migrated to the latest.

  When --version is specified, the number given should be the timestamp of the migration.

  When displaying migration status with -s, the current migration will be displayed along with how many 
  migrations behind the latest the database is currently on.
  LONG_DESC
  option :version, type: :numeric,
                   desc: 'Migrates the database to the given version'
  option :status, type:    :boolean,
                  aliases: '-s',
                  desc:    'Checks the current status of migrations'
  def migrate
    # Loads the database
    Sequel.sqlite(ENV['DB_PATH']) do |db|
      # Validates that both version and status are not given at the same time
      raise Error, 'ERROR: Only one of --version, -s can be given at a time' if options[:version] && options[:status]

      # If version is given:
      if options[:version]
        # Validates that the given version exists
        unless (file_path = Dir['db/migrations/*.rb'].find { |f| File.basename(f).to_i == options[:version] })
          raise Error, "ERROR: Migration version #{options[:version]} not found"
        end

        filename = File.basename(file_path)

        # Migrates the database to the given version
        Sequel::Migrator.run(db, 'db/migrations', target: options[:version])

        # Regenerates schema
        generator = Generators::SchemaGenerator.new(db)
        generator.generate_in('db')

        puts "+ Database migrated to version #{options[:version]} (#{filename[15..-4].camelize})"

      # If status is given, responds with migration status:
      elsif options[:status]
        filename = db[:schema_migrations].order(:filename).last[:filename]
        migration_name = filename[15..-4].camelize
        version_number = filename.to_i

        puts "Database on migration #{migration_name} (version #{version_number})"
        if Sequel::Migrator.is_current?(db, 'db/migrations')
          puts 'Database is on latest migration'
        else
          all_migration_files =  Dir['db/migrations/*.rb'].map { |p| File.basename(p) }
          unmigrated_count = (all_migration_files - db[:schema_migrations].map(:filename)).count
          puts "Database #{unmigrated_count} migration#{unmigrated_count == 1 ? nil : 's'} behind latest"
        end

      # If no options are given, migrate to latest and regenerate schema:
      else
        Sequel::Migrator.run(db, 'db/migrations', options)
        filename = db[:schema_migrations].order(:filename).last[:filename]
        migration_name = filename[15..-4].camelize
        version_number = filename.to_i
        generator = Generators::SchemaGenerator.new(db)
        generator.generate_in('db')
        puts "+ Database migrated to latest version #{version_number} (#{migration_name})"
      end
    end
  end

  desc 'rollback [--step=N]', 'Revert migrations from the database'
  long_desc <<~LONG_DESC.strip
  Reverts a number of migrations from the database. With no options, only one migration is rolled back.

  --step will throw an error if the number of migrations to be rolled back is greater than the number of
  migrations already run.
  LONG_DESC
  option :step, type: :numeric,
                desc: 'Reverts the given number of migrations'
  def rollback
    # Loads the database
    Sequel.sqlite(ENV['DB_PATH']) do |db|
      # Validates that the steps to rollback is not greater than the completed migrations
      if options[:step]
        migration_count = db[:schema_migrations].count
        if options[:step] > migration_count
          raise Error, "ERROR: Number of migrations to rollback less than #{options[:step] || 1}"
        end
      end

      filename = db[:schema_migrations].order(:filename).map(:filename)[options[:step] ? -options[:step] - 1 : -2]
      migration_name = filename[15..-4].camelize
      version_number = filename.to_i

      # Rolls back the database to the given version
      Sequel::Migrator.run(db, 'db/migrations', target: version_number)

      # Regenerates schema
      generator = Generators::SchemaGenerator.new(db)
      generator.generate_in('db')

      puts "+ Database rolled back to version #{version_number} (#{migration_name})"
    end
  end

  desc 'console [--load-only=one two three]', 'Load an IRB console that allows database interaction'
  long_desc <<~LONG_DESC.strip
  Loads an IRB console that allows interaction with the Geode's database and model classes.
  \x5The Bot::Models module is included in the IRB shell; no need to call the full class name 
  to work with a model class.

  When --load-only is given, only the given model classes will be loaded.
  LONG_DESC
  option :load_only, type: :array,
                     desc: 'Loads only the given model classes.'
  def console
    # Validates that all given models exist if load_only is given
    if options[:load_only]
      options[:load_only].each do |model_name|
        if Dir['app/models/*.rb'].none? { |p| File.basename(p, '.*').camelize == model_name }
          raise Error, "ERROR: Model #{model_name} not found"
        end
      end
    end

    # Defines MODELS_TO_LOAD environment variable
    ENV['MODELS_TO_LOAD'] = if options[:load_only]
                              options[:load_only].join(',')
                            else Dir['app/models/*.rb'].map { |p| File.basename(p, '.*').camelize }.join(',')
                            end

    # Loads IRB console script
    load 'geode/console.rb'
  end

  desc 'reset', 'Wipe the database and regenerate it using the current schema'
  long_desc <<~LONG_DESC.strip
  Wipes the database and regenerates it using the current schema. Does not affect the schema_migrations table.

  THIS COMMAND WIPES ALL STORED DATA! Do not run this command unless you are sure of what you're doing.
  LONG_DESC
  def reset
    # Verifies that user wants to reset database
    puts 'WARNING: THIS COMMAND WIPES ALL STORED DATA!'
    print 'Are you sure you want to reset? [y/n] '
    response = STDIN.gets.chomp
    until %w(y n).include? response.downcase
      print 'Please enter a valid response. '
      response = STDIN.gets.chomp
    end

    # Resets database if user has confirmed
    if response == 'y'
      Sequel.sqlite(ENV['DB_PATH']) do |db|
        db.tables.each { |k| db.drop_table(k) unless k == :schema_migrations }
        load 'db/schema.rb'
        puts '- Database regenerated from scratch using current schema db/schema.rb'
      end
    end
  end
end
