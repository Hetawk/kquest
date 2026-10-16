class SendWelcomeEmailJob < ApplicationJob
  queue_as :mailers
  retry_on Integrations::EkdSend::Client::DeliveryError, wait: :polynomially_longer, attempts: 4

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    name = ERB::Util.html_escape(user.name)
    html = "<p>Welcome to KINGDOM Quest, #{name}.</p><p>Your account is ready to use.</p>"
    text = "Welcome to KINGDOM Quest, #{user.name}. Your account is ready to use."
    Integrations::EkdSend::Client.new.send_email(
      to: user.email,
      subject: "Welcome to KINGDOM Quest",
      html: html,
      text: text
    )
  end
end
