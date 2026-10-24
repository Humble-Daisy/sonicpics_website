require "spec_helper"
require "yaml"

# The importmap audit must fail closed yet tell a registry outage from an advisory (#984).
# Enumerates every workflow running `bin/importmap audit` (#1041).
RSpec.describe "every workflow running the JS advisory audit" do
  workflow_dir = File.expand_path("../../.github/workflows", __dir__)

  audit_sites = Dir[File.join(workflow_dir, "*.yml")].sort.flat_map do |path|
    workflow = YAML.safe_load_file(path, aliases: true)
    (workflow["jobs"] || {}).flat_map do |job_name, job|
      Array(job["steps"])
        .select { |step| step["run"].to_s.include?("importmap audit") }
        .map { |step| { label: "#{File.basename(path)} / #{job_name}", step: step } }
    end
  end

  # POSITIVE CONTROL: naming the required gate means a broken parser cannot pass.
  it "finds the required per-PR gate among the audit sites" do
    expect(audit_sites.map { |site| site[:label] }).to include("ci.yml / static"),
      "the workflow scan no longer sees ci.yml's static job — with the enumeration " \
      "broken, every contract below would silently stop being checked. Found: " \
      "#{audit_sites.map { |site| site[:label] }.inspect}"
  end

  audit_sites.each do |site|
    context site[:label] do
      let(:audit_step) { site[:step] }

      it "has a step running bin/importmap audit" do
        expect(audit_step).not_to be_nil,
          "expected this job to have a step whose `run:` invokes bin/importmap audit"
      end

      it "retries the registry a bounded number of times before giving up" do
        expect(audit_step["run"]).to include("for i in 1 2 3"),
          "expected the audit step's `run:` to contain a bounded retry loop (`for i in 1 2 3`), " \
          "not an unbounded retry or a single unretried attempt"
      end

      it "names a transport failure distinctly from a real advisory" do
        expect(audit_step["run"]).to include("REGISTRY UNREACHABLE"),
          "expected the audit step to print the literal `REGISTRY UNREACHABLE` when retries are " \
          "exhausted, so a registry hiccup reads differently from a real advisory in the job log"
      end

      it "ends the step in exit 1 so a transport failure still fails the run" do
        expect(audit_step["run"].strip).to end_with("exit 1"),
          "expected the audit step's `run:` to end in `exit 1` — an audit that did not actually " \
          "run must never report success"
      end

      it "never exits 0 outside the success branch" do
        exit_0_occurrences = audit_step["run"].scan(/exit 0/)

        expect(exit_0_occurrences.length).to eq(1),
          "expected exactly one `exit 0` in the audit step, gated behind a successful audit " \
          "(`bin/importmap audit && exit 0`); found #{exit_0_occurrences.length}"
        expect(audit_step["run"]).to match(/importmap audit\s*&&\s*exit 0/),
          "expected the sole `exit 0` to be the success branch immediately following a " \
          "successful `bin/importmap audit`, never a bare fallback"
      end

      it "does not set continue-on-error, which would silently mask a real advisory" do
        expect(audit_step.key?("continue-on-error")).to be(false),
          "expected the audit step not to set continue-on-error — that would let a real " \
          "advisory pass silently"
      end
    end
  end
end
