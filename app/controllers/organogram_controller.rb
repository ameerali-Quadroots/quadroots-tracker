class OrganogramController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_page!("organogram") }

  def index
    @roots, @children = helpers.organogram_tree(User.employed)
  end
end
