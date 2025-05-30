class SendSlotAlertsForUsersJob < ApplicationJob
  queue_as :default

  def perform
    return if Flipper.enabled?(:pause_service) || ENV["STATIC_SITE_GEN"]

    User.active.where(alerting_intensity: 3).find_each do |user|
      slot = VmdSlot
        .where("last_updated_at >= ?", 7.minutes.ago)
        .where("(pfizer is true or moderna is true) and astrazeneca is false")
        .where("(SQRT(((latitude - ?)*110.574)^2 + ((longitude - ?)*111.320*COS(latitude::float*3.14159/180))^2)) < ? ", user.lat, user.lon, user.max_distance_km)
        .where("slots_1_days > 10")
        .order("next_rdv asc")
        .limit(1).first
      next unless slot
      SlotAlert.create!(vmd_slot: slot, user_id: user.id)
    end
  end
end
