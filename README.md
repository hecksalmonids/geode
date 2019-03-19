# Geode: A Clunky Modular Bot Framework for Discordrb With a Database

Geode is a modular bot framework I made for [discordrb](https://github.com/meew0/discordrb),
and is a modification of [cluster](https://github.com/410757864530-dead-salmonids/cluster). It includes 
[SQLite](https://www.sqlite.org/index.html) database integration.

I created Geode because I decided Cluster wasn't complicated enough already
(and because I wanted to integrate database support into the framework, but never mind that)

All individual modules, called crystals, are located in the `app` directory. The `main` folder contains all the crystals
that are loaded by default, and the `dev` folder contains crystals that will be loaded either by themselves or alongside
the main crystals as desired.

Database support works similar to Rails, but stripped down and different in some ways, detailed below. 
Model classes are stored in the `app/models` directory.

## Instructions

To begin, clone this repository to your local machine, then run `rake init` to initialize it.

To run a bot, fill in `config.yml` with all the necessary information and then run `thor geode:start` 
(or `thor geode -s` for short) on the command line. It will automatically load all crystals present in the `app/main` 
directory. To run crystals present in the `app/dev` directory, run `thor geode:start -d` for dev crystals,
`thor geode:start -a` to run all crystals, and `thor geode:start --load-only=one two three` to run only the
specified crystals.

## Development

### Generators

#### Generating a crystal

To generate a crystal, run `thor geode:generate crystal NAME`, with `NAME` being the crystal's name in CamelCase. A
crystal with the given name will be generated in `app/dev`. To generate a crystal in `app/main` instead, add the option
`--main` (`-m` for short).

* To generate a crystal without events, add the option `--without-events`. Similarly, to generate a crystal without
commands, add the option `--without-commands`. To generate a crystal without database model classes, add the option
`--without-models`.

* All crystals include the `Bot::Models` module, which contains the database's model classes.

#### Generating a model

Generating a model is very similar to Rails' implementation, though not as robust. The command is 
`thor geode:generate model NAME field1:type1, field2:type2`. This generates a model in `app/models` and a migration to
add its table to the database in `db/migrations`.

* To get a list of possible field types, check the description of `thor geode:help generate`.

    * The `id` field is special; the only type it is allowed to have is `primary_key`. This field will be automatically
    created if no primary key was given as a field, but will be skipped if a primary key with a different name was given.

* The `--singleton` flag allows you to generate a singleton model class, whose matching table will only ever contain
a single entry. This entry can be accessed by calling `ModelClassName.instance`, which will create the singular record
if it does not already exist. Additionally, the visibility of the two model class constructors (`.new` and `.create`)
is set to private.

#### Generating a migration

Generating a migration is also similar to Rails, and similarly not as robust. The command is 
`thor geode:generate migration NAME [--with-up-down]`, where it generates a migration with a `change` block by default,
and an up and down block when the `--with-up-down` option is provided.

Unfortunately, it does not have Rails magic; it cannot guess the migration contents from the name.

#### Renaming

All of these can be renamed using `thor geode:rename {crystal|model|migration} OLD_NAME NEW_NAME`.

* Renaming a model has special behavior; it will create a migration that renames the model's database table.

  * Note that renaming a model does not update any references to it in crystals or lib scripts!
  
* When renaming migrations, the name or version number can be provided as the `OLD_NAME` argument.

#### Destruction

All of these can also be destroyed using `thor geode:destroy {crystal|model|migration} NAMES`. 

* Destroying a model has special behavior: 

  * Unlike crystals and migrations, only one model can be deleted at a time.

  * If the database has already been migrated such that the model's table exists in the database, a new 
migration will be generated that drops the table; otherwise, the migration that would add the table is deleted along 
with every migration that follows (as it would invalidate those migrations).

* When destroying migrations, the name or version number can be provided. 

  * Note that destroying migrations is unsafe; be sure that you know what you're doing if you do it!

### Code

#### Coding a crystal

A structure for a basic bot can be seen [here](https://github.com/meew0/discordrb#usage) -- crystals, however, have a
slightly different structure as detailed below.

##### Writing a command

To define a command within a crystal, call the method `command` within the module and fill in its parameters and block 
as necessary. 

An example of a basic command definition looks like this:

```ruby
command :greet do |event|
  "Hi, #{event.user.name}!"
end
```

For details on the method, refer to its
[documentation](https://meew0.github.io/discordrb/master/Discordrb/Commands/CommandContainer.html#command-instance_method).

##### Writing an event handler

To define an event handler within a crystal, call its respective method within the module and fill in its 
parameters and block as necessary.

An example of a basic event handler definition looks like this:
```ruby
member_join do |event|
  puts "User #{event.user.name} has joined the server."
end
```

For details on what event handlers are available, refer to the
[docs](https://meew0.github.io/discordrb/master/Discordrb/EventContainer.html).

#### Additional details

* The bot object is defined as a constant, `Bot::BOT`. As all crystals are submodules of the main module, `Bot`, they have
access to this constant.

* All `.rb` files in the `lib` directory are loaded prior to loading crystals, and after loading the database and models.

* Any additional assets can be placed in the `data` directory; the environment variable `DATA_PATH` contains the path to 
this directory.

### Database tools

Geode uses the [Sequel](https://github.com/jeremyevans/sequel) library to handle databases. Database commands work
similarly to Rails, however they are significantly stripped down and have slightly different syntax.

#### Running migrations

The command `thor db:migrate` runs all migrations in the `db/migrations` directory up to the latest, or migrates to
the given version when run as `thor db:migrate --version=N` (given by the migration's timestamp).

* Running `thor db:migrate -s` displays the migration status; the information displayed shows the latest migration that 
has run and whether the database is up to date on migrations or not.

#### Rolling back migrations

The command `thor db:rollback` rolls back a single migration. 

* If the option `--step=N` is provided, it instead rolls back N migrations, provided N is not greater than the total
number of migrations that have run.

#### Interacting with the database

The command `thor db:console` opens an IRB shell that has the database and model classes loaded to interact with. 

* If the option `--load-only=one two three` is provided, only the given model classes will be loaded into the console.

#### Resetting the database
The command `thor db:reset` resets the entire database, recreating the tables from the schema at `db/schema.rb`. 

* If the option `--tables=one two three` is given, only the given tables are reset. If any other tables in the database
are dependent on a table being reset, the command will fail unless these dependent tables are also being reset.

This command erases data from the database -- be very sure of what you are doing when running this command!
