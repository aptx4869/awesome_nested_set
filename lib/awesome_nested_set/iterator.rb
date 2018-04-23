# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      class Iterator
        attr_reader :objects

        def initialize(objects)
          @objects = objects
        end

        def each_with_level
          path = [nil]
          objects.each do |object|
            parent_id_ = object.parent_id
            if parent_id_ != path.last
              # we are on a new level, did we descend or ascend?
              if path.include?(parent_id_)
                # remove wrong tailing paths elements
                path.pop while path.last != parent_id_
              else
                path << parent_id_
              end
            end
            yield(object, path.length - 1)
          end
        end
      end
    end
  end
end
