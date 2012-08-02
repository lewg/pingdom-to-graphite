require "pingdom-to-graphite"
require "pingdom-client"

class PingdomToGraphite::DataPull

  def initialize(username, password, key)
    @username = username
    @password = password
    @key      = key
  end

  def get_checks
    @client = connect!

    check_list = @client.checks
  end

  private

  def connect!
    begin
      client = Pingdom::Client.new :username => @username, :password => @password, :key => @key
    rescue
      error("There was a problem connecting to pingdom.")
    end

    client
  end


end