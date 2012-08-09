require "aruba/cucumber"
require "socket"
require "thread"

Before do 
  @aruba_timeout_seconds = 60
end

Before("@graphite") do 
  # Create a hybrid config (real pingdom / mock graphite)
  config_file = File.expand_path('~/.p2g/config.json')
  @config = JSON::parse(File.read(config_file))
  @config["pingdom"]["checks"] = [ @config["pingdom"]["checks"][0] ]
  @config["graphite"] = {
    "host" => "localhost",
    "port" => "20003",
    "prefix" => "pingdom"
  }
  File.open('tmp/mockgraphite.json',"w",0600) do |f|
    f.write(JSON.generate(@config))
  end
end

After("@graphite") do
  File.delete('tmp/mockgraphite.json')
  @mock_socket.close
end


Before("@copystate") do 
  # Copy the real statefile (so we don't mess it up)
  state_file = File.expand_path('~/.p2g/state.json')
  File.open('tmp/copiedstate.json',"w",0600) do |f|
    f.write(File.read(state_file))
  end
end
  
After("@copystate") do
  File.delete('tmp/copiedstate.json')
end

