# frozen_string_literal: true

module CollectiveIdea #:nodoc:
  module Acts #:nodoc:
    module NestedSet #:nodoc:
      module MongoidModel
        module Transactable
          class OpenTransactionsIsNotZero < Mongoid::Errors::MongoidError
          end

          class DeadlockDetected < Mongoid::Errors::MongoidError
          end

          protected

          def in_tenacious_transaction(&block)
            retry_count = 0
            begin
              atomically(&block)
            rescue CollectiveIdea::Acts::NestedSet::MongoidModel::Move::ImpossibleMove
              raise
            rescue Mongoid::Errors::MongoidError => error
              # raise OpenTransactionsIsNotZero, error.message unless self.class.connection.open_transactions.zero?
              raise unless error.message =~ /[Dd]eadlock|Lock wait timeout exceeded/
              raise DeadlockDetected, error.message unless retry_count < 10
              retry_count += 1
              logger.info "Deadlock detected on retry #{retry_count}, restarting transaction"
              sleep(rand(retry_count) * 0.1) # Aloha protocol
              retry
            end
          end
        end
      end
    end
  end
end
