require "opsworks-connect/version"
require 'aws'

module Opsworks
  class Driver
    def ask?(question, options)
      answer = nil
      answer = options[0] if options.length == 1

      while answer == nil
        puts "",question
        options
          .each.with_index(1) do |option, idx|
          puts "[#{idx}] #{option[:name]}"
        end
        print "Choose: "
        input = gets.chomp.to_i
        begin
          answer = options[input]
        rescue
          puts "Invalid choice, please try again.\n"
        end
      end
      answer
    end

    def connect
      begin
        user = AWS::IAM.new.client.get_user[:user]
      rescue AWS::Errors::MissingCredentialsError
        puts "Uh oh. AWS Credentials could not be found!", ""
        puts "Do one of the following, then try opsworks-connect again:"
        puts " * Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to ENV"
        puts " * Setup ~/.aws/credentials file"
        return
      rescue Errno::EHOSTDOWN
        puts "AWS OpsWorks API is not responding, please wait and try again."
        puts "You may be rate-limited."
        return
      end

      puts "Welcome to OpsWorks-Connect!"

      client = AWS::OpsWorks.new.client
      stacks = client.describe_stacks[:stacks].map do |stack|
        {stack_id: stack[:stack_id], name: stack[:name]}
      end.sort_by { |option| option[:name] }

      stack = ask?("Stacks", stacks)
      layers = client.describe_layers(stack_id: stack[:stack_id])[:layers].map do |layer|
        {layer_id: layer[:layer_id], name: layer[:name]}
      end.sort_by { |option| option[:name] }

      layer = ask?("Layers", layers)
      instances = client.describe_instances(layer_id: layer[:layer_id])[:instances]
        .reject { |instance| instance[:public_ip].nil? }
        .map do |instance|
          {
            instance_id: instance[:instance_id],
            name: "#{instance[:hostname]} (#{instance[:status]})",
            public_ip: instance[:public_ip]
          }
        end.sort_by { |option| option[:name] }

      instance = ask?("Instances", instances)

      cmd = "ssh"
      cmd += " -i #{ENV['AWS_OPSWORKS_IDENTITY_FILE']}" unless ENV['AWS_OPSWORKS_IDENTITY_FILE'].nil?
      cmd += " #{user[:user_name]}@#{instance[:public_ip]}"

      puts "", cmd
      system "#{cmd}"
      if $?.exitstatus == 255
        puts "","Did you properly set ENV['AWS_OPSWORKS_IDENTITY_FILE']? (= #{ENV['AWS_OPSWORKS_IDENTITY_FILE'] or "nil"})"
      end
    end
  end
end
