class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def edit
  end

  def update
    if updating_password?
      unless @user.valid_password?(params[:user][:current_password])
        @user.errors.add(:current_password, "is incorrect")
        return render :edit, status: :unprocessable_entity
      end
    end

    # Remove current_password from the parameters
    update_params = user_params.except(:current_password)

    if @user.update(update_params)
      redirect_to root_path, notice: "Profile updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
    redirect_to root_path, alert: "Access denied!" unless @user == current_user
  end

  def user_params
    params.require(:user).permit(
      :name,
      :email,
      :password,
      :password_confirmation,
      :current_password
    )
  end

  def updating_password?
    params[:user][:password].present?
  end
end
