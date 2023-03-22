# Required gems for the bot initialization
require 'discordrb'
require 'yaml'
require 'sequel'

# The main bot; all individual crystals will be submodules of this, giving them
# access to the bot object as a constant, Bot::BOT
module Bot
  # Loads config file into struct and parses info into a format readable by CommandBot constructor
  file_config = OpenStruct.new(YAML.load_file 'config.yml')
  file_config.client_id = file_config.id
  file_config.delete_field(:id)
  file_config.type = (file_config.type == 'user') ? :user : :bot
  file_config.parse_self = !!file_config.react_to_self
  file_config.delete_field(:react_to_self)
  file_config.help_command = file_config.help_alias.empty? ? false : file_config.help_alias.map(&:to_sym)
  file_config.delete_field(:help_alias)
  file_config.spaces_allowed = file_config.spaces_allowed.class == TrueClass
  file_config.webhook_commands = file_config.react_to_webhooks.class == TrueClass
  file_config.delete_field(:react_to_webhooks)
  file_config.ignore_bots = !file_config.react_to_bots
  file_config.log_mode = (%w(debug verbose normal quiet silent).include? file_config.log_mode) ? file_config.log_mode.to_sym : :normal
  file_config.fancy_log = file_config.fancy_log.class == TrueClass
  file_config.suppress_ready = !file_config.log_ready
  file_config.delete_field(:log_ready)
  file_config.redact_token = !(file_config.log_token.class == TrueClass)
  file_config.delete_field(:log_token)
  # Game is stored in a separate variable as it is not a bot attribute
  game = file_config.game
  file_config.delete_field(:game)
  # Cleans up file config struct by deleting all nil entries
  file_config = OpenStruct.new(file_config.to_h.reject { |_a, v| v.nil? })

  puts '==GEODE: A Clunky Modular Ruby Bot Framework With A Database=='

  # Prints an error message to console for any missing required components and exits
  puts 'ERROR: Client ID not found in config.yml' if file_config.client_id.nil?
  puts 'ERROR: Token not found in config.yml' if file_config.token.nil?
  puts 'ERROR: Command prefix not found in config.yml' if file_config.prefix.empty?
  if file_config.client_id.nil? || file_config.token.nil? || file_config.prefix.empty?
    puts 'Exiting.'
    exit(false)
  end

  puts 'Initializing the bot object...'

  # Creates the bot object using the file config attributes; this is a constant
  # in order to make it accessible by crystals
  BOT = Discordrb::Commands::CommandBot.new(**file_config.to_h)

  # Sets bot's playing game
  BOT.ready { BOT.game = game.to_s }

  puts 'Done.'

  puts 'Loading application data (database, models, etc.)...'

  # Data folder and database convenience constants
  DATA_PATH = File.expand_path('data')
  DB = Sequel.sqlite(Config.db_path)

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

  # Load files from lib directory in parent
  Dir['./lib/**/*.rb'].each do |path|
    require path
    puts "+ Loaded file #{path[2..-1]}"
  end

  puts 'Done.'

  # Load slash command definitions
  if Config.add_slash
    puts 'Updating slash command definitions...'

    # Load all slash commands in folder, with each file storing command ID in config
    Dir['./app/slash/*.rb'].each do |path|
      require path
      server_id, command_name = path.split(/[\/\\]/)[3].sub('.rb', '').split('_', 2)
      extra = server_id == 0 ? nil : " for server ID #{server_id}"
      puts "+ Loaded slash command /#{command_name}#{extra}."
    end

    puts 'Done.'
  end

  # Remove either all undefined global slash commands or all undefined slash commands in the given server
  if Config.remove_slash
    if Config.remove_slash == 'global'
      puts 'Removing undefined global slash commands...'
      BOT.get_application_commands.reject { |cmd| Config.slash_ids.include?(cmd.id) }.each do |cmd|
        puts "- Removed slash command /#{cmd.name}."
        cmd.delete
      end
      puts 'Done.'
    else
      puts "Removing undefined slash commands in server ID #{Config.remove_slash}..."
      BOT.get_application_commands(server_id: Config.remove_slash).reject { |cmd| Config.slash_ids.include?(cmd.id) }.each do |cmd|
        puts "- Removed slash command /#{cmd.name}."
        cmd.delete
      end
      puts 'Done.'
    end
  end

  # Load all crystals, preloading their modules if they are nested within subfolders
  Config.crystals_to_load.each do |path|
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

  puts "Starting bot with logging mode #{file_config.log_mode}..."
  BOT.ready { puts 'Bot started!' }

  # After loading all desired crystals, run the bot
  begin
    BOT.run
  rescue Interrupt
    puts ''
    puts 'Bot stopped.'
    exit
  end
end
