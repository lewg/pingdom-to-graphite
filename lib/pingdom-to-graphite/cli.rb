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
      unless File.directory?(File.dirname(config_path))
        FileUtils.mkdir_p(File.dirname(config_path), :mode => 0700)
      end
      settings = {
        "username"  => "REPLACE_ME",
        "password"  => "REPLACE_ME",
        "key"       => "REPLACE_ME"
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
    
  end

  private

  def load_config!
    unless File.exists?(File.expand_path(options.config)) 
      error("Missing config file (#{options.config})")
      exit
    end

    config = JSON::parse(options.config);

  end

end