# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      module MongoidModel
        module Prunable
          # Prunes a branch off of the tree, shifting all of the elements on the right
          # back to the left so the counts still work.
          def destroy_descendants
            return if right.nil? || left.nil? || skip_before_destroy

            in_tenacious_transaction do
              # Rescue from +Mongoid::Errors::DocumentNotFound+ error as there may be a case
              # that an +object+ has already been destroyed by its parent, but objects that are
              # in memory are not aware about this.
              begin
                reload_nested_set
              rescue Mongoid::Errors::DocumentNotFound
                self.skip_before_destroy = true
                return true
              end
              # select the rows in the model that extend past the deletion point and apply a lock
              # nested_set_scope.right_of(left).only(primary_id).lock(true)

              return false unless destroy_or_delete_descendants

              # update lefts and rights for remaining nodes
              update_siblings_for_remaining_nodes

              # Reload is needed
              # because children may have updated their parent (self) during deletion.
              reload

              # Don't allow multiple calls to destroy to corrupt the set
              self.skip_before_destroy = true
            end
          end

          def destroy_or_delete_descendants
            if acts_as_nested_set_options[:dependent] == :destroy
              descendants.each do |model|
                model.skip_before_destroy = true
                model.destroy
              end
            elsif acts_as_nested_set_options[:dependent] == :restrict_with_exception
              raise Mongoid::Errors::DeleteRestriction.new(self, :children) unless leaf?
              true
            elsif acts_as_nested_set_options[:dependent] == :restrict_with_error
              unless leaf?
                record = self.class.human_attribute_name(:children).downcase
                errors.add(:base, :"delete_restriction.message", document: self, relation: record)
                return false
              end
              true
            elsif acts_as_nested_set_options[:dependent] == :nullify
              descendants.update_all(parent_column_name => nil)
            else
              descendants.delete_all
            end
          end

          def update_siblings_for_remaining_nodes
            update_siblings(:left)
            update_siblings(:right)
          end

          def update_siblings(direction)
            column_name = send("#{direction}_column_name")
            nested_set_scope.gt(column_name => right).inc(column_name => - diff)
          end

          def diff
            right - left + 1
          end
        end
      end
    end
  end
end
