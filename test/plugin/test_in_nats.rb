require "test/unit"
require "fluent/test"
require "lib/fluent/plugin/in_nats.rb"
require "nats/client"
require "test_helper"

class NATSInputTest < Test::Unit::TestCase
  include NATSTestHelper

  CONFIG = %[
    port 4222
    host localhost
    user nats
    password nats
  ]

  def basic_queue_conf
    CONFIG + %[
      queue fluent.>
    ]
  end

  def multiple_queue_conf
    CONFIG + %[
      queue fluent.>, fluent2.>
    ]
  end

  def ssl_conf
    basic_queue_conf + %[
      ssl true
    ]
  end

  def create_driver(conf)
    Fluent::Test::InputTestDriver.new(Fluent::NATSInput).configure(conf)
  end

  sub_test_case "configure" do
    test "basic" do
      d = create_driver basic_queue_conf
      assert_equal 4222, d.instance.port
      assert_equal "localhost", d.instance.host
      assert_equal "nats", d.instance.user
      assert_equal "nats", d.instance.password
      assert_equal "fluent.>", d.instance.queue
    end

    test "multiple queue" do
      d = create_driver multiple_queue_conf
      assert_equal 4222, d.instance.port
      assert_equal "localhost", d.instance.host
      assert_equal "nats", d.instance.user
      assert_equal "nats", d.instance.password
      assert_equal "fluent.>, fluent2.>", d.instance.queue
    end

    test "basic with ssl" do
      d = create_driver ssl_conf
      assert_equal 4222, d.instance.port
      assert_equal "localhost", d.instance.host
      assert_equal "nats", d.instance.user
      assert_equal "nats", d.instance.password
      assert_equal "fluent.>", d.instance.queue
      assert_equal true, d.instance.ssl
    end
  end

  sub_test_case "events" do
    test "with credentials" do
      d = create_driver basic_queue_conf

      time = Time.parse("2011-01-02 13:14:15 UTC").to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.test1", time, {"message"=>"nats", "fluent_timestamp"=>time}
      d.expect_emit "nats.fluent.test2", time, {"message"=>"nats", "fluent_timestamp"=>time}

      uri = generate_uri(d)

      run_server(uri) do
        d.run do
          d.expected_emits.each { |tag, _time, record|
            send(uri, tag[5..-1], record)
            sleep 0.5
          }
        end
      end
    end

    test "without credentials" do
      d = create_driver basic_queue_conf

      time = Time.parse("2011-01-02 13:14:15 UTC").to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.test1", time, {"message"=>"nats", "fluent_timestamp"=>time}
      d.expect_emit "nats.fluent.test2", time, {"message"=>"nats", "fluent_timestamp"=>time}

      uri = generate_uri(d)

      run_server(uri) do
        d.run do
          d.expected_emits.each { |tag, time, record|
            send(uri, tag[5..-1], record)
            sleep 0.5
          }
        end
      end
    end

    test "multiple queues" do
      d = create_driver multiple_queue_conf

      time = Time.parse("2011-01-02 13:14:15 UTC").to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.test1", time, {"message"=>"nats", "fluent_timestamp"=>time}
      d.expect_emit "nats.fluent.test2", time, {"message"=>"nats", "fluent_timestamp"=>time}
      d.expect_emit "nats.fluent2.test1", time, {"message"=>"nats", "fluent_timestamp"=>time}
      d.expect_emit "nats.fluent2.test2", time, {"message"=>"nats", "fluent_timestamp"=>time}

      uri = generate_uri(d)

      run_server(uri) do
        d.run do
          d.expected_emits.each { |tag, time, record|
            send(uri, tag[5..-1], record)
            sleep 0.5
          }
        end
      end
    end

    test "without fluent timestamp" do
      d = create_driver basic_queue_conf

      time = Time.now.to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.test1", time, {"message"=>"nats"}

      uri = generate_uri(d)
      run_server(uri) do
        d.run do
          d.expected_emits.each do |tag, time, record|
            send(uri, tag[5..-1], record)
            sleep 0.5
          end
        end
      end
    end

    test "arrays" do
      d = create_driver basic_queue_conf

      time = Time.now.to_i
      Fluent::Engine.now = time
      
      d.expect_emit "nats.fluent.empty_array", time, []
      d.expect_emit "nats.fluent.string_array", time, %w(one two three)

      user = d.instance.user
      password = d.instance.password
      uri = "nats://#{user}:#{password}@#{d.instance.host}:#{d.instance.port}"
      run_server(uri) do
        d.run do
          d.expected_emits.each do |tag, time, record|
            send(uri, tag[5..-1], record)
            sleep 0.5
          end
        end
      end
    end

    test "empty publish string" do
      d = create_driver basic_queue_conf

      time = Time.now.to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.nil", time, {}

      uri = generate_uri(d)
      run_server(uri) do
        d.run do
          d.expected_emits.each do |tag, time, record|
            send(uri, tag[5..-1], nil)
            sleep 0.5
          end
        end
      end
    end

    test "regular publish string" do
      d = create_driver basic_queue_conf

      time = Time.now.to_i
      Fluent::Engine.now = time

      d.expect_emit "nats.fluent.string", time, "Lorem ipsum dolor sit amet"

      uri = generate_uri(d)
      run_server(uri) do
        d.run do
          d.expected_emits.each do |tag, time, record|
            send(uri, tag[5..-1], "Lorem ipsum dolor sit amet")
            sleep 0.5
          end
        end
      end
    end
  end

  def setup
    Fluent::Test.setup
  end

  def send(uri, tag, msg)
    system("test/nats-publish-message.rb", *%W[--uri=#{uri} --queue=#{tag} --message='#{msg.to_json}'])
  end

  def generate_uri(driver)
    user = driver.instance.user
    pass = driver.instance.password
    host = driver.instance.host
    port = driver.instance.port
    if user && pass
      "nats://#{user}:#{pass}@#{host}:#{port}"
    else
      "nats://#{host}:#{port}"
    end
  end
end
