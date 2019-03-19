require 'erb'
require 'pathname'
require 'sequel'
Sequel.extension :inflector, :schema_dumper

# Contains the generation classes for crystals, models, migrations, and schema
module Generators
  # Superclass for generated objects; contains a method to render the template at the given path with the
  # current instance's binding
  class ObjectGenerator
    private

    # Indents every line of the given string with the given number of spaces
    def indent(str, spaces)
      str.split("\n").map { |s| (' ' * spaces) + s }.join("\n")
    end

    # Renders the template at the given path (in trim mode) with the current binding and returns result
    def render(path)
      template = ERB.new(File.read(File.expand_path(path)), nil, '-')
      template.result(binding)
    end
  end

  # Crystal generator class
  class CrystalGenerator < ObjectGenerator
    def initialize(name, without_commands: false, without_events: false, without_models: false)
      @crystal_name = name.camelize
      @filename = "#{name.underscore}.rb"
      @containers = {command: !without_commands, event: !without_events}
      @models = !without_models
    end

    # Generates crystal file in the given directory; prints the file generation to console
    def generate_in(directory)
      crystal_path = File.expand_path("#{directory}/#{@filename}")
      File.open(crystal_path, 'w') { |f| f.write(render 'geode/templates/crystal_generate_template.erb') }
      relative_crystal_path = Pathname.new(crystal_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated crystal #{@crystal_name} at #{relative_crystal_path}"
    end
  end

  # Model generator class
  class ModelGenerator < ObjectGenerator
    # Array of valid field types
    VALID_FIELD_TYPES = %w(primary_key integer string text boolean float date time references references_singleton)

    def initialize(name, fields, singleton: false)
      @model_name = name.camelize
      @singleton = singleton
      @table_name = singleton ? name.underscore : name.tableize
      @migration_name = "Add#{@table_name.camelize}TableToDatabase"
      @model_filename = singleton ? "#{name.underscore}_singleton.rb" : "#{name.underscore}.rb"
      @migration_filename = "#{Time.now.strftime("%Y%m%d%H%M%S")}_#{@migration_name.underscore}.rb"
      fields.insert(0, %w(id primary_key)) if fields.none? { |_n, t| t == 'primary_key' }
      @columns = fields.map { |d| indent(get_column_string(*d), 6) }
    end

    # Generates model file within the given model directory and its respective migration in the migration directory;
    # prints the file generation to console
    def generate_in(model_directory, migration_directory)
      model_path = File.expand_path("#{model_directory}/#{@model_filename}")
      template_type = @singleton ? 'model_generate_singleton_template.erb' : 'model_generate_standard_template.erb'
      File.open(model_path, 'w') { |f| f.write(render "geode/templates/#{template_type}") }
      relative_model_path = Pathname.new(model_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated#{@singleton ?  ' singleton' : nil} model #{@model_name} at #{relative_model_path}"

      migration_path = File.expand_path("#{migration_directory}/#{@migration_filename}")
      File.open(migration_path, 'w') { |f| f.write(render 'geode/templates/model_generate_migration_template.erb') }
      relative_migration_path = Pathname.new(migration_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated migration #{@migration_name} at #{relative_migration_path}"
    end

    private

    # Returns a string containing the Sequel table column representation
    def get_column_string(name, type)
      case type
      when 'primary_key' then "primary_key :#{name}"
      when 'integer' then "Integer :#{name}"
      when 'string' then "String :#{name}"
      when 'text' then "String :#{name}, text: true"
      when 'boolean' then "TrueClass :#{name}"
      when 'float' then "Float :#{name}"
      when 'date' then "Date :#{name}"
      when 'time' then "Time :#{name}"
      when 'references' then "foreign_key :#{name.foreign_key}, :#{name.tableize}"
      when 'references_singleton' then "foreign_key :#{name.foreign_key}, :#{name.underscore}"
      end
    end
  end

  # Migration generation class for migrations used to rename a model
  class ModelRenameMigrationGenerator < ObjectGenerator
    def initialize(old_name, new_name, singleton = false)
      @old_table = singleton ? old_name.underscore : old_name.tableize
      @new_table = singleton ? new_name.underscore : new_name.tableize
      @migration_name = "Rename#{@old_table.camelize}TableTo#{@new_table.camelize}"
      @filename = "#{Time.now.strftime("%Y%m%d%H%M%S")}_#{@migration_name.underscore}.rb"
    end

    # Generates a timestamped migration file in the given directory; prints the file generation to console
    def generate_in(directory)
      migration_path = File.expand_path("#{directory}/#{@filename}")
      File.open(migration_path, 'w') { |f| f.write(render 'geode/templates/model_rename_migration_template.erb') }
      relative_migration_path = Pathname.new(migration_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated migration #{@migration_name} at #{relative_migration_path}"
    end
  end

  # Migration generation class for migrations used to destroy a model
  class ModelDestroyMigrationGenerator < ObjectGenerator
    def initialize(name, db, singleton = false)
      class << db
        include Sequel::SchemaDumper
      end
      @table_name = singleton ? name.underscore : name.tableize
      @migration_name = "Remove#{@table_name.camelize}TableFromDatabase"
      @filename = "#{Time.now.strftime("%Y%m%d%H%M%S")}_#{@migration_name.underscore}.rb"
      @rollback_table = indent(db.dump_table_schema(@table_name.to_sym), 4)
    end

    # Generates a timestamped migration file in the given directory; prints the file generation to console
    def generate_in(directory)
      migration_path = File.expand_path("#{directory}/#{@filename}")
      File.open(migration_path, 'w') { |f| f.write(render 'geode/templates/model_destroy_migration_template.erb') }
      relative_migration_path = Pathname.new(migration_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated migration #{@migration_name} at #{relative_migration_path}"
    end
  end

  # Migration generation class
  class MigrationGenerator < ObjectGenerator
    def initialize(name, with_up_down: false)
      @name = name.camelize
      @filename = "#{Time.now.strftime("%Y%m%d%H%M%S")}_#{@name.underscore}.rb"
      @change = !with_up_down
    end

    # Generates a timestamped migration file in the given directory, rendering either the change or up/down template;
    # prints the file generation to console
    def generate_in(directory)
      migration_path = File.expand_path("#{directory}/#{@filename}")
      template_type = @change ? 'migration_generate_change_template.erb' : 'migration_generate_up_down_template.erb'
      File.open(migration_path, 'w') { |f| f.write(render "geode/templates/#{template_type}") }
      relative_migration_path = Pathname.new(migration_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated migration #{@name} at #{relative_migration_path}"
    end
  end

  # Schema generation class
  class SchemaGenerator < ObjectGenerator
    def initialize(db)
      class << db
        include Sequel::SchemaDumper
      end
      raw_tables = db.tables.reject { |k| k == :schema_migrations }.map { |k| db.dump_table_schema(k) }
      @tables = raw_tables.map { |t| indent(t.sub('create_table', 'db.create_table?'), 4) }
    end

    # Generates schema from the given database at schema.rb in the given directory;
    # prints the file generation to console
    def generate_in(directory)
      schema_path = File.expand_path("#{directory}/schema.rb")
      File.open(schema_path, 'w') { |f| f.write(render 'geode/templates/schema_template.erb') }
      relative_schema_path = Pathname.new(schema_path).relative_path_from(Pathname.pwd).to_s
      puts "+ Generated schema at #{relative_schema_path} from current db"
    end
  end
end