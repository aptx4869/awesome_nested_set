# frozen_string_literal: true

require 'awesome_nested_set/mongoid_model/set_validator'

module CollectiveIdea
  module Acts
    module NestedSet
      module MongoidModel
        module Validatable
          def valid?
            left_and_rights_valid? && no_duplicates_for_columns? && all_roots_valid?
          end

          def left_and_rights_valid?
            SetValidator.new(self).valid?
          end

          def no_duplicates_for_columns?
            collection.aggregate(
              [
                {
                  '$project': {
                    primary_column_name => 1,
                    left_column_name    => 1,
                    right_column_name   => 1
                  }
                },
                {
                  '$group': {
                    _id: {
                      left_column_name => "$#{left_column_name}",
                      right_column_name => "$#{right_column_name}"
                    },
                    left: {
                      '$sum': { '$cond': { if: "$#{left_column_name}", then: 1, else: 0 } }
                    },
                    right: {
                      '$sum': { '$cond': { if: "$#{right_column_name}", then: 1, else: 0 } }
                    }
                  }
                },
                { '$match': { '$or': [{ left: { '$gt': 1 } }, { right: { '$gt': 1 } }] } }
              ]
            ).none?
          end

          # Wrapper for each_root_valid? that can deal with scope.
          def all_roots_valid?
            if acts_as_nested_set_options[:scope]
              all_roots_valid_by_scope?(roots)
            else
              each_root_valid?(roots)
            end
          end

          def all_roots_valid_by_scope?(roots_to_validate)
            roots_grouped_by_scope(roots_to_validate).all? do |_scope, grouped_roots|
              each_root_valid?(grouped_roots)
            end
          end

          def each_root_valid?(roots_to_validate)
            left_column = acts_as_nested_set_options[:left_column]
            reordered_roots = roots_reordered_by_column(roots_to_validate, left_column)
            left = right = 0
            reordered_roots.all? do |root|
              (root.left > left && root.right > right).tap do
                left = root.left
                right = root.right
              end
            end
          end

          private

          def roots_grouped_by_scope(roots_to_group)
            roots_to_group.group_by do |record|
              scope_column_names.collect { |col| record.send(col) }
            end
          end

          def roots_reordered_by_column(roots_to_reorder, column)
            if roots_to_reorder.respond_to?(:reorder) # Mongoid's relation
              roots_to_reorder.reorder(order_column => 1)
            elsif roots_to_reorder.respond_to?(:sort) # Array
              roots_to_reorder.sort { |a, b| a.send(column) <=> b.send(column) }
            else
              roots_to_reorder
            end
          end

          def scope_string
            Array(acts_as_nested_set_options[:scope]).map do |c|
              connection.quote_column_name(c)
            end.push(nil).join(', ')
          end
        end
      end
    end
  end
end
