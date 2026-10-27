class PagesController < ApplicationController
  def home
    @prefill_code = params[:code].to_s.upcase.first(4)
  end
end
