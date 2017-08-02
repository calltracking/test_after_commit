module TestAfterCommit::DatabaseStatements
  def transaction(*)
    @test_open_transactions ||= 0

    super do
      begin
        @test_open_transactions += 1
        if ActiveRecord::VERSION::MAJOR == 3
          @_current_transaction_records.push([]) if @_current_transaction_records.empty?
        end
        result = yield if block_given?
      rescue Exception
        rolled_back = true
        raise
      ensure
        begin
          @test_open_transactions -= 1
          if @test_open_transactions == 0 && !rolled_back
            if TestAfterCommit.enabled
              test_commit_records
            elsif ActiveRecord::VERSION::MAJOR == 3
              @_current_transaction_records.clear
            end
          end
        ensure
          result
        end
      end
    end
  end

  def test_commit_records
    if ActiveRecord::VERSION::MAJOR == 3
      commit_transaction_records
    else
      # To avoid an infinite loop, we need to copy the transaction locally, and clear out
      # `records` on the copy that stays in the AR stack. Otherwise new
      # transactions inside a commit callback will cause an infinite loop.
      #
      # This is because we're re-using the transaction on the stack, before
      # it's been popped off and re-created by the AR code.
      original = @transaction || @transaction_manager.current_transaction
      transaction = original.dup
      transaction.instance_variable_set(:@records, transaction.records.dup) # deep clone of records array
      original.records.clear                                                # so that this clear doesn't clear out both copies
      transaction.commit_records
    end
  end
end
