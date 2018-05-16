# frozen_string_literal: true

# Mixed into both classes and instances to provide easy access to the column names
module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      # no comment
      module Fields
        %i(depth left parent primary right).each do |column|
          define_method "#{column}_column_name" do
            acts_as_nested_set_options[:"#{column}_column"].to_sym
          end
        end

        def order_column
          acts_as_nested_set_options[:order_column] || left_column_name
        end

        def scope_column_names
          Array(acts_as_nested_set_options[:scope])
        end

        def counter_cache_column_name
          acts_as_nested_set_options[:counter_cache]
        end

        alias order_column_name order_column

        %i(depth left order parent primary right).each do |column|
          define_method "quoted_#{column}_column_name" do
            %('#{send("#{column}_column_name")}')
          end
        end

        def model_connection
          is_a?(Class) ? connection : self.class.connection
        end
      end
    end
  end
end
