require 'pathname'
require 'util/miq-password'
require 'fileutils'

RAILS_ROOT ||= Pathname.new(__dir__).join("../../..")

module ManageIQ
  module ApplianceConsole
    class ConfigYamlFile
      attr_accessor :file, :template_file

      def initialize(file, template_file = nil)
        self.file = file
        self.template_file = template_file
      end

      def config(reload = false)
        @config = nil if reload
        @config ||= decrypt_passwords(read_from_file)
      end

      def save
        write_to_file(config)
      end

      def exists?
        File.exist?(file)
      end

      private

      def decrypt_passwords(data)
        data.each_with_object({}) do |(env, settings), decrypted|
          decrypted[env] = {}
          env.each { |k, v| decrypted[env][k] = k.to_s == "password" ? MiqPassword.try_decrypt(v) : v }
        end
      end

      def encrypt_passwords(data)
        data.each_with_object({}) do |(env, settings), encrypted|
          encrypted[env] = {}
          env.each { |k, v| encrypted[env][k] = k.to_s == "password" ? MiqPassword.try_encrypt(v) : v }
        end
      end

      def read_from_file
        require 'yaml'
        return YAML.load_file(file) if exists?
        return YAML.load_file(template_file) if File.exist?(template_file)
        {}
      end

      def write_to_file(data)
        require 'yaml'
        File.write(self.file, YAML.dump(encrypt_passwords(data)))
      end
    end
  end
end
