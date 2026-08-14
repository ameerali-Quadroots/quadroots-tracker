class HostingController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("hosting") }

  def index
  end
end
