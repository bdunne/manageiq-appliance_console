require "pathname"
require "linux_admin"

module ManageIQ
  module ApplianceConsole
    class QueueConfiguration
      QUEUE_YML = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config/queue.yml")

      attr_accessor :disk, :encoding, :host, :password, :port, :protocol, :run_queue, :username

      def initialize(hash = {})
        set_defaults
        self.run_queue = hash[:run_queue]
      end

      def set_defaults
        self.encoding  = "json"
        self.host      = "localhost"
        self.port      = 9092
        self.protocol  = "Kafka"
        self.username  = "root"
      end

      def run_interactive
        ask_questions

        clear_screen
        say "Activating the configuration using the following settings...\n#{friendly_inspect}\n"

        raise MiqSignalError unless activate

        say("\nConfiguration activated successfully.\n")
      rescue RuntimeError => e
        puts "Configuration failed#{": " + e.message unless e.class == MiqSignalError}"
        press_any_key
        raise MiqSignalError
      end

      def ask_questions
        ask_for_queue_credentials
      end

      def ask_for_queue_credentials(password_twice = true)
        self.host     = ask_for_ip_or_hostname("queue hostname or IP address", host) if host.blank? || !local?
        self.port     = ask_for_integer("port number", nil, port) unless local?
        self.username = just_ask("username", username) unless local?
        count = 0
        loop do
          password1 = ask_for_password("queue password on #{host}", password)
          # if they took the default, just bail
          break if (password1 == password)

          if password1.strip.length == 0
            say("\nPassword can not be empty, please try again")
            next
          end
          if password_twice
            password2 = ask_for_password("queue password again")
            if password1 == password2
              self.password = password1
              break
            elsif count > 0 # only reprompt password once
              raise "passwords did not match"
            else
              count += 1
              say("\nThe passwords did not match, please try again")
            end
          else
            self.password = password1
            break
          end
        end
      end

      def friendly_inspect
        output =  "Host:     #{host}\n"
        output << "Username: #{username}\n"
        output << "Port:     #{port}\n" if port
        output
      end

      def activate
        initialize_queue
        true
      end

      def initialize_queue
        log_and_feedback(__method__) do
          start_zookeeper
          relabel_queue_dir
          start_kafka
          # create_queue_user
        end
      end

      private

      def mount_point
        "/var/lib/kafka"
      end

      def queue_mount_point?
        LinuxAdmin::LogicalVolume.mount_point_exists?(mount_point.to_s)
      end

      def relabel_queue_dir
        AwesomeSpawn.run!("/sbin/restorecon -R -v #{mount_point}")
      end

      def start_zookeeper
        LinuxAdmin::Service.new("zookeeper").enable.start
      end

      def start_kafka
        LinuxAdmin::Service.new("kafka").enable.start
      end

      # merge all the non specified setings
      # for all the basic attributes, overwrite from this object (including blank values)
      def merged_settings
        merged = self.class.current
        settings_hash.each do |k, v|
          if v.present?
            merged['production'][k] = v
          else
            merged['production'].delete(k)
          end
        end
        merged
      end

      def save(settings = nil)
        settings ||= merged_settings
        do_save(settings)
      end

      def do_save(settings)
        require 'yaml'
        File.write(DB_YML, YAML.dump(settings))
      end

      def configure_ssl
        cert_file = PostgresAdmin.data_directory.join("server.crt").to_s
        key_file  = PostgresAdmin.data_directory.join("server.key").to_s
        AwesomeSpawn.run!("/usr/bin/generate_miq_server_cert.sh", :env => {"NEW_CERT_FILE" => cert_file, "NEW_KEY_FILE"  => key_file})

        FileUtils.chown("postgres", "postgres", cert_file)
        FileUtils.chown("postgres", "postgres", key_file)
        FileUtils.chmod(0644, cert_file)
        FileUtils.chmod(0600, key_file)
      end
    end
  end
end
