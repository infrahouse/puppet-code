# Usage:
# $passwd = aws_get_secret('packager-key-focal', $facts['ec2_metadata']['placement']['region'])
Puppet::Functions.create_function(:aws_get_secret) do

  require 'json'
  require 'aws-sdk-core'
  require 'aws-sdk-secretsmanager'

  dispatch :get_secret_impl do
    param 'Variant[String, Numeric]', :key
    param 'String', :region
  end

  ##
  # get_secret
  #
  # Lookup a given key in AWS Secrets Manager
  #
  # @param key Key to lookup
  # @param region String
  #
  # @return One of Hash, String, (Binary?) depending on the value returned
  # by AWS Secrets Manager.
  def get_secret_impl(key, region)
    client_opts = {}
    client_opts[:region] = region

    secretsmanager = Aws::SecretsManager::Client.new(client_opts)

    response = nil
    secret = nil

    call_function('debug', "[aws_get_secret] Looking up #{key}")
    begin
      response = secretsmanager.get_secret_value(secret_id: key)
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException
      call_function('debug', "[aws_get_secret] No data found for #{key}")
    rescue Aws::SecretsManager::Errors::UnrecognizedClientException
      raise Puppet::DataBinding::LookupError, "[aws_get_secret] No permission to access #{key}"
    rescue Aws::SecretsManager::Errors::ServiceError => e
      raise Puppet::DataBinding::LookupError, "[aws_get_secret] Failed to lookup #{key} due to #{e.message}"
    end
    secret = response.secret_string

    begin
      result = JSON.parse(secret)
    rescue JSON::ParserError
      call_function('debug', "[aws_get_secret] Not a hashable result")
      result = secret
    end

    result
  end
end
