# BcaCommonScopes

module BCA
  module AutoScopes
    def self.included(base)
      ActiveRecord::Base.class_eval do
        extend BCA::AutoScopes::ClassMethods
        
        if defined?(Rails) && Rails.version =~ /^3/
          extend BCA::AutoScopes::Rails3
        else
          extend BCA::AutoScopes::Rails2
        end
      end
      
      base.class_eval do
        @scopes_added_by_common_scopes = []
        @failed_to_add_scopes = []
      end
    end

    module ClassMethods
      # Throw in the whole kitchen sink.
      #
      # >> User.class_eval do
      # ?>   auto_scopes
      # >> end
      # => nil
      # >> User.extra_scopes
      # => [:limit, :offset, :recent, :recently_updated, :id_greater_than,
      #       :id_less_than, :id_between, :in_id_order, :in_reverse_id_order,
      #       :id_equals, :login_contains, :login_starts_with, :login_ends_with,
      #       :login_is, :in_login_order, :in_reverse_login_order, :password_contains,
      #       :password_starts_with, :password_ends_with, :password_is,
      #       :in_password_order, :in_reverse_password_order, :salt_contains,
      #       :salt_starts_with, :salt_ends_with, :salt_is, :in_salt_order,
      #       :in_reverse_salt_order, :activation_code_contains,
      #       :activation_code_starts_with, :activation_code_ends_with,
      #       :activation_code_is, :in_activation_code_order,
      #       :in_reverse_activation_code_order, :created_at_older_than,
      #       :created_at_newer_than, :created_at_in_past, :created_at_in_future,
      #       :in_created_at_order, :in_reverse_created_at_order, :updated_at_older_than,
      #       :updated_at_newer_than, :updated_at_in_past, :updated_at_in_future,
      #       :in_updated_at_order, :in_reverse_updated_at_order, :activated_at_older_than,
      #       :activated_at_newer_than, :activated_at_in_past, :activated_at_in_future,
      #       :in_activated_at_order, :in_reverse_activated_at_order, :deleted_at_older_than,
      #       :deleted_at_newer_than, :deleted_at_in_past, :deleted_at_in_future,
      #       :in_deleted_at_order, :in_reverse_deleted_at_order]
      # >>
      #
      # In the future, I may want to let the user protect certain columns,
      # specify which columns will be run, or even alias the column (for
      # example, "in_deleted_at_order" could be turned into "in_deletion_order".
      #
      # In the mean time, judicious use of aliasing could help.
      def auto_scopes()
        begin
          add_limit_scopes
          add_created_at_scopes
          add_updated_at_scopes
          add_random_scopes

          for column in self.columns
            case column.type
            when :integer
              add_integer_scopes(column.name)
            when :float
              add_float_scopes(column.name)
            when :datetime
              add_date_time_scopes(column.name)
            when :boolean
              add_boolean_scopes(column.name)
            when :string
              add_string_scopes(column.name)
            end
          end
        rescue Exception => e
          puts "ERROR: auto scope failed for model #{self.class.name}. Message: #{e.message}"
        end

        nil
      end

      # returns a list of scoping functions added to the AR by
      # this module.
      def extra_scopes()
        @scopes_added_by_common_scopes
      end

      def failed_extra_scopes()
        @failed_to_add_scopes
      end

      protected

      # Sometimes important AR functions can get smooshed.  I don't want
      # that to happen.
      def politely_add_named_scope(*args)
        if self.respond_to? args.first
          Rails.logger.warn "Can't add named_scope #{args.first} to #{self.name}. It would overwrite an existing method."
          @failed_to_add_scopes << args.first unless @failed_to_add_scopes.include?(args.first)
        else
          @scopes_added_by_common_scopes ||= []
          @scopes_added_by_common_scopes << args.first unless @scopes_added_by_common_scopes.include?(args.first)
          impolitely_add_named_scope *args
        end
      end
    end
    
    module Rails3
      def impolitely_add_named_scope(*args)
        scope *args
      end


      def add_random_scope
        politely_add_named_scope :random, lambda { |i|
          ids = []

        
          attempts = 2 * i
          max = [i, count].min
        
          while ids.length < i && attempts >= 0
            ids << rand( max )
            ids.uniq!
            attempts -= 1
          end

          where( :id => ids )
        }
      end
      
      # Scopes for limit and offset.  Example:
      #
      # class Comment < ActiveRecord::Base
      #   add_limit_scopes
      # end
      #
      # class CommentController < ActionController::Base
      #   def recent
      #     @comments = Comment.
      def add_limit_scopes()
        # I believe Rails 3 already has a limit() scope built in
        # politely_add_named_scope :limit, lambda {|limit| {:limit => limit} }
        # politely_add_named_scope :offset, lambda {|offset| {:offset => offset } }
      end

      # Scopes dealing with "magic" created_at and updated_at columns.
      # - recent: only items created near the present time.  Default
      #    is one week, but can take a time object as an argument.
      # - recently_updated: same as recent, but for items which have
      #    recently been changed ("updated_at").  Again, defaults to
      #    one week.
      #
      # >> User.recent.length
      # => 30
      # >> User.recent( 24.hours.ago ).length
      # => 3
      def add_created_at_scopes()
        if self.column_names.include?("created_at")
          politely_add_named_scope :recent, lambda { |*args|
            where "created_at > ?", args.first || 7.days.ago
          }
          politely_add_named_scope :created_before, lambda {|t|
            where "created_at < ?", t
          }

          politely_add_named_scope :created_before_or_at, lambda { |t|
            where "created_at <= ?", t
          }

          politely_add_named_scope :created_after, lambda { |t|
            where "created_at > ?", t
          }

          politely_add_named_scope :created_after_or_at, lambda { |t|
            where "created_at >= ?", t
          }
          politely_add_named_scope :created_between, lambda {|*args|
            if(args.first.is_a?(Range))
              where :created_at => args.first 
            elsif args.length == 2
              where :created_at => args.first..args.last
            end
          }
        end
      end

      def add_updated_at_scopes()
        if self.column_names.include?("updated_at")
          politely_add_named_scope :recently_updated, lambda {|*args|
            where "updated_at > ?", args.first || 7.days.ago
          }
          politely_add_named_scope :updated_before, lambda {|t|
            where "updated_at < ?", args.first || 7.days.ago
          }
          politely_add_named_scope :updated_after, lambda {|t|
            where "updated_at > ?", t
          }
          politely_add_named_scope :updated_between, lambda {|*args|
            if(args.first.is_a?(Range))
              where :updated_at => args.first 
            elsif args.length == 2
              where :updated_at => args.first..args.last 
            end
          }
        end
      end

      # adds scopes relevant to float columns (Right now just those
      # from add_integer_or_float_scopes().
      def add_float_scopes(col)
        add_integer_or_float_scopes(col)
      end

      # adds [column]_equals scope, plus all
      # scopes from add_integer_or_float_scopes.
      #
      # Example:
      #
      # >> User.failed_login_attempts_equals(3)
      # => [#<User id: 192, login: "betty", password: .....>, #<User id: 234, login: "sam", password: .....>]
      def add_integer_scopes(col)
        add_integer_or_float_scopes(col)

        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_equals", lambda { |amt| where("#{col} = ?", amt) }
        end
      end

      # adds the following scopes to an integer column:
      #
      # - [column]_greater_than(amount)
      # - [column]_less_than(amount)
      # - [column]_in_range(*args) : takes either a range or two numbers.
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      # >> Payment.amount_greater_than(300).amount_less_than(700).length
      # => 375
      # >> Payment.in_range(300,700)
      # => 375
      # >> Payment.in_range(300..700)
      # => 375
      # >> Payment.in_range(300..600).in_reverse_id_order.limit(2)
      # => [<Payment id: 12, amount: 550, order_id: 91>,
      #     <Payment id: 27, amount: 405 order_id: 15> ]
      def add_integer_or_float_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_greater_than", lambda { |amt| where( "#{col} > ?", amt ) }
          politely_add_named_scope :"#{col}_less_than",    lambda { |amt| where( "#{col} < ?", amt ) }
          politely_add_named_scope :"#{col}_in_range",     lambda { |*args|
            if args.first.is_a?(Range)
              where :"#{col}" => args.first 
            elsif args.length == 2
              where :"#{col}" => args.first..args.last 
            else
              raise ArgumentError.new("Wrong number of arguments.")
            end
          }

          add_order_scopes(col)
        end
      end


      # adds the following scopes to an 'orderable' column (string, datetime, integer, float):
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      def add_order_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"in_#{col}_order", lambda { order("#{col}") }
          politely_add_named_scope :"in_reverse_#{col}_order", lambda { order("#{col} DESC") }
        end
      end

      # Adds scopes suitable for datetime columns:
      # - [column]_older_than(time = 7.days.ago)
      # - [column]_newer_than(time = 7.days.ago)
      # - [column]_in_past
      # - [column]_in_future
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      #
      def add_date_time_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_older_than", lambda {|*args| where( "#{col} < ?", args.first || 7.days.ago ) }
          politely_add_named_scope :"#{col}_newer_than", lambda {|*args| where( "#{col} > ?", args.first || 7.days.ago ) }
          politely_add_named_scope :"#{col}_in_past",    lambda { where( "#{col} < ?", Time.now ) }
          politely_add_named_scope :"#{col}_in_future",  lambda { where( "#{col} > ?", Time.now ) }
          add_order_scopes(col)
        end
      end

      # what about date functions.  Yesterday? Today? Tomorrow?
      # This year?  NextWeekRange?

      def add_boolean_scopes(col)
        if self.column_names.include?(col.to_s)
          # have to freeze the column name in place.  By the time lambda is evaluated,
          # col is long gone.
          politely_add_named_scope :"#{col}",     lambda { where( :"#{col}" => true ) } 
          politely_add_named_scope :"not_#{col}", lambda { where( :"#{col}" => false ) }
        end
      end

      # Adds scopes for string columns.
      # - [column]_contains(str) : includes the substring somewhere in the string
      # - [column]_starts_with(str)
      # - [column]_ends_with(str)
      # - [column]_is(str) : string exactly equals the given string
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      # >> Email.address_contains("anderson")in_reverse_address_order.limit(3)
      # => [ <Email address: 'mister_anderson@zippy.ru'>, <Email address: 'bryce_anderson@notarealaddress.com'>, <Email address: 'anderson_lumber@mail.com'>]
      # >> Email.address_starts_with("anderson").limit(2)
      # => [<Email address: 'anderson_lumber@mail.com'>, <Email address: 'andersonroo@pendragon.edu'>]
      # >> Email.address_is("jumper@thwappity.com")
      # => [<Email address: 'jumper@thwappity.com'>]
      def add_string_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_contains",    lambda { |str| where( "#{col} LIKE ?", "%#{str}%" ) }
          politely_add_named_scope :"#{col}_starts_with", lambda { |str| where( "#{col} LIKE ?", "#{str}%" ) }
          politely_add_named_scope :"#{col}_ends_with",   lambda { |str| where( "#{col} LIKE ?", "%#{str}" ) }
          politely_add_named_scope :"#{col}_is",          lambda { |str| where( :"#{col}" => str ) }
          add_order_scopes(col)
        end
      end

      def add_primary_key_scopes
        for column in self.columns
          if column.primary
            politely_add_named_scope :"#{column.name}_excludes", lambda { |ids|
                case ids
                when Integer
                  { :conditions => ["id != ?", ids] }
                when Array
                  ids = ids.map{ |item|
                  case item
                  when Integer
                    item
                  when String
                    item.to_i
                  when id.is_a?(ActiveRecord::Base)
                    item.id
                  end
                }
                end

              where "id NOT IN (?)", ids.join(',')
            }
          end
        end
      end
    end

    module Rails2
      def impolitely_add_named_scope(*args)
        named_scope *args
      end
      # Scopes for limit and offset.  Example:
      #
      # class Comment < ActiveRecord::Base
      #   add_limit_scopes
      # end
      #
      # class CommentController < ActionController::Base
      #   def recent
      #     @comments = Comment.
      def add_limit_scopes()
        politely_add_named_scope :limit, lambda {|limit| {:limit => limit} }
        politely_add_named_scope :offset, lambda {|offset| {:offset => offset } }
      end


      def add_random_scope()
        # do nothing.  Not implemented yet.
      end
      # Scopes dealing with "magic" created_at and updated_at columns.
      # - recent: only items created near the present time.  Default
      #    is one week, but can take a time object as an argument.
      # - recently_updated: same as recent, but for items which have
      #    recently been changed ("updated_at").  Again, defaults to
      #    one week.
      #
      # >> User.recent.length
      # => 30
      # >> User.recent( 24.hours.ago ).length
      # => 3
      def add_created_at_scopes()
        if self.column_names.include?("created_at")
          politely_add_named_scope :recent, lambda {|*args|
            { :conditions => ["created_at > ?", args.first || 7.days.ago] }
          }
          politely_add_named_scope :created_before, lambda {|t|
            { :conditions => ["created_at < ?", t] }
          }

          politely_add_named_scope :created_before_or_at, lambda { |t|
            { :conditions => ["created_at <= ?", t] }
          }

          politely_add_named_scope :created_after, lambda { |t|
            { :conditions => ["created_at > ?", t] }
          }

          politely_add_named_scope :created_after_or_at, lambda { |t|
            { :conditions => ["created_at >= ?", t] }
          }
          politely_add_named_scope :created_between, lambda {|*args|
            if(args.first.is_a?(Range))
              { :conditions => { :created_at => args.first } }
            elsif args.length == 2
              { :conditions => { :created_at => args.first..args.last } }
            end
          }
        end
      end

      def add_updated_at_scopes()
        if self.column_names.include?("updated_at")
          politely_add_named_scope :recently_updated, lambda {|*args|
            { :conditions => ["updated_at > ?", args.first || 7.days.ago] }
          }
          politely_add_named_scope :updated_before, lambda {|t|
            { :conditions => ["updated_at < ?", args.first || 7.days.ago] }
          }
          politely_add_named_scope :updated_after, lambda {|t|
            { :conditions => ["updated_at > ?", t] }
          }
          politely_add_named_scope :updated_between, lambda {|*args|
            if(args.first.is_a?(Range))
              { :conditions => { :updated_at => args.first } }
            elsif args.length == 2
              { :conditions => { :updated_at => args.first..args.last } }
            end
          }
        end
      end

      # adds scopes relevant to float columns (Right now just those
      # from add_integer_or_float_scopes().
      def add_float_scopes(col)
        add_integer_or_float_scopes(col)
      end

      # adds [column]_equals scope, plus all
      # scopes from add_integer_or_float_scopes.
      #
      # Example:
      #
      # >> User.failed_login_attempts_equals(3)
      # => [#<User id: 192, login: "betty", password: .....>, #<User id: 234, login: "sam", password: .....>]
      def add_integer_scopes(col)
        add_integer_or_float_scopes(col)

        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_equals",       lambda { |amt| { :conditions => ["#{col} = ?", amt] } }
        end
      end

      # adds the following scopes to an integer column:
      #
      # - [column]_greater_than(amount)
      # - [column]_less_than(amount)
      # - [column]_in_range(*args) : takes either a range or two numbers.
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      # >> Payment.amount_greater_than(300).amount_less_than(700).length
      # => 375
      # >> Payment.in_range(300,700)
      # => 375
      # >> Payment.in_range(300..700)
      # => 375
      # >> Payment.in_range(300..600).in_reverse_id_order.limit(2)
      # => [<Payment id: 12, amount: 550, order_id: 91>,
      #     <Payment id: 27, amount: 405 order_id: 15> ]
      def add_integer_or_float_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_greater_than", lambda { |amt| { :conditions => ["#{col} > ?", amt] } }
          politely_add_named_scope :"#{col}_less_than",    lambda { |amt| { :conditions => ["#{col} < ?", amt] } }
          politely_add_named_scope :"#{col}_in_range",     lambda { |*args|
            if args.first.is_a?(Range)
              { :conditions => { :"#{col}" => args.first } }
            elsif args.length == 2
              { :conditions => { :"#{col}" => args.first..args.last } }
            else
              raise ArgumentError.new("Wrong number of arguments.")
            end
          }

          add_order_scopes(col)
        end
      end


      # adds the following scopes to an 'orderable' column (string, datetime, integer, float):
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      def add_order_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"in_#{col}_order", { :order => "#{col}" }
          politely_add_named_scope :"in_reverse_#{col}_order", { :order => "#{col} DESC" }
        end
      end

      # Adds scopes suitable for datetime columns:
      # - [column]_older_than(time = 7.days.ago)
      # - [column]_newer_than(time = 7.days.ago)
      # - [column]_in_past
      # - [column]_in_future
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      #
      def add_date_time_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_older_than", lambda {|*args| { :conditions => ["#{col} < ?", args.first || 7.days.ago] } }
          politely_add_named_scope :"#{col}_newer_than", lambda {|*args| { :conditions => ["#{col} > ?", args.first || 7.days.ago] } }
          politely_add_named_scope :"#{col}_in_past",    { :conditions => ["#{col} < ?", Time.now] }
          politely_add_named_scope :"#{col}_in_future",  { :conditions => ["#{col} > ?", Time.now] }
          add_order_scopes(col)
        end
      end

      # what about date functions.  Yesterday? Today? Tomorrow?
      # This year?  NextWeekRange?

      def add_boolean_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}",     { :conditions => { :"#{col}" => true } }
          politely_add_named_scope :"not_#{col}", { :conditions => { :"#{col}" => false } }
        end
      end

      # Adds scopes for string columns.
      # - [column]_contains(str) : includes the substring somewhere in the string
      # - [column]_starts_with(str)
      # - [column]_ends_with(str)
      # - [column]_is(str) : string exactly equals the given string
      # - in_[column]_order :  from add_order_scopes
      # - in_reverse_[column]_order :  from add_order_scopes
      #
      # Examples:
      #
      # >> Email.address_contains("anderson")in_reverse_address_order.limit(3)
      # => [ <Email address: 'mister_anderson@zippy.ru'>, <Email address: 'bryce_anderson@notarealaddress.com'>, <Email address: 'anderson_lumber@mail.com'>]
      # >> Email.address_starts_with("anderson").limit(2)
      # => [<Email address: 'anderson_lumber@mail.com'>, <Email address: 'andersonroo@pendragon.edu'>]
      # >> Email.address_is("jumper@thwappity.com")
      # => [<Email address: 'jumper@thwappity.com'>]
      def add_string_scopes(col)
        if self.column_names.include?(col.to_s)
          politely_add_named_scope :"#{col}_contains",    lambda { |str| { :conditions => ["#{col} LIKE ?", "%#{str}%"] } }
          politely_add_named_scope :"#{col}_starts_with", lambda { |str| { :conditions => ["#{col} LIKE ?", "#{str}%"] } }
          politely_add_named_scope :"#{col}_ends_with",   lambda { |str| { :conditions => ["#{col} LIKE ?", "%#{str}"] } }
          politely_add_named_scope :"#{col}_is",          lambda { |str| { :conditions => { :"#{col}" => str } } }
          add_order_scopes(col)
        end
      end

      def add_primary_key_scopes
        for column in self.columns
          if column.primary
            politely_add_named_scope :"#{column.name}_excludes", lambda { |ids|
                case ids
                when Integer
                  { :conditions => ["id != ?", ids] }
                when Array
                  ids = ids.map{ |item|
                  case item
                  when Integer
                    item
                  when String
                    item.to_i
                  when id.is_a?(ActiveRecord::Base)
                    item.id
                  end
                }
                end

              { :conditions => ["id NOT IN (?)", ids.join(',')] }
            }
          end
        end
      end
    end
  end
end

