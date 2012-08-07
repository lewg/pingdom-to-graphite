require "pingdom-to-graphite"
require "pingdom-to-graphite/data-pull"
require "thor"
require "json"
require "fileutils"
require "logger"

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

  class_option :verbose, :type => :boolean, :aliases => "-v", :desc => "Increase verbosity."

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

      # A nice little defaults file.
      settings = {
        "pingdom"   => {
          "username"  => "YOUR_USERNAME",
          "password"  => "YOUR_PASSWORD",
          "key"       => "YOUR_API_KEY",
          "checks"    => ["CHECK_ID_1","CHECK_ID_2"]
        },
        "graphite"  => {
          "server"  => "YOUR_SERVER",
          "port"    => "YOUR_PORT",
          "prefix"  => "pingdom"
        }  
      }
      File.open(File.expand_path(options.config),"w",0600) do |f|
        f.write(JSON.pretty_generate(settings))
      end

    end

  end


  desc "list", "List all your available Pingdom checks."
  def list
    load_check_list!
    @checks.each do |check_id, check|
      puts "#{check.name} (#{check.id}) - #{check.status}"
    end
  end

  desc "results [CHECK_ID]", "List results for a specific check. The Pingdom API limits results to 100."

  method_option :start_time,
                :desc     => "Beginning time for the checks, in any format supported by ruby's Time.parse(). Default will give you the last hour of checks.",
                :type     => :string,
                :aliases  => "-b"

  method_option :end_time,
                :desc     => "End time for the checks, in any format supported by ruby's Time.parse(). Default to right now.",
                :aliases  => "-e"

  def results(check_id)
    load_config!
    load_probe_list!
    start_time = (options.start_time) ? DateTime.parse(options.start_time).to_i : 1.hour.ago
    end_time = (options.end_time) ? DateTime.parse(options.end_time).to_i : DateTime.now.to_i
    if start_time - end_time > 2764800
      error("Date range must be less then 32 days.")
      exit
    end
    datapull = get_datapull
    datapull.results(check_id, start_time, end_time).each do |result|
      #<Pingdom::Result probeid: 33 time: 1343945109 status: "up" responsetime: 1103 statusdesc: "OK" statusdesclong: "OK">
      puts "#{Time.at(result.time)}: #{result.status} - #{result.responsetime}ms (#{@probes[result.probeid].name})"
    end
    puts datapull.friendly_limit
  end


  desc "update", "Attempt to bring the checks defined in your config file up to date in graphite. If a check has never been polled before it will start with the last 100 checks."
  def update
    load_config!
    load_state!
    load_probe_list!
    load_check_list!
    datapull = get_datapull
    
    @config["pingdom"]["checks"].each do |check_id|
      puts "Check #{check_id}: " if options.verbose
      # Check the state file
      puts @state
      check_state = @state.has_key?(check_id.to_s) ? @state[check_id.to_s] : Hash.new
      puts check_state
      latest_ts = check_state.has_key?("latest_ts") ? check_state["latest_ts"] : 1.hour.ago.to_i
      earliest_ts = check_state.has_key?("earliest_ts") ? check_state["earliest_ts"] : latest_ts
      # Pull the data
      rec_count = 0
      datapull.full_results(check_id, latest_ts, nil).each do |result|
        prefix = "#{@config["graphite"]["prefix"]}.#{@checks[check_id].type}."
        prefix += "#{@checks[check_id].name.gsub(/ /,"_")}"
        check_status = result.status.eql?("up") ? 1 : 0
        check_time = Time.at(result.time).to_i
        puts "#{prefix}.status.all #{check_status} #{check_time}" if options.verbose
        puts "#{prefix}.status.#{@probes[result.probe_id].countryiso} #{check_status} #{check_time} " if options.verbose
        puts "#{prefix}.response_time.all #{result.responsetime} #{check_time}" if options.verbose
        puts "#{prefix}.response_time.#{@probes[result.probe_id].countryiso} #{result.responsetime} #{check_time}" if options.verbose
        latest_ts = result.time if result.time > latest_ts
        earliest_ts = result.time if result.time < earliest_ts
        rec_count += 1
      end
      puts "#{rec_count} metrics sent to graphite for check #{check_id}."
      @state[check_id] = Hash.new
      @state[check_id]["latest_ts"] = latest_ts
      @state[check_id]["earliest_ts"] = earliest_ts
    end
    write_state!
  end

  private

  def get_datapull
    datapull = PingdomToGraphite::DataPull.new(@config["pingdom"]["username"], @config["pingdom"]["password"], @config["pingdom"]["key"], log_level)
  end

  def load_config!
    config_file = File.expand_path(options.config)
    unless File.exists?(config_file) 
      error("Missing config file (#{options.config})")
      exit
    end

    @config = JSON::parse(File.read(config_file));

  end

  def load_state!
    state_file = File.expand_path(options.state)
    if File.exists?(state_file)
      @state = JSON::parse(File.read(state_file))
    else
      @state = Hash.new
    end
  end

  # Write the state to disk
  def write_state!
    state_file = File.expand_path(options.state)
    File.open(state_file,"w",0600) do |f|
      f.write(JSON.generate(@state))
    end
  end


  # Store the list in the object for reference (less api calls)
  def load_probe_list!
    config_file = File.expand_path(options.config)
    datapull = get_datapull
    @probes = Hash.new
    datapull.probes.each do |probe|
      # {"city"=>"Manchester", "name"=>"Manchester, UK", "country"=>"United Kingdom",
      # "countryiso"=>"GB", "id"=>46, "ip"=>"212.84.74.156", "hostname"=>"s424.pingdom.com", "active"=>true}
      @probes[probe.id] = probe
    end
  end

  # Store the check list in the object for reference (less api calls)
  def load_check_list!
    load_config!
    datapull = get_datapull
    @checks = Hash.new
    datapull.checks.each do |check|
      # {"name"=>"Autocomplete", "id"=>259103, "type"=>"http", "lastresponsetime"=>203173, 
      #  "status"=>"up", "lasttesttime"=>1298102416}
      @checks[check.id] = check
    end
  end

  def log_level
    options.verbose ? Logger::DEBUG : Logger::ERROR
  end

end