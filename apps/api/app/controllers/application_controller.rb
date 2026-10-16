class ApplicationController < ActionController::API
  private

  def render_error(code:, message:, status:, details: {})
    render(
      json: {
        error: {
          code: code,
          message: message,
          details: details
        }
      },
      status: status
    )
  end

  def render_validation_error(record)
    details = record.errors.group_by_attribute.transform_values do |errors|
      errors.map do |error|
        { code: error.type.to_s, message: error.message }
      end
    end

    render_error(
      code: "validation_failed",
      message: "The submitted data is invalid.",
      status: :unprocessable_entity,
      details: details
    )
  end

  def render_not_found
    render_error(
      code: "not_found",
      message: "The requested resource was not found.",
      status: :not_found
    )
  end

  def prototype_api_only?
    return true if Rails.env.development? || Rails.env.test?

    render_not_found
    false
  end
end
