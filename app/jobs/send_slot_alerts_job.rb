class SendSlotAlertsJob < ApplicationJob
  queue_as :critical

  def perform(params)
    Rails.logger.info("[SendSlotAlertsJob] with params=#{@params}")
    return if Flipper.enabled?(:pause_service) || ENV["STATIC_SITE_GEN"]
    return unless params[:days]
    SlotAlertService.new(params[:days],
      params[:threshold],
      params[:user_alerting_intensity]).call
  end
end
