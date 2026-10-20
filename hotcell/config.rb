# frozen_string_literal: true

# deadline and queue_wait are seconds, memory and file_size bytes; the cell must answer (queue_wait + deadline + 1)
# before the app's 30s timeout in config/initializers/hotcell.rb, or every boot warns. /docs/developer/hot-cell
HotCell.limits concurrency: 4, queue_size: 8, queue_wait: 5, deadline: 20, memory: 1536 * 1024**2
