module Fluent
  class NATSInput < Input
    Fluent::Plugin.register_input("nats", self)

    config_param :host, :string, :default => "localhost"
    config_param :user, :string, :default => "nats"
    config_param :password, :string, :default => "nats"
    config_param :port, :integer, :default => 4222
    config_param :queue, :string, :default => "fluent.>"
    config_param :tag, :string, :default => "nats"
    config_param :ssl, :bool, :default => false
    config_param :max_reconnect_attempts, :integer, :default => 150
    config_param :reconnect_time_wait, :integer, :default => 2

    def initialize
      require "nats/client"

      NATS.on_error { |err| puts "Server Error: #{err}"; exit! }
      super
    end

    def configure(conf)
      super
      @conf = conf
      unless @host && @queue
        raise ConfigError, "'host' and 'queue' must be all specified."
      end

      @nats_config = {
        :uri => "nats://#{@host}:#{@port}",
        :ssl => @ssl,
        :user => @user,
        :pass => @password,
        :reconnect_time_wait => @reconnect_time_wait,
        :max_reconnect_attempts => @max_reconnect_attempts,
      }
    end

    def start
      super
      run_reactor_thread
      @thread = Thread.new(&method(:run))
      $log.info "listening nats on #{@uri}/#{@queue}"
    end

    def shutdown
      super
      @nats_conn.close
      @thread.join
      EM.stop if EM.reactor_running?
      @reactor_thread.join if @reactor_thread
    end

    def run
      queues = @queue.split(',')
      EM.next_tick {
        @nats_conn = NATS.connect(@nats_config) {
          queues.each do |queue|
            @nats_conn.subscribe(queue) do |msg, reply, sub|
              tag = "#{@tag}.#{sub}"
              begin
                msg_json = JSON.parse(msg)
              rescue JSON::ParserError => e
                $log.error "Failed parsing JSON #{e.inspect}.  Passing as a normal string"
                msg_json = msg
              end
              time = Engine.now
              Engine.emit(tag, time, msg_json)
            end
          end
        }
      }
    end

    private
    def run_reactor_thread
      unless EM.reactor_running?
        @reactor_thread = Thread.new { EM.run }
      end
    end

  end
end
