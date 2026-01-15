class ClearController < ApplicationController

  USER_SLUG_WHITELIST = %w[
    bmath
    mcgd
    johnolilly
    pt
    josh-elman
    tomfrange
    brendan
    kevinakwok
    tihomir-bajic
    marcus-gosling
    komal-sethi
    melissa-gail-pancoast
    russh
    ericries
    nguyen
    gary-ross-3
    arina-shulga-1
    streeter
    devon-boulton-mills
    stevenewcomb
  ]


  def require_admin_or_whitelist
    raise ActiveRecord::RecordNotFound unless user_signed_in?
    unless current_user.admin? || USER_SLUG_WHITELIST.include?(current_user.slug_name)
      raise ActiveRecord::RecordNotFound
    end
  end


  def offer
    @compensations = CacheItem.get_cache "__cache_salaries_stats__"
    unless @compensations.nil?
      # filter down to only a few key areas w/ data
      @compensations[:tags] = {
        locations: {
          "San Francisco": @compensations[:tags][:locations]["San Francisco"],
          "New York City": @compensations[:tags][:locations]["New York City"],
        },
        roles: {
          "Developer": @compensations[:tags][:roles]["Developer"],
          "Designer": @compensations[:tags][:roles]["Designer"],
          "Mobile Developer": @compensations[:tags][:roles]["Mobile Developer"],
          "Frontend Developer": @compensations[:tags][:roles]["Frontend Developer"],
          "Backend Developer": @compensations[:tags][:roles]["Backend Developer"],
          "Full Stack Developer": @compensations[:tags][:roles]["Full Stack Developer"],
          "Product Manager": @compensations[:tags][:roles]["Product Manager"]
        }
      }
    end
    @valuations = CacheItem.get_cache "__cache_valuation_stats__"
    @presenter = Presenter::Clear.new
    render layout: @presenter.layout
  end


  def landing
    @presenter = Presenter::Clear.new
    render layout: @presenter.layout(:landing)
  end


  def amendment
    @presenter = Presenter::Clear.new
    render layout: @presenter.layout
  end


  def how_much
    @presenter = Presenter::Clear.new
    render layout: @presenter.layout
  end


end
