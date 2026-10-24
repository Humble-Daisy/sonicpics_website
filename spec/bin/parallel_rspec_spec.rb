require "rails_helper"

# `load` defines the class without running it (bottom-of-file guard), matching
# the bin/deploy-guide spec's pattern of exercising bin scripts directly.
load Rails.root.join("bin/parallel-rspec")

RSpec.describe ParallelRspecRunner do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:counts_dir) { workdir.join("counts") }
  let(:dry_run_json) { workdir.join("dry_run.json") }
  let(:runner) { described_class.new(counts_dir: counts_dir, dry_run_json: dry_run_json) }

  after { FileUtils.remove_entry(workdir) }

  def write_counts(counts_by_worker)
    FileUtils.mkdir_p(counts_dir)
    counts_by_worker.each { |worker, count| counts_dir.join("#{worker}.count").write(count.to_s) }
  end

  def write_dry_run(example_count)
    FileUtils.mkdir_p(dry_run_json.dirname)
    dry_run_json.write({ summary: { example_count: example_count } }.to_json)
  end

  describe ".shard_files (#495 CI sharding)" do
    let(:files) { %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb spec/d_spec.rb] }

    it "partitions files into disjoint shards whose union is the input" do
      shards = (0..1).map { |i| described_class.shard_files(files, runtimes: {}, count: 2, index: i) }

      expect(shards.flatten.sort).to eq(files.sort)
      expect(shards[0] & shards[1]).to be_empty
    end

    it "balances by recorded runtime, not file count" do
      runtimes = { "spec/a_spec.rb" => 100.0, "spec/b_spec.rb" => 5.0,
                   "spec/c_spec.rb" => 5.0, "spec/d_spec.rb" => 5.0 }
      shard_with_a = (0..1).map { |i| described_class.shard_files(files, runtimes: runtimes, count: 2, index: i) }
                           .find { |s| s.include?("spec/a_spec.rb") }

      expect(shard_with_a).to eq(%w[spec/a_spec.rb]),
        "the 100s file should sit alone while the three 5s files share the other shard"
    end

    it "is deterministic across calls (same input, same shards)" do
      first  = described_class.shard_files(files, runtimes: {}, count: 2, index: 0)
      second = described_class.shard_files(files, runtimes: {}, count: 2, index: 0)

      expect(first).to eq(second)
    end

    it "falls back to file size when a file has no recorded runtime" do
      expect {
        described_class.shard_files(files, runtimes: {}, count: 2, index: 0)
      }.not_to raise_error
    end
  end

  describe "#expected_count" do
    it "reads the example count from the dry-run JSON" do
      write_dry_run(3502)
      expect(runner.expected_count).to eq(3502)
    end
  end

  describe "#executed_count" do
    it "sums every worker's count file" do
      write_counts("1" => 900, "2" => 880, "3" => 872, "4" => 850)
      expect(runner.executed_count).to eq(3502)
    end
  end

  # Stubbed so these examples don't print the runner's progress banners into
  # the suite's own output, where they read as a real build/parity result.
  before { allow(runner).to receive(:puts) }

  describe "#build_assets!" do
    it "passes silently when the Tailwind build succeeds" do
      allow(runner).to receive(:system).and_return(true)

      expect { runner.build_assets! }.not_to raise_error
    end

    it "aborts rather than running a suite that would fail on missing CSS" do
      allow(runner).to receive(:system).and_return(false)

      expect { runner.build_assets! }.to raise_error(SystemExit) do |error|
        expect(error.status).not_to eq(0)
      end
    end
  end

  # Ordering is the invariant, not just presence: lefthook.yml pipes
  # tailwind_build ahead of rspec because a build racing the workers leaves
  # them reading a partial stylesheet and reporting phantom axe violations.
  # Building once here, before any worker forks, is the same guarantee.
  it "prepares the worker databases and builds assets before running the suite" do
    called = []
    allow(runner).to receive(:reset_artifacts)
    allow(runner).to receive(:enumerate!)
    allow(runner).to receive(:expected_count).and_return(0)
    allow(runner).to receive(:verify_count!)
    allow(runner).to receive(:enforce_coverage!)
    allow(runner).to receive(:prepare_databases!) { called << :prepare }
    allow(runner).to receive(:build_assets!) { called << :build }
    allow(runner).to receive(:run_suite!) { called << :suite }

    runner.run

    expect(called).to eq([ :prepare, :build, :suite ])
  end

  describe "#prepare_databases!" do
    it "reloads the schema and seeds into every worker database in one pass" do
      expect(runner).to receive(:system)
        .with("bundle", "exec", "rake", "parallel:setup").and_return(true)

      runner.prepare_databases!
    end

    it "aborts rather than running the suite against databases it could not seed" do
      allow(runner).to receive(:system).and_return(false)

      expect { runner.prepare_databases! }.to raise_error(SystemExit) do |error|
        expect(error.status).not_to eq(0)
      end
    end
  end

  describe "#run_suite! under an explicit SEED (#867)" do
    # A replay must be deterministic from the working tree alone: the normal
    # run groups workers by the LIVE runtime log, which changes between runs.
    it "pins worker grouping to file size so the replay's mapping cannot drift" do
      captured = nil
      allow(runner).to receive(:system) { |*args| captured = args; true }
      original = ENV["SEED"]
      ENV["SEED"] = "12345"
      runner.send(:run_suite!)
      expect(captured.each_cons(2)).to include([ "--group-by", "filesize" ])
    ensure
      original.nil? ? ENV.delete("SEED") : ENV["SEED"] = original
    end

    it "leaves normal runs on runtime-balanced grouping" do
      captured = nil
      allow(runner).to receive(:system) { |*args| captured = args; true }
      original = ENV["SEED"]
      ENV.delete("SEED")
      runner.send(:run_suite!)
      expect(captured).not_to include("--group-by")
    ensure
      ENV["SEED"] = original unless original.nil?
    end
  end

  describe "#verify_count!" do
    it "passes silently when executed matches expected" do
      write_dry_run(10)
      write_counts("1" => 4, "2" => 6)
      expect { runner.verify_count! }.not_to raise_error
    end

    # Same reasoning as the `puts` stub above, for the one path it cannot
    # reach: `abort` writes to $stderr directly, so stubbing `puts` does not
    # silence it. Uncaptured, this example prints
    #   "example-count mismatch — expected 10, ran 9 ... worker 1: 4, worker 2: 5"
    # into every suite run's stderr, where it reads as a genuine splitter
    # failure — it has already cost one full false-alarm investigation into
    # whether CI was silently under-testing.
    #
    # Capturing it also lets us assert the diagnostic's CONTENT, which nothing
    # did before: the counts and the per-worker breakdown are the whole reason
    # the message exists, and an empty or countless abort would have passed.
    it "aborts with a diagnostic naming the counts and the per-worker split" do
      write_dry_run(10)
      write_counts("1" => 4, "2" => 5)

      captured = StringIO.new
      original_stderr, $stderr = $stderr, captured
      begin
        expect { runner.verify_count! }.to raise_error(SystemExit) do |error|
          expect(error.status).not_to eq(0)
        end
      ensure
        $stderr = original_stderr
      end

      expect(captured.string).to include("expected 10, ran 9")
      expect(captured.string).to include("worker 1: 4, worker 2: 5")
    end
  end
end
