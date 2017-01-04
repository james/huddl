class Gatheringship
  include Mongoid::Document
  include Mongoid::Timestamps
  
  field :paid, :type => Integer
  field :joined_facebook_group, :type => Boolean

  belongs_to :gathering  
  
  belongs_to :account, index: true, class_name: "Account", inverse_of: :memberships
  belongs_to :accepted_by, index: true, class_name: "Account", inverse_of: :memberships_accepted
  
  def shifts
    Shift.where(:account_id => account_id, :rota_id.in => gathering.rota_ids)
  end
  
  def teamships
    Teamship.where(:account_id => account_id, :team_id.in => gathering.team_ids)
  end
        
  def self.admin_fields
    {
      :account_id => :lookup,
      :gathering_id => :lookup,      
      :accepted_by => :lookup,
      :paid => :number,
      :joined_facebook_group => :check_box,
    }
  end
    
end
