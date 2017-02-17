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
    (!group.member_limit or (group.memberships.count < group.member_limit)) and verdicts.proposers.count > 0 and verdicts.blockers.count == 0
  end
  
  def meets_threshold
    group.threshold and (verdicts.proposers.count + verdicts.supporters.count) >= group.threshold
  end
  
  def accept
    mapplication = self    
    account = mapplication.account
    group = mapplication.group    
    update_attribute(:status, 'accepted')
    group.memberships.create account: account, mapplication: mapplication
            
    if !mapplication.account.sign_ins or mapplication.account.sign_ins == 0
      action = %Q{<a href="http://#{ENV['DOMAIN']}/accounts/edit?sign_in_token=#{account.sign_in_token}&h=#{group.slug}">Click here to finish setting up your account and get involved with the co-creation!</a>}
    else
      action = %Q{<a href="http://#{ENV['DOMAIN']}/h/#{group.slug}?sign_in_token=#{account.sign_in_token}">Sign in to get involved with the co-creation!</a>}
    end
        
    if ENV['SMTP_ADDRESS']
      mail = Mail.new
      mail.to = mapplication.account.email
      mail.from = "Huddl <team@huddl.tech>"
      mail.subject = "You're now a member of #{group.name}"
      
      html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
        body "Hi #{account.firstname},<br /><br />You were accepted into #{group.name} on Huddl. #{action}<br /><br />Best,<br />Team Huddl" 
      end
      mail.html_part = html_part
      
      mail.deliver
            
      mail = Mail.new
      mail.bcc = group.admin_emails
      mail.from = "Huddl <team@huddl.tech>"
      mail.subject = "#{account.name} was accepted into #{group.name}"
      
      html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
        body %Q{Hi admins of #{group.name},<br /><br />#{account.name} was #{'automatically ' if !mapplication.processed_by}accepted into #{group.name}#{" by #{mapplication.processed_by.name}" if mapplication.processed_by}. <a href="http://#{ENV['DOMAIN']}/h/#{group.slug}">View members</a><br /><br />Best,<br />Team Huddl}
      end
      mail.html_part = html_part       
      
      mail.deliver
      
    end    
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
      account = self.account
      group = self.group
      
      mail = Mail.new
      mail.bcc = group.emails
      mail.from = "Huddl <team@huddl.tech>"
      mail.subject = "#{account.name} applied to #{group.name}"
     
      html_part = Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
        body %Q{#{account.name} applied to #{group.name}. <a href="http://#{ENV['DOMAIN']}/h/#{group.slug}/applications">View applications</a><br /><br />Best,<br />Team Huddl<br /><br /><a href="http://#{ENV['DOMAIN']}/accounts/edit">Stop these emails</a>}
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
