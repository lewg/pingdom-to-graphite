require "pingdom-to-graphite"
require "pingdom-to-graphite/data-pull"
require "pingdom-to-graphite/data-push"
require "graphite-metric"
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
          "host"  => "YOUR_SERVER",
          "port"    => "2003",
          "prefix"  => "pingdom"
        }
      }
      File.open(File.expand_path(options.config),"w",0600) do |f|
        f.write(JSON.pretty_generate(settings))
      end

    end

  end

  desc "init_checks <regex>", "Add your checks to your config. (Will overwrite existing list.) If regex is supplied will only add matching checks."
  def init_checks(check_regex=nil)
    @check_regex = check_regex
    load_config!
    load_check_list!
    @config["pingdom"]["checks"] = @checks.keys
    File.open(File.expand_path(options.config),"w",0600) do |f|
      f.write(JSON.pretty_generate(@config))
    end
    puts "Added #{@checks.count} checks to #{options.config}"
  end

  desc "advice", "Gives you some advice about update frequency."
  def advice
    load_config!
    total_checks = @config["pingdom"]["checks"].count
    calls_per_check = 2 + (total_checks)
    puts "You have #{total_checks} monitored checks. Given a 48000/day API limit:"
    every_minutes = 5
    begin
      daily_calls = 60*24 / every_minutes * calls_per_check
      puts "Every #{every_minutes} Minutes: #{daily_calls}/day - #{daily_calls < 48000 ? "WORKS" : "won't work"}"
      every_minutes += 5
    end until (daily_calls < 48000)
  end

  desc "list", "List all your available Pingdom checks."
  def list
    load_check_list!
    @checks.each do |check_id, check|
      puts "#{check.name} (#{check.id}) - #{check.status}"
    end
  end

  desc "probes", "List all the pingdom probes."
  def probes
    load_probe_list!
    @probes.each do |probe_id, probe|
      puts "#{probe.countryiso} - #{probe.city}"
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
    start_time = (options.start_time) ? DateTime.parse(options.start_time).to_i : Time.now.to_i - 3600
    end_time = (options.end_time) ? DateTime.parse(options.end_time).to_i : Time.now.to_i
    if start_time - end_time > 2764800
      error("Date range must be less then 32 days.")
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
      check_state = @state.has_key?(check_id.to_s) ? @state[check_id.to_s] : Hash.new
      latest_ts = check_state.has_key?("latest_ts") ? check_state["latest_ts"] : 1.hour.ago.to_i
      # API limits to 2764800 seconds, so we'll use that (minutes 30 seconds)
      limit_ts = 2764770.seconds.ago.to_i
      latest_ts = (latest_ts.to_i < limit_ts) ? limit_ts : latest_ts
      new_records = pull_and_push(check_id, latest_ts)
      puts "#{new_records} metrics sent to graphite for check #{check_id}."
    end
    puts datapull.friendly_limit
  end

  desc 'backfill [CHECK_ID]', "Work backwards from the oldest check send to graphite, grabbing more historical data."

  method_option :limit,
                :desc     => "Number of API calls to use while backfilling. If you don't provide one, I'll ask!",
                :type     => :numeric,
                :aliases  => "-l"

  def backfill(check_id)
    load_config!
    load_state!
    # Check the state file
    if @state.has_key?(check_id) && @state[check_id].has_key?("earliest_ts")
      earliest_ts = @state[check_id.to_s]["earliest_ts"]
    else
      error("You can't backfill a check you've never run an update on.")
    end
    load_probe_list!
    load_check_list!
    datapull = get_datapull
    chunk = 10
    unless limit = options.limit
      limit = ask("You have #{datapull.effective_limit} API calls remaining. How many would you like to use?").to_i
    end
    created_ts = datapull.check(check_id).created

    # Keep within the API limits
    working_towards = (earliest_ts - created_ts) > 2678400 ? 31.days.ago.to_i : created_ts
    puts "Backfilling from #{Time.at(earliest_ts)} working towards #{Time.at(working_towards)}. Check began on #{Time.at(created_ts)}"
    # Break it into chunks
    additions = 0
    (limit.to_i.div(chunk)+1).times do
      batch_count = pull_and_push(check_id, working_towards, earliest_ts, chunk)
      puts "#{batch_count} metrics pushed in this batch." if options.verbose
      additions += batch_count
    end
    puts "#{additions} metrics sent to graphite for check #{check_id}."
  end

  private

  def get_datapull
    if @datapull.nil?
      load_config!
      @datapull = PingdomToGraphite::DataPull.new(@config["pingdom"]["username"], @config["pingdom"]["password"], @config["pingdom"]["key"], log_level)
    end
    @datapull
  end

  def get_datapush
    load_config!
    datapush = PingdomToGraphite::DataPush.new(@config["graphite"]["host"], @config["graphite"]["port"])
  end

  def load_config!
    if @config.nil?
      config_file = File.expand_path(options.config)
      unless File.exists?(config_file)
        error("Missing config file (#{options.config})")
      end

      @config = JSON::parse(File.read(config_file));
    end

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

    # If the state dir doesn't exist create it first to prevent errors
    unless File.directory?(File.dirname(state_file))
      FileUtils.mkdir_p(File.dirname(state_file), :mode => 0700)
    end

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
      if @check_regex
        if check.name =~ /#{@check_regex}/
          @checks[check.id] = check
        end
      else
        @checks[check.id] = check
      end
    end
  end

  # Take a pingdom check, and return an Array of metrics to be passed to graphite
  def parse_result(check_id, result)
    results = Array.new
    prefix = "#{@config["graphite"]["prefix"]}.#{@checks[check_id.to_i].class}."
    prefix += @checks[check_id.to_i].name.gsub(/ /,"_").gsub(/\./,"")
    check_status = result.status.eql?("up") ? 1 : 0
    check_time = Time.at(result.time).to_i
    check_city = @probes[result.probe_id].city.gsub(/ /,"_").gsub(/\./,"")
    results << GraphiteMetric::Plaintext.new("#{prefix}.status.#{@probes[result.probe_id].countryiso}.#{check_city}", check_status, check_time)
    results << GraphiteMetric::Plaintext.new("#{prefix}.responsetime.#{@probes[result.probe_id].countryiso}.#{check_city}", result.responsetime, check_time)
    results.each { |metric| puts metric } if options.verbose
    results
  end

  def pull_and_push(check_id, latest_ts = nil, earlist_ts = nil, limit = nil)
    datapull = get_datapull
    datapush = get_datapush
    load_state!
    # Check the state file
    check_state = @state.has_key?(check_id.to_s) ? @state[check_id.to_s] : Hash.new
    latest_stored = check_state.has_key?("latest_ts") ? check_state["latest_ts"] : nil
    earliest_stored = check_state.has_key?("earliest_ts") ? check_state["earliest_ts"] : nil
    # Pull the data
    rec_count = 0
    result_list = Array.new
    begin
      datapull.full_results(check_id, latest_ts, earlist_ts, limit).each do |result|
        result_list += parse_result(check_id, result)
        latest_stored = result.time if latest_stored.nil? || result.time > latest_stored
        earliest_stored = result.time if earliest_stored.nil? || result.time < earliest_stored
        rec_count += 1
      end
    rescue Pingdom::Error => e
      error("Caught error from Pingdom: #{e}")
    end
    # Push to graphite
    begin
      datapush.to_graphite(result_list) unless result_list.empty?
    rescue Exception => e
      error("Failed to push to graphite: #{e}")
    end
    # Store the state
    @state[check_id] = Hash.new
    @state[check_id]["latest_ts"] = latest_stored
    @state[check_id]["earliest_ts"] = earliest_stored
    write_state!
    rec_count
  end

  def error(message)
    STDERR.puts "ERROR: #{message}"
    exit 1
  end

  def log_level
    options.verbose ? Logger::DEBUG : Logger::ERROR
  end

end
