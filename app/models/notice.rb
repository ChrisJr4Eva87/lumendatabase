require 'recent_scope'
require 'validates_automatically'

class Notice < ActiveRecord::Base
  include Tire::Model::Search
  include Tire::Model::Callbacks
  include ValidatesAutomatically

  extend RecentScope

  HIGHLIGHTS = %i(
    title tag_list categories.name submitter_name recipient_name
    works.description works.url infringing_urls.url
  )

  UNDER_REVIEW_VALUE = 'Under review'
  RANGE_SEPARATOR = '..'

  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations
  has_many :category_relevant_questions,
    through: :categories, source: :relevant_questions
  has_many :related_blog_entries,
    through: :categories, source: :blog_entries, uniq: true
  has_many :entity_notice_roles, dependent: :destroy, inverse_of: :notice
  has_many :entities, through: :entity_notice_roles
  has_many :file_uploads
  has_many :infringing_urls, through: :works
  has_and_belongs_to_many :relevant_questions

  has_and_belongs_to_many :works

  validates_presence_of :works, :entity_notice_roles

  acts_as_taggable

  accepts_nested_attributes_for :file_uploads,
    reject_if: ->(attributes) { attributes['file'].blank? }

  accepts_nested_attributes_for :entity_notice_roles

  accepts_nested_attributes_for :works

  after_touch { tire.update_index }

  delegate :country_code, to: :recipient, allow_nil: true

  mapping do
    indexes :id, index: 'not_analyzed', include_in_all: false
    indexes :title
    indexes :date_received, type: 'date', include_in_all: false
    indexes :tag_list, as: 'tag_list'
    indexes :submitter_name, as: 'submitter_name'
    indexes :submitter_name_facet,
      analyzer: 'keyword', as: 'submitter_name',
      include_in_all: false
    indexes :recipient_name, as: 'recipient_name'
    indexes :recipient_name_facet,
      analyzer: 'keyword',  as: 'recipient_name', include_in_all: false
    indexes :categories, type: 'object', as: 'categories'
    indexes :category_facet,
      analyzer: 'keyword', as: ->(notice){ notice.categories.map(&:name) },
      include_in_all: false
    indexes :works,
      type: 'object',
      as: ->(notice){ notice.works.as_json({ only: [:description, :url] }) }
    indexes :infringing_urls,
      type: 'object',
      as: ->(notice){ notice.infringing_urls.as_json({ only: :url})}
  end

  def all_relevant_questions
    relevant_questions | category_relevant_questions
  end

  def submitter
    entities_that_have_submitted.first
  end

  def submitter_name
    submitter && submitter.name
  end

  def recipient
    entities_that_have_received.first
  end

  def recipient_name
    recipient && recipient.name
  end

  def mark_for_review
    update_column(:review_required, RiskAssessment.new(self).high_risk?)
  end

  def redacted(field)
    if review_required?
      UNDER_REVIEW_VALUE
    else
      send(field)
    end
  end

  private

  def entities_that_have_submitted
    entity_notice_roles.submitters.map(&:entity)
  end

  def entities_that_have_received
    entity_notice_roles.recipients.map(&:entity)
  end

end
