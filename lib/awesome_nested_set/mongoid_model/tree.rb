# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      module MongoidModel
        class Tree
          attr_reader :model, :validate_nodes
          attr_accessor :indices

          delegate(
            :left_column_name, :right_column_name, :parent_column_name,
            :order_for_rebuild, :scope_for_rebuild, :counter_cache_column_name,
            to: :model
          )

          def initialize(model, validate_nodes)
            @model = model
            @validate_nodes = validate_nodes
            @indices = {}
          end

          def rebuild!
            # Don't rebuild a valid tree.
            return true if model.valid?

            root_nodes.each do |root_node|
              # setup index for this scope
              indices[scope_for_rebuild.call(root_node)] ||= 0
              set_left_and_rights(root_node)
              reset_counter_cache(root_node)
            end
          end

          private

          def increment_indice!(node)
            indices[scope_for_rebuild.call(node)] += 1
          end

          def set_left_and_rights(node)
            set_left!(node)
            # find
            node_children(node).each { |n| set_left_and_rights(n) }
            set_right!(node)

            node.save!(validate: validate_nodes)
          end

          def node_children(node)
            scope = scope_for_rebuild.call(node)
            model
              .where(scope.merge(parent_column_name => node.primary_id))
              .order(order_for_rebuild)
          end

          def root_nodes
            model.where(parent_column_name => nil).order(order_for_rebuild)
          end

          def set_left!(node)
            node[left_column_name] = increment_indice!(node)
          end

          def set_right!(node)
            node[right_column_name] = increment_indice!(node)
          end

          def reset_counter_cache(node)
            return unless counter_cache_column_name
            node.class.reset_counters(node.id, :children)

            node.children.each do |child|
              reset_counter_cache(child)
            end
          end
        end
      end
    end
  end
end
