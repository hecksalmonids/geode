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

  # Load model classes and print to console
  Models = Module.new
  Dir['app/models/*.rb'].each do |path|
    load path
    if (filename = File.basename(path, '.*')).end_with?('_singleton')
      puts "+ Loaded singleton model class #{filename[0..-11].camelize}"
    else
      puts "+ Loaded model class #{filename.camelize}"
    end
  end

  puts 'Done.'

  puts 'Loading additional scripts in lib directory...'

  # Loads files from lib directory in parent
  Dir['./lib/**/*.rb'].each do |path|
    require path
    puts "+ Loaded file #{path[2..-1]}"
  end

  puts 'Done.'

  # Load all crystals, preloading their modules if they are nested within subfolders
  ENV['CRYSTALS_TO_LOAD'].split(',').each do |path|
    crystal_name = path.camelize.split('::')[2..-1].join('::').sub('.rb', '')
    parent_module = crystal_name.split('::')[0..-2].reduce(self) do |memo, name|
      if memo.const_defined? name
        memo.const_get name
      else
        submodule = Module.new
        memo.const_set(name, submodule)
        submodule
      end
    end
    load path
    BOT.include! self.const_get(crystal_name)
    puts "+ Loaded crystal #{crystal_name}"
  end

  puts "Starting bot with logging mode #{config.log_mode}..."
  BOT.ready { puts 'Bot started!' }

  # After loading all desired crystals, run the bot
  BOT.run
end
