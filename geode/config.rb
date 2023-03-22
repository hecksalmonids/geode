require 'dry-configurable'

# Class to hold configuration details
class Config
  extend Dry::Configurable

  setting :db_path, default: File.expand_path('db/data.db'), reader: true
  setting :crystals_to_load, default: [], reader: true
  setting :add_slash, reader: true
  setting :remove_slash, reader: true
  setting :slash_ids, default: [], reader: true
  setting :models_to_load, reader: true
end