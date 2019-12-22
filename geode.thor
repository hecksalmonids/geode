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
  # Throw exit code 1 on errors
  def self.exit_on_failure?
    true
  end

  # Throw an error if an unknown flag is provided
  check_unknown_options!

  map %w(-r -s) => :start
  desc 'start [-d], [-a], [--load-only=one two three]', 'Load crystals and start the bot'
  long_desc <<~LONG_DESC.strip
    Loads crystals and starts the bot. With no options, this loads only the crystals in main.
  
    Note: If two crystals with the same name are found by --load-only, an error will be thrown as crystals must
    have unique names.
  LONG_DESC
  option :dev,        type:    :boolean,
                      aliases: '-d',
                      desc:    'Load dev crystals instead of main'
  option :all,        type:    :boolean,
                      aliases: '-a',
                      desc:    'Load all crystals (main and dev)'
  option :load_only,  type:    :array,
                      desc:    'Load only the given crystals (searching both main and dev)'
  def start
    # Validate that only one option is given
    raise Error, 'ERROR: Only one of -d, -a and --load-only can be given' if options.count { |_k, v| v } > 1

    # Select the crystals to load, throwing an error if a crystal given in load_only is not found
    if options[:dev]
      ENV['CRYSTALS_TO_LOAD'] = Dir['app/dev/**/*.rb'].join(',')
    elsif options[:all]
      ENV['CRYSTALS_TO_LOAD'] = (Dir['app/main/**/*.rb'] + Dir['app/dev/*.rb']).join(',')
    elsif options[:load_only]
      all_crystal_paths = Dir['app/main/**/*.rb'] + Dir['app/dev/**/*.rb']
      ENV['CRYSTALS_TO_LOAD'] = options[:load_only].map do |arg|
        path = all_crystal_paths.find { |p| p.split('/')[2..-1].join('/') == (arg.underscore + '.rb') }
        raise Error, "ERROR: Crystal #{arg} not found" unless path
        path
      end.join(',')
    else
      ENV['CRYSTALS_TO_LOAD'] = Dir['app/main/**/*.rb'].join(',')
    end

    # Load the bot script
    load File.expand_path('app/bot.rb')
  end

  desc 'generate {crystal|model|migration} ARGS', 'Generate a Geode crystal, model or migration'
  long_desc <<~LONG_DESC.strip
    Generate a Geode crystal, model or migration.

    When generating a crystal, the format is 
    'generate crystal [-m], [--main], [--without-commands], [--without-events], [--without-models] names...'
    \x5When generating a model, the format is 'generate model name [--singleton] [fields...]'
    \x5When generating a migration, the format is 'generate migration [--with-up-down] name'

    If a model is being generated, the model's fields should be included in the format 'name:type'
    (i.e. generate model name:string number:integer), similar to Rails.
    \x5The allowed field types are: #{Generators::ModelGenerator::VALID_FIELD_TYPES.join(', ')}
    \x5The 'id' field is special; if given, it must be of type 'primary_key'. If no primary key is
    given, a primary key field named 'id' will automatically be created; it is skipped if a primary 
    key with a different name exists.
    \x5The --singleton option allows you to generate a singleton model class, which will create a
    table with only a single entry that can be retrieved using 'ModelClassName.instance'.
  LONG_DESC
  option :main,             type:    :boolean,
                            aliases: '-m',
                            desc:    'Generate a crystal in the main folder instead of dev (crystal generation only)'
  option :without_commands, type:    :boolean,
                            desc:    'Generate a crystal without a CommandContainer (crystal generation only)'
  option :without_events,   type:    :boolean,
                            desc:    'Generate a crystal without an EventContainer (crystal generation only)'
  option :without_models,   type:    :boolean,
                            desc:    'Generate a crystal without database model classes (crystal generation only)'
  option :singleton,        type:    :boolean,
                            desc:    'Generate a singleton model class instead of the standard (model generation only)'
  option :with_up_down,     type:    :boolean,
                            desc:    'Generate a migration with up/down blocks instead of a change block (migration generation only)'
  def generate(type, *args)
    # Case generation type
    case type
    when 'crystal'
      # Validate that no invalid options are given when a crystal is being generated
      raise Error, 'ERROR: Option --singleton should not be given when generating a crystal' if options[:singleton]
      raise Error, 'ERROR: Option --with-up-down should not be given when generating a crystal' if options[:with_up_down]

      # Validate that both of --without-events and --without-commands are not given
      if options[:without_events] && options[:without_commands]
        raise Error, 'ERROR: Only one of --without-events, --without-commands can be given'
      end

      # Iterate through the given names and generate crystals for each
      args.each do |crystal_name|
        generator = Generators::CrystalGenerator.new(
            crystal_name,
            without_commands: options[:without_commands],
            without_events: options[:without_events],
            without_models: options[:without_models]
        )
        generator.generate_in(options[:main] ? 'app/main' : 'app/dev')
      end

    when 'model'
      # Validate that no invalid option is given when generating a model
      raise Error, 'ERROR: Option -m, --main should not be given when generating a model' if options[:main]
      raise Error, 'ERROR: Option --without-commands should not be given when generating a model' if options[:without_commands]
      raise Error, 'ERROR: Option --without-events should not be given when generating a model' if options[:without_events]
      raise Error, 'ERROR: Option --without-models should not be given when generating a model' if options[:without_models]
      raise Error, 'ERROR: Option --with-up-down should not be given when generating a model' if options[:with_up_down]

      name = args[0]
      fields = args[1..-1]

      # Validate that a name is given
      raise Error, 'ERROR: Model name must be given' unless name

      # If fields were given, validate that they have the correct format, the type is valid and if an id field is
      # given, it is the primary key; if so, map the array to the correct format for the generator
      if fields
        fields.map! do |field_str|
          unless (field_name, field_type = field_str.split(':')).size == 2
            raise Error, "ERROR: #{field_str} is not in the correct format of name:type"
          end
          unless Generators::ModelGenerator::VALID_FIELD_TYPES.include?(field_type)
            raise Error, "ERROR: #{field_str} has an invalid type"
          end
          if field_name == 'id' && field_type != 'primary_key'
            raise Error, 'ERROR: Field id can only be primary key'
          end
          [field_name, field_type]
        end

        # If fields were not given, set fields equal to an empty array
      else
        fields = []
      end

      # Generate model (either standard or singleton)
      generator = Generators::ModelGenerator.new(name, fields, singleton: options[:singleton])
      generator.generate_in 'app/models', 'db/migrations'

    when 'migration'
      # Validate that no invalid option is given when generating a migration
      raise Error, 'ERROR: Option -m, --main should not be given when generating a migration' if options[:main]
      raise Error, 'ERROR: Option --without-commands should not be given when generating a migration' if options[:without_commands]
      raise Error, 'ERROR: Option --without-events should not be given when generating a migration' if options[:without_events]
      raise Error, 'ERROR: Option --without-models should not be given when generating a migration' if options[:without_models]
      raise Error, 'ERROR: Option --singleton should not be given when generating a migration' if options[:singleton]

      # Validate that exactly one argument (the migration name) is given
      raise Error, 'ERROR: Migration name must be given' if args.size < 1
      raise Error, 'ERROR: Only one migration name can be given' if args.size > 1

      # Generate migration
      generator = Generators::MigrationGenerator.new(args[0], with_up_down: options[:with_up_down])
      generator.generate_in 'db/migrations'

    else raise Error, 'ERROR: Type must be crystal, model or migration'
    end
  end

  desc 'rename {crystal|model|migration} OLD_NAME NEW_NAME', 'Rename a Geode crystal, model or migration'
  long_desc <<~LONG_DESC.strip
    Rename a Geode crystal, model or migration.

    When renaming a model, a new migration will be generated that renames the model's table.
    \x5When renaming a migration, provide either the migration's name or version number for the old name.

    Note: Renaming a model does not update any references to the model within crystals or lib scripts!
  LONG_DESC
  def rename(type, old_name, new_name)
    # Case rename type
    case type
    when 'crystal'
      # Validate that crystal with given name exists
      unless (old_path = (Dir['app/dev/*.rb'] + Dir['app/main/*.rb']).find { |p| File.basename(p, '.*').camelize == old_name })
        raise Error, "ERROR: Crystal #{old_name} not found"
      end

      new_path = "#{File.dirname(old_path)}/#{new_name.underscore}.rb"

      # Write content of old crystal file to new, replacing all instances of old name with new
      File.open(new_path, 'w') do |file|
        file.write(File.read(old_path).gsub(old_name, new_name.camelize))
      end

      # Delete old file
      File.delete(old_path)

      puts "= Renamed crystal #{old_name} to #{new_name} at #{new_path}"

    when 'model'
      old_path = if File.exists? "app/models/#{old_name.underscore}.rb"
                   singleton = false
                   "app/models/#{old_name.underscore}.rb"
                 elsif File.exists? "app/models/#{old_name.underscore}_singleton.rb"
                   singleton = true
                   "app/models/#{old_name.underscore}_singleton.rb"
                 end

      # Validate that model with given name exists
      unless old_path
        raise Error, "ERROR: Model #{old_name} not found"
      end

      new_path = singleton ? "app/models/#{new_name.underscore}_singleton.rb" : "app/models/#{new_name.underscore}.rb"

      # Write content of old model file to new, replacing all instances of old name (and table if singleton) with new
      File.open(new_path, 'w') do |file|
        new_content = File.read(old_path).gsub(old_name.camelize, new_name.camelize)
        new_content = new_content.gsub(":#{old_name.underscore}", ":#{new_name.underscore}") if singleton
        file.write new_content
      end

      # Delete old file
      File.delete(old_path)

      puts "= Renamed model #{old_name.camelize} to #{new_name.camelize} at #{new_path}"

      # Generate migration renaming old model's table to new
      generator = Generators::ModelRenameMigrationGenerator.new(old_name, new_name, singleton)
      generator.generate_in('db/migrations')

    when 'migration'
      # Validate that migration with given name or version number exists
      old_path = Dir['db/migrations/*.rb'].find do |path|
        filename = File.basename(path)
        filename.to_i == old_name.to_i || filename[15..-4].camelize == old_name.camelize
      end
      raise Error, "ERROR: Migration #{old_name.camelize} not found" unless old_path

      old_migration_name = File.basename(old_path)[15..-4].camelize
      migration_version = File.basename(old_path).to_i
      new_path = "db/migrations/#{migration_version}_#{new_name.underscore}.rb"

      # Write content of old migration file to new, replacing all instances of old name with new
      File.open(new_path, 'w') do |file|
        file.write(File.read(old_path).gsub(old_migration_name, new_name.camelize))
      end

      # Delete old file
      File.delete(old_path)

      puts "= Renamed migration version #{migration_version} (#{old_migration_name}) to #{new_name.camelize} at #{new_path}"

    else raise Error, 'ERROR: Generation type must be crystal, model or migration'
    end
  end

  desc 'destroy {model|migration} NAME(S)', 'Destroy Geode models or migrations'
  long_desc <<~LONG_DESC.strip
    Destroy a Geode model or migration. 
    Destruction of models must be done one at a time; however multiple migrations may be deleted at a time.

    When destroying a model, the migration that created its table and every migration afterward will be deleted 
    provided the model's table does not already exist in the database; otherwise, a new migration will be created 
    that drops the model's table.
    \x5When destroying migrations, provide either the version number or name.

    Note: Destroying migrations is unsafe; avoid doing it unless you are sure of what you are doing.
  LONG_DESC
  def destroy(type, *args)
    # Validate that arguments have been given
    raise Error, 'ERROR: At least one name must be given' if type && args.empty?

    # Case destruction type
    case type
    when 'model'
      # Validate that only one model name is given
      raise Error, 'ERROR: Only one model can be deleted at a time' unless args.size == 1

      model_name = args[0]
      model_path = if File.exists? "app/models/#{model_name.underscore}.rb"
                   singleton = false
                   "app/models/#{model_name.underscore}.rb"
                 elsif File.exists? "app/models/#{model_name.underscore}_singleton.rb"
                   singleton = true
                   "app/models/#{model_name.underscore}_singleton.rb"
                 end

      # Validate that model exists
      raise Error, "ERROR: Model #{model_name} not found" unless model_path

      table_name = singleton ? model_name.underscore : model_name.tableize

      # Delete model, printing deletion to console
      File.delete model_path
      puts "- Deleted model file for model #{model_name}"

      # Load the database
      Sequel.sqlite(ENV['DB_PATH']) do |db|
        # If model's table exists in the database, generate new migration dropping the model's table
        if db.table_exists?(table_name.to_sym)
          generator = Generators::ModelDestroyMigrationGenerator.new(model_name, db, singleton)
          generator.generate_in('db/migrations')

        # Otherwise, delete the migration adding the model's table and every migration that follows
        else
          initial_migration_index = Dir['db/migrations/*.rb'].sort.index do |path|
            path.include? "add_#{table_name}_table_to_database"
          end

          Dir['db/migrations/*.rb'].sort[initial_migration_index..-1].each do |migration_path|
            migration_name = File.basename(migration_path)[15..-4].camelize
            migration_version = File.basename(migration_path).to_i
            File.delete(migration_path)
            puts "- Deleted migration version #{migration_version} (#{migration_name})"
          end
        end
      end

    when 'migration'
      all_migration_paths = Dir['db/migrations/*.rb']

      # Validate that migrations with the given names or versions all exist and get their names, versions
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

      # Delete all given migrations, printing deletions to console
      migrations_to_delete.each do |migration_name, migration_version, migration_path|
        File.delete(migration_path)
        puts "- Deleted migration version #{migration_version} (#{migration_name})"
      end

    else raise Error, 'ERROR: Generation type must be model or migration'
    end
  end
end

# Geode's database management; contains tasks related to modifying the database
class Database < Thor
  namespace :db

  # Throw exit code 1 on errors
  def self.exit_on_failure?
    true
  end

  # Throw an error if an unknown flag is provided
  check_unknown_options!

  desc 'migrate [--version=N], [-s]', "Migrate this Geode's database or display migration status"
  long_desc <<~LONG_DESC.strip
    Migrate this Geode's database, or displays migration status. With no options, the database is migrated to the latest.

    When --version is specified, the number given should be the timestamp of the migration.

    When displaying migration status with -s, the current migration will be displayed along with how many 
    migrations behind the latest the database is currently on.
  LONG_DESC
  option :version, type:    :numeric,
                   desc:    'Migrate the database to the given version'
  option :status,  type:    :boolean,
                   aliases: '-s',
                   desc:    'Check the current status of migrations'
  def migrate
    # Load the database
    Sequel.sqlite(ENV['DB_PATH']) do |db|
      # Validate that both version and status are not given at the same time
      raise Error, 'ERROR: Only one of --version, -s can be given at a time' if options[:version] && options[:status]

      # If version is given:
      if options[:version]
        # Validate that the given version exists
        unless (file_path = Dir['db/migrations/*.rb'].find { |f| File.basename(f).to_i == options[:version] })
          raise Error, "ERROR: Migration version #{options[:version]} not found"
        end

        filename = File.basename(file_path)

        # Migrate the database to the given version
        Sequel::Migrator.run(db, 'db/migrations', target: options[:version])

        # Regenerate schema
        generator = Generators::SchemaGenerator.new(db)
        generator.generate_in('db')

        puts "+ Database migrated to version #{options[:version]} (#{filename[15..-4].camelize})"

      # If status is given, respond with migration status:
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
        if Sequel::Migrator.is_current?(db, 'db/migrations')
          puts 'Database is on latest migration'
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
  end

  desc 'rollback [--step=N]', 'Revert migrations from the database'
  long_desc <<~LONG_DESC.strip
    Revert a number of migrations from the database. With no options, only one migration is rolled back.

    --step will throw an error if the number of migrations to be rolled back is greater than the number of
    migrations already run.
  LONG_DESC
  option :step, type: :numeric,
                desc: 'Revert the given number of migrations'
  def rollback
    # Load the database
    Sequel.sqlite(ENV['DB_PATH']) do |db|
      # Validate that the steps to rollback is not greater than the completed migrations
      if options[:step]
        migration_count = db[:schema_migrations].count
        if options[:step] > migration_count
          raise Error, "ERROR: Number of migrations to rollback less than #{options[:step] || 1}"
        end
      end

      filename = db[:schema_migrations].order(:filename).map(:filename)[options[:step] ? -options[:step] - 1 : -2]
      migration_name = filename[15..-4].camelize
      version_number = filename.to_i

      # Roll back the database to the given version
      Sequel::Migrator.run(db, 'db/migrations', target: version_number)

      # Regenerate schema
      generator = Generators::SchemaGenerator.new(db)
      generator.generate_in('db')

      puts "+ Database rolled back to version #{version_number} (#{migration_name})"
    end
  end

  desc 'console [--load-only=one two three]', 'Load an IRB console that allows database interaction'
  long_desc <<~LONG_DESC.strip
    Load an IRB console that allows interaction with the Geode's database and model classes.
    \x5The Bot::Models module is included in the IRB shell; no need to call the full class name 
    to work with a model class.

    When --load-only is given, only the given model classes will be loaded.
    \x5When --without-models is given, no models will be loaded.
  LONG_DESC
  option :load_only,      type: :array,
                          desc: 'Load only the given model classes'
  option :without_models, type: :boolean,
                          desc: 'Load only the database, without model classes'
  def console
    # Validate that only one option is given at a time
    if options[:load_only] && options[:without_models]
      raise Error, 'ERROR: Only one of --load-only and --without-models can be given at a time'
    end

    # Validate that all given models exist if load_only is given and add their paths to MODELS_TO_LOAD environment
    # variable if so
    if options[:load_only]
      options[:load_only].each do |model_name|
        model_paths = Array.new
        if File.exists?(path = "app/models/#{model_name.underscore}.rb")
          model_paths.push(path)
        elsif File.exists?(path = "app/models/#{model_name.underscore}_singleton.rb")
          model_paths.push(path)
        else
          raise Error, "ERROR: Model #{model_name} not found"
        end
        ENV['MODELS_TO_LOAD'] = model_paths.join
      end
    elsif options[:without_models]
      ENV['MODELS_TO_LOAD'] = nil
    else
      ENV['MODELS_TO_LOAD'] = Dir['app/models/*.rb'].join(',')
    end

    # Load IRB console script
    load 'geode/console.rb'
  end

  desc 'reset', 'Wipe the database and regenerate it using the current schema'
  long_desc <<~LONG_DESC.strip
    Wipe the database and regenerate it using the current schema. Does not affect the schema_migrations table.

    Do not run this command unless you are sure of what you're doing.

    If the option --tables=one two three is given, only the given tables will be reset, provided any tables that
    are dependent on them are given as option arguments to be reset as well.
  LONG_DESC
  option :tables, type: :array,
                  desc: 'Reset only the given tables'
  def reset
    # Load the database
    Sequel.sqlite(ENV['DB_PATH']) do |db|
      # Validate that if tables option is given, all given tables exist, none of them are schema_migrations, and
      # either have no dependent tables or all dependent tables are included in the arguments
      if options[:tables]
        options[:tables].each do |table_name|
          raise Error, 'ERROR: Table schema_migrations cannot be reset' if table_name == 'schema_migrations'

          if db.table_exists?(table_name.to_sym)
            dependent_tables = db.tables.select do |key|
              db.foreign_key_list(key).any? { |fk| fk[:table] == table_name.to_sym }
            end

            unless dependent_tables.all? { |k| options[:tables].include? k.to_s }
              raise Error, "ERROR: Table #{table_name} has dependencies"
            end
          else
            raise Error, "ERROR: Table #{table_name} not found"
          end
        end
      end

      tables_to_reset = options[:tables] ? options[:tables].map(&:to_sym) : db.tables - [:schema_migrations]

      # Verify that user wants to reset database
      puts 'WARNING: THIS COMMAND WILL RESULT IN LOSS OF DATA!'
      print 'Are you sure you want to reset? [y/n] '
      response = STDIN.gets.chomp
      until %w(y n).include? response.downcase
        print 'Please enter a valid response. '
        response = STDIN.gets.chomp
      end

      # If user has confirmed:
      if response == 'y'
        dependent_tables = tables_to_reset.select { |k| db.foreign_key_list(k).any? }
        remaining_tables = tables_to_reset - dependent_tables

        # Drop tables, beginning with dependent tables
        db.drop_table(*dependent_tables)
        db.drop_table(*remaining_tables)

        # Load schema
        load 'db/schema.rb'
        if options[:tables]
          puts '- Given tables regenerated from scratch using current schema db/schema.rb'
        else
          puts '- Database regenerated from scratch using current schema db/schema.rb'
        end
      end
    end
  end
end
