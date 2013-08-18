# encoding: UTF-8

require 'sinatra'
require 'sinatra/sequel'
require 'json'

module Railscamp
class Thirteen < Sinatra::Base

  SUBMISSION_DEADLINE = Time.new(2013,5,21,0,0,0,"+10:00").utc

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader
  end

  register Sinatra::SequelExtension

  migration "create the inital tables" do
    database.create_table :entrants do
      primary_key :id
      Time :created_at, null: false
      String :name, null: false
      String :email, null: false
      String :dietary_reqs, text: true
      TrueClass :wants_bus, null: false

      String :cc_name, null: false
      String :cc_address, null: false
      String :cc_city, null: false
      String :cc_post_code, null: false
      String :cc_state, null: false
      String :cc_country, null: false
      String :card_token, null: false

      String :ip_address, null: false
      Time   :chosen_at
      Time   :chosen_notified_at
    end

    database.create_table :scholarship_entrants do
      primary_key :id
      Time :created_at, null: false
      String :name, null: false
      String :email, null: false
      String :dietary_reqs, text: true
      TrueClass :wants_bus, null: false

      String :scholarship_pitch, null:false, text: true
      String :scholarship_github, null: false

      String :ip_address, null: false
      Time   :chosen_at
      Time   :chosen_notified_at
    end
  end

  class Entrant < Sequel::Model
    PUBLIC_ATTRS = [
      :name, :email, :dietary_reqs, :wants_bus,
      :cc_name, :cc_address, :cc_city, :cc_post_code, :cc_state, :cc_country,
      :card_token, :ip_address
    ]

    set_allowed_columns *PUBLIC_ATTRS
    plugin :validation_helpers

    def self.submitted_before_deadline
      filter { created_at >= SUBMISSION_DEADLINE }
    end
    def self.unchosen
      filter(chosen_at: nil)
    end
    def self.chosen
      exclude(chosen_at: nil)
    end

    def validate
      super
      validates_presence PUBLIC_ATTRS - [:dietary_reqs]
    end

    def before_save
      self.created_at = Time.now.utc
    end

    def choose!
      update(chosen_at: Time.now.utc)
    end
  end

  class ScholarshipEntrant < Sequel::Model
    PUBLIC_ATTRS = [
      :name, :email, :dietary_reqs, :wants_bus,
      :scholarship_github, :scholarship_pitch
    ]

    set_allowed_columns *PUBLIC_ATTRS
    plugin :validation_helpers

    def validate
      super
      validates_presence PUBLIC_ATTRS - [:dietary_reqs]
    end

    def before_save
      self.created_at = Time.now.utc
    end
  end

  configure :development do
    set :pin, {
      publishable_key: ENV['PIN_TEST_PUBLISHABLE_KEY'] || raise("Missing PIN_TEST_PUBLISHABLE_KEY env var"),
      api: 'test'
    }
  end

  configure :production do
    set :pin, {
      publishable_key: ENV['PIN_LIVE_PUBLISHABLE_KEY'] || raise("Missing PIN_LIVE_PUBLISHABLE_KEY env var"),
      api: 'live'
    }
  end

  helpers do
    def partial(name)
      erb name, layout: false
    end
    def ensure_host!(host, scheme, status)
      unless request.host == host && request.scheme == scheme
        redirect "#{scheme}://#{host}#{request.path}", status
      end
    end
  end

  configure :production do
    before do
      case request.path
      when "/register"
        ensure_host! "secure.ruby.org.au", 'https', 302
      else
        ensure_host! "melb13.railscamps.org", 'http', 301
      end
    end
  end

  get '/' do
    erb :home
  end

  get '/register' do
    erb :register
  end
  get '/scholarship' do
    erb :scholarship
  end

  post '/register' do
    STDERR.puts JSON.generate(params)
    entrant = Entrant.new(params[:entrant])
    if entrant.valid?
      entrant.save
      redirect "/✌"
    else
      @errors = entrant.errors
      erb :register
    end
  end


  post '/scholarship' do
    STDERR.puts JSON.generate(params)
    entrant = ScholarshipEntrant.new(params[:entrant])
    entrant.ip_address = request.ip
    if entrant.valid?
      entrant.save
      redirect "/✌"
    else
      @errors = entrant.errors
      erb :scholarship
    end
  end

  get '/✌' do
    erb :thanks
  end

end
end
