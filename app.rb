# encoding: UTF-8

require 'sinatra'
require 'sinatra/sequel'
require 'json'
require 'httparty'
require 'mail'

require 'pp'

def required_env_var(env)
  (ENV[env] || raise("Missing #{env} env var"))
end

class Object
  def tapp
    tap {|o| pp o }
  end
end


module Railscamp
class Thirteen < Sinatra::Base

  SUBMISSION_DEADLINE = Time.new(2013,5,21,0,0,0,"+10:00").utc
  TICKET_PRICE_CENTS = required_env_var("TICKET_PRICE_CENTS").to_i
  TICKET_PRICE_CURRENCY = "AUD"

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader

    set :pin, {
      publishable_key: required_env_var('PIN_TEST_PUBLISHABLE_KEY'),
      secret_key: required_env_var('PIN_TEST_SECRET_KEY'),
      api: 'test',
      api_root: 'https://test-api.pin.net.au/1'
    }
  end

  configure :production do
    set :pin, {
      publishable_key: required_env_var('PIN_LIVE_PUBLISHABLE_KEY'),
      secret_key: required_env_var('PIN_LIVE_SECRET_KEY'),
      api: 'live',
      api_root: 'https://api.pin.net.au/1'
    }
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


  migration "add charge columns" do
    database.add_column :entrants, :charge_token, String
  end

  class Entrant < Sequel::Model
    PUBLIC_ATTRS = [
      :name, :email, :dietary_reqs, :wants_bus,
      :cc_name, :cc_address, :cc_city, :cc_post_code, :cc_state, :cc_country,
      :card_token, :ip_address
    ]

    CHARGE_ATTRS = [ :charge_token ]

    set_allowed_columns *[ PUBLIC_ATTRS, CHARGE_ATTRS ].flatten
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

    def set_charge_token!(token)
      update charge_token: token
    end
    def charged?
      charge_token
    end
    def self.uncharged
      filter(charge_token: nil)
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
        ensure_host! "syd14.railscamps.org", 'http', 301
      end
    end
  end


  class Pin
    include HTTParty
    format :json
    base_uri Railscamp::Thirteen.settings.pin[:api_root]
    basic_auth Railscamp::Thirteen.settings.pin[:secret_key], ''
  end

  class EntrantCharger
    def charge!(entrant)
      if entrant.charged?
        raise("Entrant #{entrant.id} #{entrant.email} has already been charged")
      end
      body = Pin.post("/charges", body: params(entrant))
      if response = body['response']
        entrant.set_charge_token!(response['token'])
        response
      else
        entrant.errors.add("credit card", "charging failed")
        raise "Charge failed for entrant #{entrant.id} #{entrant.email}: \n#{body.inspect}"
      end
    end
    def params(entrant)
      {
        email: entrant.email,
        description: "Railscamp XIV Sydney",
        amount: TICKET_PRICE_CENTS,
        currency: TICKET_PRICE_CURRENCY,
        ip_address: entrant.ip_address,
        card_token: entrant.card_token
      }
    end
  end

  class EntrantMailer
    def mail!(entrant)
      if entrant.mailed?
        raise("already mailed #{entrant.id} #{entrant.email}")
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
