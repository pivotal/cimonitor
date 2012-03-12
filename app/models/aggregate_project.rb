class AggregateProject < ActiveRecord::Base
  include Rails.application.routes.url_helpers
  has_many :projects

  before_destroy :remove_project_associations

  scope :with_projects, joins(:projects).where(:aggregate_projects => {:enabled => true}).select("distinct aggregate_projects.*")

  acts_as_taggable
  validates :name, presence: true
  validates :code, presence: true, length: {maximum: 4}

  def red?
    projects.detect {|p| p.red? }
  end

  def green?
    return false if projects.empty?
    
    projects.all? {|p| p.green? }
  end

  def online?
    return false if projects.empty?
    projects.all?(&:online?)
  end

  def status
    latest_status
  end

  def statuses
    projects.select {|p| !p.latest_status.nil?}.collect{|p| p.latest_status}.sort_by(&:id)
  end

  def latest_status
    statuses.last
  end

  def last_published_at
    last_online_status = ProjectStatus.online(projects, 1).first
    last_online_status ? last_online_status.published_at : nil
  end


  def building?
    projects.detect{|p| p.building? }
  end

  def recent_online_statuses(count = Project::RECENT_STATUS_COUNT)
    ProjectStatus.online(projects, count)
  end

  def url
    aggregate_project_path(self)
  end

  def red_since
    breaking_build.nil? ? nil : breaking_build.published_at
  end

  def never_been_green?
    projects.all? { |p| p.last_green.blank? }
  end

  def breaking_build
    return statuses.first if never_been_green?
    reds = []
    projects.each do |p|
      reds << p.statuses.find(:last, :conditions => ["online = ? AND success = ? AND published_at IS NOT NULL AND id > ?", true, false, p.last_green.id])
    end
    reds.compact.sort_by(&:published_at).first
  end

  def red_build_count
    return 0 if breaking_build.nil? || !online?
    red_project = projects.detect(&:red?)
    red_project.statuses.count(:conditions => ["online = ? AND id >= ?", true, red_project.breaking_build.id])
  end

  private
  def remove_project_associations
    projects.map {|p| p.aggregate_project = nil; p.save! }
  end

end
