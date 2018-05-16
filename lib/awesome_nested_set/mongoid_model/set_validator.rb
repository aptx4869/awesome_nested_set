# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      # set valitator
      class SetValidator
        def initialize(model)
          @model = model
        end

        def valid?
          aggregation.none?
        end

        private

        attr_reader :model

        delegate(
          :parent_column_name, :primary_column_name,
          :left_column_name, :right_column_name,
          to: :model
        )

        def aggregation
          model.collection.aggregate(
            [only_nested_set_fields, lookup_scope, project_scope, filter_scope].flatten
          )
        end

        def only_nested_set_fields
          {
            '$project': {
              primary_column_name => 1,
              left_column_name    => 1,
              right_column_name   => 1,
              parent_column_name  => 1
            }
          }
        end

        def lookup_scope
          [
            {
              '$lookup': {
                from: model.collection.name,
                let: {
                  foreignField: "$#{parent_column_name}"
                },
                'as' => 'parent',
                pipeline: [
                  {
                    '$match': {
                      '$expr': {
                        '$eq': ["$#{primary_column_name}", '$$foreignField']
                      }
                    }
                  }
                ]
              }
            },
            { '$unwind': { path: '$parent', preserveNullAndEmptyArrays: true } }
          ]
        end

        def project_scope
          {
            '$project': {
              primary_column_name => 1,
              left_column_name    => 1,
              right_column_name   => 1,
              parent_column_name  => 1,
              'parent': 1,
              parent_left: "$parent.#{left_column_name}",
              parent_right: "$parent.#{right_column_name}"
            }
          }
        end

        def filter_scope
          {
            '$match': {
              '$or': [
                { left_column_name => nil },
                { right_column_name => nil },
                left_bound_greater_than_right,
                parent_not_null_and_bounds_outside_parent
              ]
            }
          }
        end

        def left_bound_greater_than_right
          { '$expr': { '$gte': ["$#{left_column_name}", "$#{right_column_name}"] } }
        end

        def parent_not_null
          arel_table[parent_column_name].not_eq(nil)
        end

        def parent_not_null_and_bounds_outside_parent
          {
            parent: { '$exists': true },
            '$or': [
              { '$expr': { '$lte': ["$#{left_column_name}", '$parent_left'] } },
              { '$expr': { '$gte': ["$#{right_column_name}", '$parent_right'] } }
            ]
          }
        end
      end
    end
  end
end
