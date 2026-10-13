module Operations
  # Fork seam (merge=ours): a fork lists its own operations pages as [label, path] pairs, rendered after the
  # template's in layouts/operations. Replace this file wholesale; see /docs/developer/forking.
  module ForkNavHelper
    def operations_fork_nav_items = []
  end
end
