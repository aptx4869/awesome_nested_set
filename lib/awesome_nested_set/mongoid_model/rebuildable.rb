# frozen_string_literal: true

require 'awesome_nested_set/mongoid_model/tree'

module CollectiveIdea
  module Acts
    module NestedSet
      module MongoidModel
        module Rebuildable
          # Rebuilds the left & rights if unset or invalid.
          # Also very useful for converting from acts_as_tree.
          def rebuild!(validate_nodes = true)
            # default_scope with order may break database queries
            # so we do all operation without scope
            unscoped do
              Tree.new(self, validate_nodes).rebuild!
            end
          end

          def scope_for_rebuild
            if acts_as_nested_set_options[:scope]
              proc { |node|
                scope_column_names.each_with_object({}) do |column_name, hash|
                  column_value = node.send(column_name)
                  hash[column_name] = column_value
                end
              }
            else

              proc { {} }
            end
          end

          def order_for_rebuild
            # 1 for ascending or -1 for descending
            {
              left_column_name => 1,
              right_column_name => 1,
              primary_column_name => 1
            }
          end
        end
      end
    end
  end
end
