$zendesk_client = ZendeskAPI::Client.new do |config|
  config.url = Rails.application.secrets.wbid[:url] "https://meyouhealth.zendesk.com/api/v2"
  config.username = "admin@meyouhealth.com"
  config.token = "utPpL5knOyabCysC2nu34x2xlWdXpA3BXQt6CUbd"
end
