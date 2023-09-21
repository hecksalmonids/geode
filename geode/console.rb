require 'sequel'
require 'irb'
require 'dry-configurable'

module Bot
  Models = Module.new
end



# Loads database
DB = Sequel.sqlite(Config.db_path)
puts '+ Loaded database'

# Load models based on MODELS_TO_LOAD environment variable, if defined
if Config.models_to_load
  models_to_load = Config.models_to_load.each do |path|
    path.camelize.split('::')[2..-2].reduce do |memo = Bot::Models, name|
      if memo.const_defined? name
        memo.const_get name
      else
        submodule = Module.new
        memo.const_set name, submodule
        submodule
      end
    end

    load path
    filename = File.basename(path, '.*')
    if filename.end_with?('singleton')
      puts "+ Loaded singleton model class #{filename[0..-11].camelize}"
    else
      puts "+ Loaded model class #{filename.camelize}"
    end
  end
end

# Include module at top level so IRB console has direct access to model classes
include Bot::Models

# Clear command-line arguments and load console
ARGV.clear
if Config.models_to_load
  puts 'Database can be accessed with the constant DB. Model classes can be accessed with their default names.'
else
  puts 'Database can be accessed with the constant DB.'
end
IRB.start