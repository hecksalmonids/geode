require 'sequel'
require 'irb'

module Bot
  Models = Module.new
end

# Loads database
DB = Sequel.sqlite(ENV['DB_PATH'])
puts '+ Loaded database'

# Loads models based on MODELS_TO_LOAD environment variable unless WITHOUT_MODELS is defined
unless ENV['WITHOUT_MODELS']
  models_to_load = ENV['MODELS_TO_LOAD'].split(',').map do |model_name|
    model_path = if File.exists? "app/models/#{model_name.underscore}_singleton.rb"
                   singleton = true
                   "app/models/#{model_name.underscore}_singleton.rb"
                 else
                   singleton = false
                   "app/models/#{model_name.underscore}.rb"
                 end
    [model_name.camelize, model_path, singleton]
  end

  models_to_load.each do |model_name, model_path, singleton|
    load model_path
    puts "+ Loaded#{singleton ? ' singleton' : nil} model class #{model_name}"
  end
end

# Includes module at top level so IRB console has direct access to model classes
include Bot::Models

# Clears command-line arguments and loads console
ARGV.clear
if ENV['WITHOUT_MODELS']
  puts 'Database can be accessed with the constant DB.'
else puts 'Database can be accessed with the constant DB. Model classes can be accessed with their default names.'
end
IRB.start