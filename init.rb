# Include hook code here

require 'auto_scopes'

ActiveRecord::Base.class_eval do
  include BCA::AutoScopes
end
