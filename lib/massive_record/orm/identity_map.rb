module MassiveRecord
  module ORM

    #
    # The goal of the IdentiyMap is to make sure that the same object is not loaded twice
    # from the database, but uses the same object if you do 2.times { AClass.find(1) }.
    #
    # To get a quick introduction on IdentityMap see: http://www.martinfowler.com/eaaCatalog/identityMap.html
    #
    # You can enable / disable Identity map by doing:
    # MassiveRecord::ORM::IdentityMap.enabled = flag
    #
    module IdentityMap
      extend ActiveSupport::Concern

      class << self
        #
        # Switch to either turn on or off the identity map
        #
        def enabled=(boolean)
          Thread.current[:identity_map_enabled] = !!boolean
        end

        def enabled
          Thread.current[:identity_map_enabled]
        end
        alias enabled? enabled


        #
        # Call this with a block to ensure that IdentityMap is enabled
        # for that block and reset to it's origianl setting thereafter
        #
        def use
          original_value, self.enabled = enabled, true
          yield
        ensure
          self.enabled = original_value
        end

        #
        # Call this with a block to ensure that IdentityMap is disabled
        # for that block and reset to it's origianl setting thereafter
        #
        def without
          original_value, self.enabled = enabled, false
          yield
        ensure
          self.enabled = original_value
        end



        def get(klass, *ids)
          ids.flatten!

          case ids.length
          when 0
            raise ArgumentError.new("Must have at least one ID!")
          when 1
            get_one(klass, ids.first)
          else
            get_some(klass, ids)
          end
        end

        def add(record)
          return if record.nil?

          repository[record_class_to_repository_key(record)][record.id] = record
        end

        def remove(record)
          remove_by_id record.class, record.id
        end

        def remove_by_id(klass, id)
          repository[class_to_repository_key(klass)].delete id
        end

        delegate :clear, :to => :repository



        private

        def get_one(klass, id)
          if record = repository[class_to_repository_key(klass)][id]
            return record if klass == record.class || klass.descendants.include?(record.class)
          end
        end

        def get_some(klass, ids)
          ids.collect { |id| get_one(klass, id) }.compact
        end

        def repository
          Thread.current[:identity_map_repository] ||= Hash.new { |hash, key| hash[key] = {} }
        end

        def record_class_to_repository_key(record)
          class_to_repository_key record.class
        end

        def class_to_repository_key(klass)
          klass.base_class
        end
      end





      module ClassMethods
        private


        def find_one(id, options)
          return super unless IdentityMap.enabled? && can_use_identity_map_with?(options)

          IdentityMap.get(self, id) || IdentityMap.add(super)
        end



        def can_use_identity_map_with?(finder_options)
          !finder_options.has_key?(:select)
        end
      end



      module InstanceMethods
        def reload
          IdentityMap.remove(self) if IdentityMap.enabled?
          super
        end

        def destroy
          return super unless IdentityMap.enabled?

          super.tap { IdentityMap.remove(self) }
        end
        alias_method :delete, :destroy

        private


        def create
          return super unless IdentityMap.enabled?

          super.tap { IdentityMap.add(self) }
        end
      end
    end
  end
end
