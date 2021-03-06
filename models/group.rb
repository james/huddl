class Group
  include Mongoid::Document
  include Mongoid::Timestamps
  extend Dragonfly::Model
  
  dragonfly_accessor :image
  
  def self.enablable
    %w{teams qualities timetables rotas tiers accommodation transport bookings inventory budget}
  end  
  
  field :name, :type => String
  field :slug, :type => String
  field :image_uid, :type => String
  field :intro_for_members, :type => String
  field :enable_applications, :type => Boolean  
  field :intro_for_non_members, :type => String
  field :application_questions, :type => String
  field :anonymise_supporters, :type => Boolean
  field :democratic_threshold, :type => Boolean
  field :fixed_threshold, :type => Integer
  field :ask_for_date_of_birth, :type => Boolean
  field :ask_for_gender, :type => Boolean
  field :ask_for_poc, :type => Boolean  
  field :ask_for_facebook_profile_url, :type => Boolean
  field :featured, :type => Boolean
  field :member_limit, :type => Integer
  field :proposing_delay, :type => Integer
  field :require_reason_proposer, :type => Boolean
  field :require_reason_supporter, :type => Boolean
  field :booking_limit, :type => Integer
  field :processed_via_stripe, :type => Integer
  field :disable_stripe, :type => Boolean
  field :balance, :type => Float
  field :paypal_email, :type => String
  field :currency, :type => String
  field :teamup_calendar_url, :type => String
  field :mailgun_route_id, :type => String
  enablable.each { |x|
    field :"enable_#{x}", :type => Boolean
  }
    
  before_validation do
    self.balance = 0 if self.balance.nil?
    self.processed_via_stripe = 0 if self.processed_via_stripe.nil?
    self.enable_teams = true if self.enable_budget
    self.disable_stripe = true if self.currency == 'SEK'
    self.member_limit = self.memberships.count if self.member_limit and self.member_limit < self.memberships.count
  end
  
  after_create do    
    notifications.create! :notifiable => self, :type => 'created_group'    
    memberships.create! account: account, admin: true        
    if enable_teams
      general = teams.create! name: 'General', account: account, prevent_notifications: true
      general.teamships.create! account: account, prevent_notifications: true
    end
  end
  
  after_create :send_email
  def send_email
   	if ENV['SMTP_ADDRESS']
      mail = Mail.new
      mail.to = ENV['ADMIN_EMAIL']
      mail.from = ENV['BOT_EMAIL']
      mail.subject = "New group: #{name}"
      
      group = self
      html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
        body %Q{#{group.account.name} (#{group.account.email}) created a new group: <a href="#{ENV['BASE_URI']}/h/#{group.slug}">#{group.name}</a>}
      end
      mail.html_part = html_part
      
      mail.deliver
    end
  end
  handle_asynchronously :send_email
    
  def create_route
    if ENV['MAILGUN_API_KEY']
      mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
      response = mg_client.post('routes', {:description => slug, :expression => "match_recipient('^#{slug}\\+(.*)@#{ENV['MAILGUN_DOMAIN']}$')", :action => "forward('#{ENV['BASE_URI']}/h/#{slug}/inbound/\\1')"})
      update_attribute(:mailgun_route_id, JSON.parse(response.body)['route']['id'])    
    end
  end  
  
  after_destroy :delete_route
  def delete_route
    if ENV['MAILGUN_API_KEY']
      mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
      response = mg_client.delete("routes/#{mailgun_route_id}")
      update_attribute(:mailgun_route_id, nil)          
    end
  rescue
  end
  
  attr_accessor :_replace_route
  before_validation do
    @_replace_route = slug_changed?
    true
  end
  after_save :replace_route
  def replace_route
    if persisted? and @_replace_route
      @_replace_route = nil
      delete_route
      create_route      
    end
  end  
  
  belongs_to :account, index: true
  
  validates_presence_of :name, :slug
  validates_uniqueness_of :slug
  validates_format_of :slug, :with => /\A[a-z0-9\-]+\z/
  
  has_many :memberships, :dependent => :destroy
  has_many :mapplications, :dependent => :destroy  
  has_many :notifications, :dependent => :destroy
  has_many :verdicts, :dependent => :destroy
  has_many :payments, :dependent => :nullify
  has_many :withdrawals, :dependent => :nullify
  
  # Timetable
  has_many :timetables, :dependent => :destroy
  has_many :spaces, :dependent => :destroy
  has_many :tslots, :dependent => :destroy
  has_many :activities, :dependent => :destroy
  has_many :attendances, :dependent => :destroy
  # Teams
  has_many :teams, :dependent => :destroy
  has_many :teamships, :dependent => :destroy  
  has_many :posts, :dependent => :destroy
  has_many :subscriptions, :dependent => :destroy
  has_many :comments, :dependent => :destroy
  has_many :comment_likes, :dependent => :destroy
  # Rotas
  has_many :rotas, :dependent => :destroy
  has_many :roles, :dependent => :destroy
  has_many :rslots, :dependent => :destroy
  has_many :shifts, :dependent => :destroy
  # Tiers
  has_many :tiers, :dependent => :destroy
  has_many :tierships, :dependent => :destroy
  # Accommodation
  has_many :accoms, :dependent => :destroy
  has_many :accomships, :dependent => :destroy
  # Transport
  has_many :transports, :dependent => :destroy
  has_many :transportships, :dependent => :destroy
  # Budget  
  has_many :spends, :dependent => :destroy
  # Bookings
  has_many :bookings, :dependent => :destroy
  has_many :booking_lifts, :dependent => :destroy
  # Qualities
  has_many :qualities, :dependent => :destroy
  has_many :cultivations, :dependent => :destroy
  # Inventory
  has_many :inventory_items, :dependent => :destroy
  
  def application_questions_a
    q = (application_questions || '').split("\n").map(&:strip).reject { |l| l.blank? }
    q.empty? ? [] : q
  end  
  
  def members
    Account.where(:id.in => memberships.pluck(:account_id))
  end
  
  def cultivators
    Account.where(:id.in => cultivations.pluck(:account_id))
  end
      
  def admin_emails
    Account.where(:id.in => memberships.where(admin: true).pluck(:account_id)).pluck(:email)
  end
  
  def emails
    Account.where(:unsubscribed.ne => true).where(:id.in => memberships.where(:unsubscribed.ne => true).pluck(:account_id)).pluck(:email)
  end  
  
  def incomings
    i = 0
    tiers.each { |tier|
      i += tier.cost*tier.tierships.count
    }
    accoms.select { |accom| accom.accomships.count > 0 }.each { |accom|
      i += accom.cost
    }
    transports.each { |transport|
      i += transport.cost*transport.transportships.count
    }
    i
  end
  
  def anonymise_proposers
    false
  end
        
  def self.admin_fields
    h = {
      :name => :text,
      :slug => :slug,      
      :image => :image,
      :intro_for_members => :wysiwyg,
      :fixed_threshold => :number,
      :member_limit => :number,
      :proposing_delay => :number,
      :require_reason_proposer => :check_box,
      :require_reason_supporter => :check_box,
      :booking_limit => :number,
      :processed_via_stripe => :number,
      :disable_stripe => :check_box,
      :balance => :number,
      :democratic_threshold => :check_box,
      :enable_applications => :check_box,      
      :intro_for_non_members => :wysiwyg,
      :application_questions => :text_area,
      :anonymise_supporters => :check_box,
      :ask_for_date_of_birth => :check_box,
      :ask_for_gender => :check_box,
      :ask_for_poc => :check_box,
      :ask_for_facebook_profile_url => :check_box,
      :featured => :check_box,
      :paypal_email => :text,
      :currency => :select,
      :teamup_calendar_url => :url,
      :account_id => :lookup,
      :memberships => :collection,
      :mapplications => :collection,
      :spends => :collection,
      :rotas => :collection,
      :teams => :collection
    }
    h.merge(Hash[enablable.map { |x|
          ["enable_#{x}".to_sym, :check_box]
        }])
  end
  
  def self.currencies
    %w{GBP EUR USD SEK}
  end
  
  def self.currency_symbol(code)
    case code
    when 'GBP'; '£'
    when 'EUR'; '€'
    when 'USD'; '$'
    when 'SEK'; 'kr'
    end    
  end
  
  def currency_symbol
    Group.currency_symbol(currency)
  end
    
  def admins
    Account.where(:id.in => memberships.where(:admin => true).pluck(:account_id))
  end
  
  def self.new_tips
    {      
      :application_questions => 'One per line'
    }
  end
  
  def self.new_hints
    {
      :currency => 'This cannot be changed, choose wisely',
      :fixed_threshold => 'Automatically accept applications with this number of proposers + supporters (with at least one proposer)',
      :proposing_delay => 'Accept proposers on applications only once the application is this many hours old'
    }
  end
  
  def self.human_attribute_name(attr, options={})  
    {
      :intro_for_non_members => 'Intro for non-members',
      :enable_applications => 'People must apply to join',
      :paypal_email => 'PayPal email',
      :ask_for_poc => 'Ask whether applicants identify as a person of colour',
      :ask_for_facebook_profile_url => 'Ask for Facebook profile URL',
      :fixed_threshold => 'Magic number',
      :democratic_threshold => 'Allow all group members to suggest a magic number, and use the median',
      :teamup_calendar_url => 'Teamup calendar URL',
      :require_reason_proposer => 'Proposers must provide a reason',
      :require_reason_supporter => 'Supporters must provide a reason'
    }[attr.to_sym] || super  
  end   
  
  def self.edit_tips
    self.new_tips
  end  
  
  def self.edit_hints
    self.new_hints
  end    
    
  def threshold
    democratic_threshold ? (median_threshold if democratic_threshold) : fixed_threshold
  end
  
  before_validation do
    if democratic_threshold
      self.fixed_threshold = false
    end
    true
  end
  
  def median_threshold
    array = memberships.pluck(:desired_threshold).compact
    if array.length > 0
      sorted = array.sort
      len = sorted.length
      ((sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0).round
    end
  end
    
end
