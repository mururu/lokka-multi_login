require 'koala'

module Lokka
  module MultiLogin
    module Facebook
    end
  end

  module Helpers
    def facebook_authorize_url
      facebook_client.url_for_oauth_code
    end

    def facebook_user_params(params)
      access_token = facebook_client.get_access_token(params[:code])
      user_params = Koala::Facebook::API.new(access_token).get_object('me')
      [user_params['id'], user_params['name']]
    end

    def facebook_name(id)
      id || ""
    end

    def facebook_url(id)
      id ? "https://www.facebook.com/profile.php?id=#{id}" : ""
    end

    def facebook_client
      Koala::Facebook::OAuth.new(Option.facebook_key, Option.facebook_secret, "#{request.base_url}/login/facebook/callback")
    end
  end
end
