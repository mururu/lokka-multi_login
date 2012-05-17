require 'oauth'

module Lokka
  module MultiLogin
    module Twitter
    end
  end

  module Helpers
    def twitter_authorize_url
      consumer = OAuth::Consumer.new(Option.twitter_key, Option.twitter_secret, :site => "https://twitter.com", :authorize_path => '/oauth/authenticate')
      request_token = consumer.get_request_token(:oauth_callback => "#{request.base_url}/login/twitter/callback")
      session[:request_token] = request_token
      request_token.authorize_url
    end

    def twitter_user_params(params)
      request_token = session[:request_token]
      access_token = request_token.get_access_token(
          {},
          :oauth_token => params[:oauth_token],
          :oauth_verifier => params[:oauth_verifier])
      [access_token.params[:screen_name]]*2
    rescue
      [nil]*2
    end

    def twitter_name(name)
      name ? "@#{name}" : ""
    end

    def twitter_url(name)
      name ? "https://twitter.com/#!/#{name}" : ""
    end
  end
end
