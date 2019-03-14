require 'sequel'
require 'irb'

module Bot
  Models = Module.new
end

# Loads database
DB = Sequel.sqlite(ENV['DB_PATH'])
puts '+ Loaded database'

# Loads models based on MODELS_TO_LOAD environment variable
models_to_load = ENV['MODELS_TO_LOAD'].split(',').map do |model_name|
  if (path = Dir['app/models/*.rb'].find { |p| File.basename(p, '.*').camelize == model_name })
    [model_name, path]
  else raise Error, "ERROR: Model #{model_name} not found"
  end
end
models_to_load.each do |model_name, path|
  load path
  puts "+ Loaded model class #{model_name}"
end

# Includes module at top level so IRB console has direct access to model classes
include Bot::Models

# Clears command-line arguments and loads console
ARGV.clear
puts 'Database can be accessed with the constant DB. Model classes can be accessed with their default names.'
IRB.start