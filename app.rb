# Require dependencies
require 'sinatra'
require 'sinatra/multi_route'
require 'sinatra/activerecord'
require 'vonage'
require 'dotenv/load'
require 'json'

# Require models
current_dir = Dir.pwd
Dir["#{current_dir}/models/*.rb"].each { |file| require file }

# Set up the database
set :database, { adapter: 'postgresql',  encoding: 'unicode', database: 'verify_demo_db', pool: 2 }

# Create variables to hold Vonage API credentials
VONAGE_API_KEY = ENV['VONAGE_API_KEY']
VONAGE_API_SECRET = ENV['VONAGE_API_SECRET']
VONAGE_APPLICATION_ID = ENV['VONAGE_APPLICATION_ID']
VONAGE_NUMBER = ENV['VONAGE_NUMBER']

# Instantiate Vonage SDK client
def vonage
  @vonage ||= Vonage::Client.new(
    api_key: VONAGE_API_KEY,
    api_secret: VONAGE_API_SECRET,
    application_id: VONAGE_APPLICATION_ID,
    private_key: File.read('./private.key')
  )
end

# Enable session data
enable :sessions

route :get, '/' do
  erb :index
end

route :post, '/verify' do
  result = vonage.verify.request(
    number: params[:phone_number],
    brand: 'Vonage Demo'
  )

  puts result['request_id']

  session[:request_id] = result['request_id']
  session[:phone_number] = params[:phone_number]

  erb :verify
end

route :post, '/confirmation' do
  result = vonage.verify.check(
    request_id: session[:request_id],
    code: params[:pin]
  )

  if result['status'] == '0'
    @verify_status = 'You have successfully confirmed your phone number!'
    new_contestant = Contestant.new(phone_number: session[:phone_number])
    if new_contestant.save
      @contest_status = 'You have also been entered into the drawing. Good luck!'
    else
      @contest_status = "Your verification was successful, however #{new_contestant.errors.full_messages}."
    end
  else
    @verify_status = 'Oops! Something went wrong. Care to try again?'
    @contest_status = 'You must verify your phone number to be entered into the drawing.'
  end

  erb :confirmation
end

route :get, '/winner' do
  puts 'Picking a random contestant...'
  winner = Contestant.order('RANDOM()').first

  puts 'Calling the winner now...'
  response = vonage.voice.create(
    to: [{ type: 'phone', number: winner.phone_number }],
    from: { type: 'phone', number: VONAGE_NUMBER },
    ncco: [{ action: 'talk', text: 'Congratulations! You won! Please find us to claim your prize.' }]
  )

  puts response.inspect
end

route :get, '/webhooks/event' do
  status 200
  body ''
end

# Set application to listen on port 3000
set :port, 3000