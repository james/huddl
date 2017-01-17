class Mapplication
  include Mongoid::Document
  include Mongoid::Timestamps
  
  field :status, :type => String
  field :answers, :type => Array  

  belongs_to :group             
  belongs_to :account, index: true, class_name: "Account", inverse_of: :mapplications
  belongs_to :processed_by, index: true, class_name: "Account", inverse_of: :mapplications_processed
  
  has_many :verdicts, :dependent => :destroy
  has_one :membership, :dependent => :nullify
  
  validates_presence_of :account, :group, :status
  validates_uniqueness_of :account, :scope => :group  
      
  def self.pending
    where(status: 'pending')
  end
  
  def self.rejected
    where(status: 'rejected')
  end  
  
  def answers=(x)
    if x.is_a? String
      super(eval(x))
    else
      super(x)
    end
  end
  
  def acceptable?
    verdicts.proposers.count > 0 and verdicts.blockers.count == 0
  end
        
  def self.admin_fields
    {
      :summary => {:type => :text, :index => false, :edit => false},
      :account_id => :lookup,
      :group_id => :lookup,
      :verdicts => :collection,
      :status => :select,
      :answers => :text_area
    }
  end
  
  after_create do
    if ENV['SMTP_ADDRESS']
      mail = Mail.new
      mail.bcc = Account.where(:id.in => group.memberships.pluck(:account_id)).pluck(:email)
      mail.from = "Huddl <team@huddl.tech>"
      mail.subject = "#{account.name} expressed an interest in #{group.name}"
      
      account = self.account
      group = self.group
      html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
        body "#{account.name} expressed an interest in joining #{group.name}. Visit http://#{ENV['DOMAIN']}/h/#{group.slug} to review the application.<br /><br />Best,<br />Team Huddl"
      end
      mail.html_part = html_part       
      
      mail.deliver
    end    
  end
  
  def summary
    "#{self.account.name} - #{self.group.name}"
  end
    
  def self.statuses
    ['pending', 'accepted', 'rejected']
  end    

end
