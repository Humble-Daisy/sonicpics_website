# frozen_string_literal: true

require "rake"

# Rake APPENDS an action block to a task every time its .rake file is read, and
# Rake::Task#reenable only clears the invoked flag — it does not dedupe actions.
# So a second Rails.application.load_tasks makes every task run its body twice,
# and a task whose body calls `abort` raises SystemExit on the second pass,
# terminating the RSpec run mid-example while the summary still prints
# "0 failures". Load once per process instead.
module RakeTasks
  class << self
    def load_once
      return if @loaded

      Rails.application.load_tasks
      @loaded = true
    end

    def invoke(name, *args)
      Rake::Task[name].reenable
      Rake::Task[name].invoke(*args)
    end
  end
end
