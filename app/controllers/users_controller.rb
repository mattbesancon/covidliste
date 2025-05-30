class UsersController < ApplicationController
  include UserAuthenticationViaSignedId

  before_action :authenticate_user!, except: %i[new create destroy confirm_destroy]
  before_action -> { authenticate_user_via_signed_id!(purpose: "users.destroy") }, only: %i[confirm_destroy destroy]
  before_action :sign_out_if_anonymized!
  before_action :find_or_create_match, only: %i[new show update]
  invisible_captcha only: [:create], honeypot: :subtitle
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def index
    policy_scope(User)
    redirect_to profile_path
  end

  def new
    @reviews = Review.all
    skip_authorization
    if current_partner
      redirect_to partners_vaccination_centers_path
    else
      @user = User.new(birthdate: Date.today.change(year: 1961))
      set_counters
    end
  end

  def show
    @user = current_user
    authorize @user
    prepare_phone_number

    respond_to do |format|
      format.html
      format.csv do
        send_data @user.to_csv, type: "text/csv", filename: "mes_donnees_covidliste.csv", disposition: :attachment
      end
    end
  end

  def update
    @user = current_user
    authorize @user
    @user.statement_accepted_at = Time.now.utc if !@user.statement && ActiveRecord::Type::Boolean.new.cast(user_params["statement"])
    @user.assign_attributes(user_params)
    if @user.save
      flash.now[:success] = "Modifications enregistrées."
    else
      flash.now[:error] = "Impossible d'enregistrer vos modifications."
    end
    prepare_phone_number
    render action: :show
  end

  def create
    @reviews = Review.all
    @user = User.new(user_params)
    @user.ensure_lat_lon # fallback in case lat/lon are not returning from client
    @user.statement_accepted_at = Time.zone.now if @user.statement
    @user.toc_accepted_at = Time.zone.now if @user.toc
    if Flipper.enabled?(:pause_service) || ENV["STATIC_SITE_GEN"]
      flash.now[:error] = "Le service est en pause. La création de compte est désactivée."
      return render action: :new, status: :unprocessable_entity
    end
    authorize @user
    @user.save
    set_counters
    prepare_phone_number
    render action: :new, status: :ok
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    flash.now[:error] = "Une erreur s’est produite."
    render action: :new, status: :unprocessable_entity
  end

  def confirm_destroy
    authorize current_user
  end

  def destroy
    authorize current_user
    current_user.anonymize!(params[:reason])
    sign_out current_user
    flash[:success] = "🎉 🎉 🎉 Votre compte a été supprimé de nos serveurs. Portez-vous bien."
    redirect_to root_path
  end

  private

  def find_or_create_match
    return unless current_user.present?
    match = current_user.find_or_create_match
    return unless match.present?
    @match = match
  end

  def set_counters
    @users_count = Rails.cache.fetch(:users_count, expires_in: 30.seconds) { Counter.total_users }
    @confirmed_matched_users_count = Rails.cache.fetch(:confirmed_matched_users_count, expires_in: 30.minutes) { Match.confirmed.count }
    @matched_users_count = Rails.cache.fetch(:matched_users_count, expires_in: 30.minutes) { User.where("matches_count > 0").count }
    @vaccination_centers_count = Rails.cache.fetch(:vaccination_centers_count, expires_in: 30.minutes) { VaccinationCenter.confirmed.count }
  end

  def prepare_phone_number
    @user.phone_number = @user.human_friendly_phone_number
  end

  def user_params
    if current_user&.has_role?(:volunteer)
      params.require(:user).permit(:email, :phone_number, :toc, :address, :lat, :lon, :birthdate, :password, :statement, :max_distance_km, :alerting_intensity, :firstname, :lastname)
    else
      params.require(:user).permit(:email, :phone_number, :toc, :address, :lat, :lon, :birthdate, :password, :statement, :max_distance_km, :alerting_intensity)
    end
  end

  def sign_out_if_anonymized!
    if current_user&.anonymized_at
      flash[:notice] = "Votre compte a été anonymisé car vous avez confirmé un RDV avec un centre de vaccination"
      sign_out
      redirect_to root_path
    end
  end

  def user_not_authorized(exception)
    policy_name = exception
      .policy.class.to_s.underscore
    message = exception.message || (t "#{policy_name}.#{exception.query}", scope: "pundit", default: :default)
    flash[:error] = message
    redirect_back(fallback_location: root_path)
  end
end
