require "pingdom-to-graphite"
require "pingdom-to-graphite/data-pull"
require "thor"
require "json"
require "fileutils"

class PingdomToGraphite::CLI < Thor

  class_option  :config,
                :desc     => "The path to your config file.",
                :type     => :string,
                :aliases  => "-c",
                :default  => "~/.p2g/config.json"

  class_option  :state,
                :desc     => "The path to your state file.",
                :type     => :string,
                :aliases  => "-s",
                :default  => "~/.p2g/state.json"


  desc "init", "Create an empty config JSON file if missing."
  def init
    config_path = File.expand_path(options.config)

    if File.exists?(config_path)
      error("Config file already exists. (#{options.config})")
    else

      # Make sure we have a directory to put the config in
      unless File.directory?(File.dirname(config_path))
        FileUtils.mkdir_p(File.dirname(config_path), :mode => 0700)
      end

      settings = {
        "username"  => "YOUR_USERNAME",
        "password"  => "YOUR_PASSWORD",
        "key"       => "YOUR_API_KEY"
      }
      File.open(File.expand_path(options.config),"w",0600) do |f|
        f.write(JSON.pretty_generate(settings))
      end

    end

  end


  desc "list", "List all your available Pingdom checks."
  def list
    load_config!
    puts "Hello"
    puts "Config: #{options.config}"
    puts "Username: #{@username}"
    puts "Password: #{@password}"
    puts "Key: #{@key}"
    puts "State: #{options.state}"
    datapull = PingdomToGraphite::DataPull.new(@username, @password, @key)
    datapull.get_checks.each do |check|
      puts "#{check.name} (#{check.id}) - #{check.status}"
    end
  end

  private

  def load_config!
    config_file = File.expand_path(options.config)
    unless File.exists?(config_file) 
      error("Missing config file (#{options.config})")
      exit
    end

    config = JSON::parse(File.read(config_file));

    @username = config["username"]
    @password = config["password"]
    @key = config["key"]

  end

end