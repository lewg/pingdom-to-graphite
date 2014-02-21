require "graphite-metric"
require "socket"

class PingdomToGraphite::DataPush

  def initialize(graphite_host, graphite_port)
    @graphite_host = graphite_host
    @graphite_post = graphite_port
  end

  # Sent an array of graphite metrics to graphite
  def to_graphite(metric_array)
    graphite = TCPSocket.new(@graphite_host, @graphite_post)
    metric_array.each do |metric|
      graphite.puts metric.to_s
    end
    graphite.close
  end

end
