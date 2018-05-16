# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      module MongoidModel
        # move service
        class Move
          attr_reader :target, :position, :instance

          def initialize(target, position, instance)
            @target = target
            @position = position
            @instance = instance
          end

          def move
            prevent_impossible_move
            self.distance = bound - left
            self.edge = bound > right ? bound - 1 : bound
            # there would be no change
            return if [right, left].include? edge

            collection.bulk_write(bulk_operations, ordered: false)
          end

          protected

          attr_accessor :distance, :edge

          private

          def width
            right - left + 1
          end

          delegate(
            :left, :right, :left_column_name, :right_column_name,
            :quoted_left_column_name, :quoted_right_column_name,
            :quoted_parent_column_name, :parent_column_name,
            :nested_set_scope_without_default_scope, :collection,
            :primary_column_name, :quoted_primary_column_name, :primary_id,
            to: :instance
          )

          delegate :acts_as_nested_set_base_class, to: 'instance.class', prefix: :instance

          def primary_key
            primary_column_name == :id ? '_id' : primary_column_name
          end

          alias scope nested_set_scope_without_default_scope

          def bulk_operations
            [
              allocate_space,
              move_nodes,
              fill_in_the_gap,
              case_condition_for_parent
            ].flatten
          end

          def allocate_space
            [
              {
                update_many: {
                  filter: scope.gte(left_column_name => bound).selector,
                  update: { '$inc' => { left_column_name => width } }.merge(update_with_timestamp)
                }
              },
              {
                update_many: {
                  filter: scope.gte(right_column_name => bound).selector,
                  update: { '$inc' => { right_column_name => width } }.merge(update_with_timestamp)
                }
              }
            ]
          end

          def move_nodes
            # moving backwards
            left_bound = left
            if distance.negative?
              self.distance -= width
              left_bound += width
            end

            {
              update_many: {
                filter: scope.and(
                  left_column_name => { '$gte' => left_bound },
                  right_column_name => { '$lt' => left_bound + width }
                ).selector,
                update: { '$inc' => {
                  left_column_name => distance,
                  right_column_name => distance
                } }.merge(update_with_timestamp)
              }
            }
          end

          def fill_in_the_gap
            gap = - width
            [
              {
                update_many: {
                  filter: scope.gt(left_column_name => right).selector,
                  update: { '$inc' => { left_column_name => gap } }.merge(update_with_timestamp)
                }
              },
              {
                update_many: {
                  filter: scope.gt(right_column_name => right).selector,
                  update: { '$inc' => { right_column_name => gap } }.merge(update_with_timestamp)
                }
              }
            ]
          end

          def update_with_timestamp
            @update_with_timestamp ||= {}.tap do |result|
              if instance_acts_as_nested_set_base_class.include?(Mongoid::Timestamps::Updated)
                result['$set'] = { updated_at_field => Time.now.utc }
              end
            end
          end

          def updated_at_field
            instance.database_field_name :updated_at
          end

          def case_condition_for_parent
            {
              update_one: {
                filter: scope.where(primary_key => instance.primary_id).selector,
                update: {
                  '$set' => { parent_column_name => new_parent_id }
                    .merge(update_with_timestamp['$set'].to_h)
                }
              }
            }
          end

          def root?
            position == :root
          end

          def new_parent_id
            case position
            when :child then target.primary_id
            when :root  then nil
            else target[parent_column_name]
            end
          end

          # error class for impossible move
          class ImpossibleMove < Mongoid::Errors::MongoidError
          end

          # error class for invalid position
          class InvalidPosition < Mongoid::Errors::MongoidError
            def initialize(position)
              @position = position
            end

            def message
              "Position should be :child, :left, :right or :root ('#{@position}' received)."
            end
          end

          def prevent_impossible_move
            return if root? || instance.move_possible?(target)
            raise ImpossibleMove, 'Impossible move, target node cannot be inside moved tree.'
          end

          def bound
            target_right = right(target)
            case position
            when :child then target_right
            when :left then  left(target)
            when :right then target_right + 1
            when :root then  scope.pluck(right_column_name).max + 1
            else
              raise InvalidPosition, position
            end
          end
        end
      end
    end
  end
end
