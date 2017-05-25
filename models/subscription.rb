class Subscription
  include Mongoid::Document
  include Mongoid::Timestamps
  
  belongs_to :post, index: true
  belongs_to :account, index: true
  belongs_to :group, index: true
  belongs_to :membership, index: true
  belongs_to :team, index: true
  
  validates_presence_of :post, :account, :group, :membership, :team
  validates_uniqueness_of :account, :scope => :post

  before_validation do
  	self.team = self.post.team if self.post
    self.group = self.team.group if self.team
    self.membership = self.group.memberships.find_by(account: self.account) if self.group and self.account and !self.membership
  end    

  def self.admin_fields
    {
      :id => {:type => :text, :edit => false},
      :post_id => :lookup,
      :account_id => :lookup,
      :group_id => :lookup,
      :membership_id => :lookup,
      :team_id => :lookup
    }
  end
    
end
