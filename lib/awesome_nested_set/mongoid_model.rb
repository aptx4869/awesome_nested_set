# frozen_string_literal: true

require 'awesome_nested_set/fields'
require 'awesome_nested_set/mongoid_model/prunable'
require 'awesome_nested_set/mongoid_model/movable'
require 'awesome_nested_set/mongoid_model/transactable'
require 'awesome_nested_set/mongoid_model/relatable'
require 'awesome_nested_set/mongoid_model/rebuildable'
require 'awesome_nested_set/mongoid_model/validatable'
require 'awesome_nested_set/iterator'

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      module MongoidModel
        extend ActiveSupport::Concern

        included do
          include Fields
          extend Fields
          extend Validatable
          extend Rebuildable
          include Movable
          include Prunable
          include Relatable
          include Transactable
        end

        module ClassMethods
          def associate_parents(objects)
            return objects unless objects.all? { |o| o.respond_to?(:association) }

            id_indexed = objects.index_by(&primary_column_name.to_sym)
            objects.each do |object|
              association = object.association(:parent)
              parent = id_indexed[object.parent_id]

              if !association.loaded? && parent
                association.target = parent
                add_to_inverse_association(association, parent)
              end
            end
          end

          def add_to_inverse_association(association, record)
            inverse_reflection = association.send(:inverse_reflection_for, record)
            inverse = record.association(inverse_reflection.name)
            inverse.target << association.owner
            inverse.loaded!
          end

          def children_of(parent_id)
            where(parent_column_name => parent_id)
          end

          # Iterates over tree elements and determines the current level in the tree.
          # Only accepts default ordering, odering by an other column than lft
          # does not work. This method is much more efficent than calling level
          # because it doesn't require any additional database queries.
          #
          # Example:
          #    Category.each_with_level(Category.root.self_and_descendants) do |o, level|
          #
          def each_with_level(objects, &block)
            Iterator.new(objects).each_with_level(&block)
          end

          def leaves
            nested_set_scope.where(
              "this['#{right_column_name}'] - this['#{left_column_name}'] == 1"
            )
          end

          def left_of(node)
            lt left_column_name => node
          end

          def left_of_right_side(node)
            lte right_column_name => node
          end

          def right_of(node)
            gte left_column_name => node
          end

          def nested_set_scope(options = {})
            options = { order: { order_column => 1 } }.merge(options)

            where(options[:conditions]).order(options.delete(:order))
          end

          def primary_key_scope(id)
            where primary_column_name => id
          end

          def root
            roots.first
          end

          def roots
            nested_set_scope.children_of nil
          end
        end

        # Any instance method that returns a collection makes use of Rails 2.1's named_scope
        # (which is bundled for Rails 2.0), so it can be treated as a finder.
        #
        #   category.self_and_descendants.count
        #   category.ancestors.find(:all, :conditions => "name like '%foo%'")
        # Value of the parent column
        def parent_id(target = self)
          target[parent_column_name]
        end

        def primary_id(target = self)
          target[primary_column_name]
        end

        # Value of the left column
        def left(target = self)
          target[left_column_name]
        end

        # Value of the right column
        def right(target = self)
          target[right_column_name]
        end

        # Returns true if this is a root node.
        def root?
          parent_id.nil?
        end

        # Returns true is this is a child node
        def child?
          !root?
        end

        # Returns true if this is the end of a branch.
        def leaf?
          persisted? && right.to_i - left.to_i == 1
        end

        # All nested set queries should use this nested_set_scope, which
        # performs finds on the base Mongoid class, using the :scope
        # declared in the acts_as_nested_set declaration.
        def nested_set_scope(options = {})
          if (scopes = Array(acts_as_nested_set_options[:scope])).any?
            options[:conditions] = scopes.inject({}) do |conditions, attr|
              conditions.merge attr => self[attr]
            end
          end

          self.class.acts_as_nested_set_base_class.nested_set_scope options
        end

        # Separate an other `nested_set_scope` for unscoped model
        # because normal query still need activerecord `default_scope`
        # Only activerecord callbacks need unscoped model to handle the nested set records
        # And class level `nested_set_scope` seems just for query `root` `child` .. etc
        # I think we don't have to provide unscoped `nested_set_scope` in class level.
        def nested_set_scope_without_default_scope(*args)
          self.class.acts_as_nested_set_base_class.unscoped do
            nested_set_scope(*args)
          end
        end

        def to_text
          self_and_descendants.map do |node|
            "#{'*' * (node.level + 1)} #{node.primary_id} #{node.to_s} (#{node.parent_id}, #{node.left}, #{node.right})"
          end.join("\n")
        end

        protected

        def without_self(scope)
          return scope if new_record?
          scope.ne(primary_column_name => primary_id)
        end

        def store_new_parent
          @move_to_new_parent_id = send("#{parent_column_name}_changed?") ? parent_id : false
          true # force callback to return true
        end

        def with_depth_column?
          nested_set_scope.serializers.keys.map(&:to_s).include?(depth_column_name.to_s)
        end

        def right_most_node
          @right_most_node ||= nested_set_scope_without_default_scope(
            order: { right_column_name => :desc }
          ).first
        end

        def right_most_bound
          @right_most_bound ||= begin
                                  return 0 if right_most_node.nil?

                                  right_most_node
                                  right_most_node[right_column_name] || 0
                                end
        end

        def set_depth!
          return unless with_depth_column?

          in_tenacious_transaction do
            reload
            update_depth(level)
          end
        end

        def set_depth_for_self_and_descendants!
          return unless with_depth_column?

          in_tenacious_transaction do
            reload
            # self_and_descendants.select(primary_column_name).lock(true)
            old_depth = self[depth_column_name] || 0
            new_depth = level
            update_depth(new_depth)
            change_descendants_depth!(new_depth - old_depth)
            new_depth
          end
        end

        def update_depth(depth)
          nested_set_scope
            .primary_key_scope(primary_id)
            .update_all(depth_column_name => depth)
          self[depth_column_name] = depth
        end

        def change_descendants_depth!(diff)
          return unless !leaf? && diff != 0
          depth_increment = diff.abs * [1, 1, -1][diff <=> 0]
          descendants.inc(depth_column_name => depth_increment)
        end

        def update_counter_cache
          return unless acts_as_nested_set_options[:counter_cache]

          # Decrease the counter for all old parents
          if old_parent = parent
            self.class.decrement_counter(acts_as_nested_set_options[:counter_cache], old_parent)
          end

          # Increase the counter for all new parents
          return unless new_parent = reload.parent
          self.class.increment_counter(acts_as_nested_set_options[:counter_cache], new_parent)
        end

        def set_default_left_and_right
          # adds the new node to the right of all existing nodes
          self[left_column_name] = right_most_bound + 1
          self[right_column_name] = right_most_bound + 2
        end

        # reload left, right, and parent
        def reload_nested_set
          reload
        end

        def reload_target(target, position)
          if target.is_a? self.class.acts_as_nested_set_base_class
            target.reload
          elsif position != :root
            nested_set_scope_without_default_scope.where(primary_column_name => target).first
          end
        end
      end
    end
  end
end
