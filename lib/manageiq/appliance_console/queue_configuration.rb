require "pathname"

module ManageIQ
  module ApplianceConsole
    class QueueConfiguration
      include ApplianceConsole::Logging
      QUEUE_YML = ManageIQ::ApplianceConsole::RAILS_ROOT.join("config/queue.yml")

      attr_accessor :host, :password, :port, :username

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

      def ask_for_queue_credentials
        self.host     = ask_for_ip_or_hostname("queue hostname or IP address")
        self.port     = ask_for_integer("port number", (1..65535), 9092)
        self.username = just_ask("username")
        count = 0
        loop do
          password1 = ask_for_password("queue password on #{host}")

          if password1.strip.length == 0
            say("\nPassword can not be empty, please try again")
            next
          end

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
        end
      end

      def friendly_inspect
        <<~EOS
          Host:     #{host}
          Username: #{username}
          Port:     #{port}
        EOS
      end

      def activate
        save
        true
      end

      private

      def settings_from_input
        {
          "production" => {
            "hostname" => host,
            "password" => password,
            "port"     => port,
            "username" => username
          }
        }
      end

      def save(settings = nil)
        settings ||= settings_from_input

        require 'yaml'
        File.write(DB_YML, YAML.dump(settings))
      end
    end
  end
end
