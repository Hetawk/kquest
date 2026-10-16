module Api
  module V1
    class AssetsController < ApplicationController
      before_action :prototype_api_only?
      before_action :require_current_user

      def create
        return unless current_user

        uploaded_asset = Integrations::EkdAssets::Client.new.upload_cover(
          user: current_user,
          uploaded_file: params.require(:file)
        )
        render(
          json: {
            data: {
              id: uploaded_asset.id,
              public_url: uploaded_asset.public_url,
              content_type: uploaded_asset.content_type,
              file_size: uploaded_asset.file_size
            }
          },
          status: :created
        )
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "Choose an image to upload.",
          status: :unprocessable_entity
        )
      rescue Integrations::EkdAssets::Client::InvalidUpload => error
        render_error(
          code: "invalid_cover_image",
          message: error.message,
          status: :unprocessable_entity
        )
      rescue Integrations::EkdAssets::Client::UploadError => error
        render_error(
          code: "asset_upload_failed",
          message: error.message,
          status: :bad_gateway
        )
      end
    end
  end
end
