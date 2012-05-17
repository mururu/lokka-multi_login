require File.expand_path File.dirname(__FILE__) + '/multi_login/twitter'
require File.expand_path File.dirname(__FILE__) + '/multi_login/facebook'

module Lokka
  module MultiLogin
    def self.registered(app)
      app.before %r{(?!^/admin/login$)^/admin/.*$} do
        user_filter(request.path_info)
      end

      # override
      app.get '/admin/users' do
        @users = User.all(:order => :created_at.desc).
                    page(params[:page], :per_page => settings.admin_per_page)
        haml :'plugin/lokka-multi_login/views/users/index', :layout => :"admin/layout"
      end

      # override
      app.get '/admin/login' do
        haml :"plugin/lokka-multi_login/views/login", :layout => false
      end

      # override
      app.get '/admin/users/:id/edit' do |id|
        @user = User.get(id) or raise Sinatra::NotFound
        haml :"plugin/lokka-multi_login/views/users/edit", :layout => :"admin/layout"
      end

      app.get '/admin/plugins/multi_login' do
        haml :"plugin/lokka-multi_login/views/index", :layout => :"admin/layout"
      end

      app.put '/admin/plugins/multi_login/permission' do
        set_filterd_paths(params)
        flash[:notice] = t("multi_login.filter_updated")
        redirect '/admin/plugins/multi_login'
      end

      Helpers.providers.each do |provider|
        app.put "/admin/plugins/multi_login/#{provider}" do
          Option.send("#{provider}_key=", params["#{provider}_key"])
          Option.send("#{provider}_secret=", params["#{provider}_secret"])
          flash[:notice] = t("multi_login.#{provider}.enabled")
          redirect '/admin/plugins/multi_login'
        end

        app.delete "/admin/plugins/multi_login/#{provider}" do
          Option.first(:name => "#{provider}_key").destroy
          Option.first(:name => "#{provider}_secret").destroy
          flash[:notice] = t("multi_login.#{provider}.disabled")
          redirect '/admin/plugins/multi_login'
        end

        app.get "/admin/plugins/multi_login/#{provider}/acceptable_users" do
          @names = acceptable_users(provider)
          haml :"plugin/lokka-multi_login/views/acceptable_users", :layout => :"admin/layout", :locals => { :provider => provider }
        end

        app.put "/admin/plugins/multi_login/#{provider}/acceptable_users" do
          add_acceptable_users(provider, params[:name])
          flash[:notice] = 'added.'
          redirect "/admin/plugins/multi_login/#{provider}/acceptable_users"
        end

        app.delete "/admin/plugins/multi_login/#{provider}/acceptable_users/:name" do |name|
          remove_acceptable_users(provider, name)
          flash[:notice] = 'removed.'
          redirect "/admin/plugins/multi_login/#{provider}/acceptable_users"
        end

        app.get "/login/#{provider}" do
          redirect send("#{provider}_authorize_url")
        end

        app.get "/login/#{provider}/callback" do
          id, name = send("#{provider}_user_params", params)
          if !id
            if logged_in?
              flash[:notice] = t("multi_login.#{provider}.add_failed")
              redirect 'admin/users'
            else
              flash[:notice] = t("multi_login.#{provider}.login_failed")
              redirect 'admin/login'
            end
          elsif send("#{provider}_on?") && acceptable_users(provider).include?(id)
            @user = User.send("#{provider}_authenticate", id)
            if @user
              session[:user] = @user.id
              flash[:notice] = t('logged_in_successfully')
              if session[:return_to]
                redirect_url = session[:return_to]
                session[:return_to] = false
                redirect redirect_url
              else
                redirect '/admin/'
              end
            elsif logged_in?
              user = current_user
              user.send("#{provider}_id=", id)
              if user.save(provider.to_sym)
                flash[:notice] = t("multi_login.#{provider}.added")
                redirect 'admin/users'
              else
                flash[:notice] = t("multi_login.#{provider}.add_failed")
                redirect 'admin/users/edit'
              end
            else
              user = User.new(:name => name, :"#{provider}_id" => id, :created_at => Time.now, :updated_at => Time.now)
              if user.save(provider.to_sym)
                session[:user] = user.id
                flash[:notice] = t('logged_in_successfully')
                redirect '/admin/'
              else
                flash[:notice] = t("multi_login.#{provider}.login_failed")
                redirect "/admin/login"
              end
            end
          else
            flash[:notice] = t("multi_login.#{provider}.not_allowed_login")
            redirect "/admin/login"
          end
        end
      end

      self.constants.each do |name|
        const = const_get(name)
        const.registered(app) if const.respond_to? :registered
      end
    end
  end

  module Helpers
    def providers
      MultiLogin.constants.map{|name|name.to_s.underscore}
    end

    def add_acceptable_users(provider, id)
      raise if id.include?(',')
      Option.send("acceptable_#{provider}_users=", acceptable_users(provider).push(id).uniq.join(','))
    end

    def remove_acceptable_users(provider, id)
      raise if id.include?(',')
      Option.send("acceptable_#{provider}_users=", acceptable_users(provider).delete_if{|u| u == id }.join(','))
    end

    def acceptable_users(provider)
      users = Option.send("acceptable_#{provider}_users") || ''
      users.split(',')
    end

    def admin_paths
      routes = [].tap{|routes| Lokka::App.routes.each{|m|m[1].each{|r|routes << r[0] }}}
      [].tap{|a| routes.map(&:source).each{|s| a << $1 if s =~ %r{(?!^\^/admin/(?:login|logout|\s))^\^/admin/(.*?)(?:/|\$)} }}.uniq.delete_if{|s|s==''}
    end

    def filterd_paths
      paths = Option.filterd_paths || ''
      paths.split(',')
    end

    def set_filterd_paths(params)
      ap = admin_paths
      Option.filterd_paths = params.keys.delete_if{|path|!ap.include?(path)}.join(',')
    end

    def filterd?(path)
      filterd_paths.any? do |f|
        path =~ %r{/admin/#{f}}
      end
    end

    def user_filter(path)
      if current_user.is_not_normal_user? && filterd?(path)
        flash[:notice] = path + t("multi_login.not_allowed_access")
        redirect '/admin/'
        return false
      end
    end

    def filterable_paths
      paths = filterd_paths
      {}.tap{|h| admin_paths.each{|path| h[path] = paths.include?(path)}}
    end

    providers.each do |provider|
      define_method "#{provider}_on?" do
        !!(Option.send("#{provider}_key") || Option.send("#{provider}_secret"))
      end
    end
  end
end

class User
  def is_not_normal_user?
    !(self.hashed_password && self.salt)
  end

  def is_normal_user?
    !is_normal_user?
  end

  class << self
    ::Lokka::Helpers.providers.each do |provider|
      define_method "#{provider}_authenticate" do |id|
        current_user = first(:"#{provider}_id" => id)
        return nil if current_user.nil?
        return current_user
      end
    end
  end
end

User.class_eval do
  Lokka::Helpers.providers.each do |provider|
    property :"#{provider}_id", String
    validates_presence_of :"#{provider}_id", :context => provider.to_sym
    validates_uniqueness_of :"#{provider}_id", :context => provider.to_sym

    define_method "is_#{provider}_user?" do
      !!self.send("#{provider}_id")
    end
  end
end
