require 'json'

Given /^Our mock graphite server is running$/ do
  @mock_received = Queue.new
  @mock_socket = TCPServer.new 20003
  @server = Thread.new do
    loop do
      client = @mock_socket.accept
      data = ""
      recv_length = 100
      while (tmp = client.recv(recv_length))
        data += tmp
        break if tmp.empty?
      end
      @mock_received << data
    end
  end
end

When /^I run `([^`]*)` with a valid check_id$/ do |cmd|
  config_file = File.expand_path('~/.p2g/config.json')
  @config = JSON::parse(File.read(config_file));
  step "When I run `#{cmd} #{@config["pingdom"]["checks"][0]}`"
end

Then /^graphite should have recieved results$/ do 
  last_entry = @mock_received.pop
  last_entry.should match /^[^ ]* [\d]+ [\d]{10,}$/
end