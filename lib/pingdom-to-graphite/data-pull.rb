require "pingdom-to-graphite"
require "pingdom-client"

require "logger"

class PingdomToGraphite::DataPull

  def initialize(username, password, key, log_level = Logger::ERROR)
    @username   = username
    @password   = password
    @key        = key
    @log_level  = log_level

    @client = connect

  end

  # def limit
  #   limit = @client.limit
  #   short_time = Time.at(limit[:short][:resets_at] - Time.now).gmtime.strftime('%R:%S')
  #   long_time = Time.at(limit[:long][:resets_at] - Time.now).gmtime.strftime('%R:%S')
  #   limit[:friendly] = 
  #   limit
  # end

  def friendly_limit
    limit = @client.limit
    short_time = Time.at(limit[:short][:resets_at] - Time.now).gmtime.strftime('%R:%S')
    long_time = Time.at(limit[:long][:resets_at] - Time.now).gmtime.strftime('%R:%S')
    "You can make #{limit[:short][:remaining]} requests in the next #{short_time} and #{limit[:long][:remaining]} requests in the next #{long_time}."
  end

  def checks
    check_list = @client.checks
  end

  def probes
    probe_list = @client.probes
  end

  def results(check_id, start_ts = nil, end_ts = nil, offset = nil)

    check_options = {}

    unless start_ts.nil?
      check_options['from'] = start_ts
    end

    unless end_ts.nil?
      check_options['to'] = end_ts
    end

    unless offset.nil?
      check_options['offset'] = offset
    end

    results = @client.check(check_id).results(check_options)
  end

  # Get the full results for the range, looping over the API limits as necessary.
  def full_results(check_id, start_ts, end_ts)
    offset = 0
    full_set = Array.new
    begin
      result_set = self.results(check_id, start_ts, end_ts, offset)
      full_set = full_set.concat(result_set)
      offset += 100
    end until result_set.count < 100
    full_set
  end


  private

  def connect
    log = Logger.new(STDOUT)
    log.level = @log_level
    begin
      client = Pingdom::Client.new :username => @username, :password => @password, :key => @key, :logger => log
    rescue
      error("There was a problem connecting to pingdom.")
    end

    client
  end


end