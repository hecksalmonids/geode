# Required gems for the bot initialization
require 'discordrb'
require 'yaml'
require 'sequel'

# The main bot; all individual crystals will be submodules of this, giving them
# access to the bot object as a constant, Bot::BOT
module Bot
  # Loads config file into struct and parses info into a format readable by CommandBot constructor
  config = OpenStruct.new(YAML.load_file 'config.yml')
  config.client_id = config.id
  config.delete_field(:id)
  config.type = (config.type == 'user') ? :user : :bot
  config.parse_self = !!config.react_to_self
  config.delete_field(:react_to_self)
  config.help_command = config.help_alias.empty? ? false : config.help_alias.map(&:to_sym)
  config.delete_field(:help_alias)
  config.spaces_allowed = config.spaces_allowed.class == TrueClass
  config.webhook_commands = config.react_to_webhooks.class == TrueClass
  config.delete_field(:react_to_webhooks)
  config.ignore_bots = !config.react_to_bots
  config.log_mode = (%w(debug verbose normal quiet silent).include? config.log_mode) ? config.log_mode.to_sym : :normal
  config.fancy_log = config.fancy_log.class == TrueClass
  config.suppress_ready = !config.log_ready
  config.delete_field(:log_ready)
  config.redact_token = !(config.log_token.class == TrueClass)
  config.delete_field(:log_token)
  # Game is stored in a separate variable as it is not a bot attribute
  game = config.game
  config.delete_field(:game)
  # Cleans up config struct by deleting all nil entries
  config = OpenStruct.new(config.to_h.reject { |_a, v| v.nil? })

  puts '==GEODE: A Clunky Modular Ruby Bot Framework With A Database=='

  # Prints an error message to console for any missing required components and exits
  puts 'ERROR: Client ID not found in config.yml' if config.client_id.nil?
  puts 'ERROR: Token not found in config.yml' if config.token.nil?
  puts 'ERROR: Command prefix not found in config.yml' if config.prefix.empty?
  if config.client_id.nil? || config.token.nil? || config.prefix.empty?
    puts 'Exiting.'
    exit(false)
  end

  puts 'Initializing the bot object...'

  # Creates the bot object using the config attributes; this is a constant 
  # in order to make it accessible by crystals
  BOT = Discordrb::Commands::CommandBot.new(config.to_h)

  # Sets bot's playing game
  BOT.ready { BOT.game = game.to_s }

  puts 'Done.'

  puts 'Loading application data (database, models, etc.)...'

  # Sets path to the data folder as environment variable
  ENV['DATA_PATH'] = File.expand_path('data')

  # Database constant
  DB = Sequel.sqlite(ENV['DB_PATH'])

  # Creates the encapsulating module for all model classes and loads them
  Models = Module.new
  Dir['app/models/*.rb'].each do |path|
    load path
    if (filename = File.basename(path, '.*')).end_with?('_singleton')
      puts "+ Loaded singleton model class #{File.basename(path, '.*').gsub('_singleton', '').camelize}"
    else
      puts "+ Loaded model class #{File.basename(path, '.*').camelize}"
    end
  end

  puts 'Done.'

  puts 'Loading additional scripts in lib directory...'

  # Loads files from lib directory in parent
  Dir['lib/*.rb'].each do |path|
    load path
    puts "+ Loaded file #{path}"
  end
  
  puts 'Done.'

  # Loads a crystal from the given file and includes the module into the bot's container;
  # crystal loading progress is printed to console
  # @param path [String] the path to the file to load the crystal from; filename must be the crystal
  #                      name in_snake_case, or this will not work (the crystal generator names the
  #                      file in this way automatically)
  def self.load_crystal(path)
    module_name = File.basename(path, '.*').camelize
    load path
    BOT.include! self.const_get(module_name)
    puts "+ Loaded crystal #{module_name}"
  end

  # Loads crystals depending on CRYSTALS_TO_LOAD environment variable
  ENV['CRYSTALS_TO_LOAD'].split(',').each { |p| load_crystal p }

  puts "Starting bot with logging mode #{config.log_mode}..."
  BOT.ready { puts 'Bot started!' }

  # After loading all desired crystals, runs the bot
  BOT.run
end
